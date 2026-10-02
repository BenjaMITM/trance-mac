import AVFoundation
import Synchronization

private struct Tone: Sendable {
    var center: Double; var binaural: Double; var pulse: Double; var amplitude: Double
    var leftPhase = 0.0; var rightPhase = 0.0; var pulsePhase = 0.0
}
private struct SynthState: Sendable {
    var tones: [Tone] = []; var targets: [Tone] = []
    var gain = 0.0; var targetGain = 0.0; var remaining = 0
    var paused = false; var muted = false
    mutating func sample(rate: Double, clamp: Bool = true) -> (Float, Float) {
        guard !paused else { return (0,0) }
        var left = 0.0, right = 0.0
        let blend = remaining > 0 ? 1/Double(remaining) : 1
        gain += (targetGain-gain)*blend
        for i in tones.indices {
            let target = i < targets.count ? targets[i] : Tone(center: tones[i].center,binaural: tones[i].binaural,pulse: tones[i].pulse,amplitude: 0)
            tones[i].center += (target.center-tones[i].center)*blend
            tones[i].binaural += (target.binaural-tones[i].binaural)*blend
            tones[i].pulse += (target.pulse-tones[i].pulse)*blend
            tones[i].amplitude += (target.amplitude-tones[i].amplitude)*blend
            let t = tones[i]
            let gateL = t.pulse > 0 ? (1+cos(t.pulsePhase))*0.5 : 1
            let gateR = t.pulse > 0 ? (1-cos(t.pulsePhase))*0.5 : 1
            left += sin(t.leftPhase)*gateL*t.amplitude; right += sin(t.rightPhase)*gateR*t.amplitude
            tones[i].leftPhase = (t.leftPhase+2 * .pi*(t.center-t.binaural/2)/rate).truncatingRemainder(dividingBy: 2 * .pi)
            tones[i].rightPhase = (t.rightPhase+2 * .pi*(t.center+t.binaural/2)/rate).truncatingRemainder(dividingBy: 2 * .pi)
            tones[i].pulsePhase = (t.pulsePhase+2 * .pi*t.pulse/rate).truncatingRemainder(dividingBy: 2 * .pi)
        }
        if remaining > 0 { remaining -= 1 }
        if muted { return (0,0) }
        return clamp ? (Float(max(-0.8,min(0.8,left*gain))),Float(max(-0.8,min(0.8,right*gain)))) : (Float(left*gain),Float(right*gain))
    }
}

private final class SynthStorage: Sendable { let state = Mutex(SynthState()) }

@MainActor final class AudioService {
    private let engine = AVAudioEngine()
    private let storage = SynthStorage()
    private var source: AVAudioSourceNode?
    private var channels: [Int: AVAudioPlayer] = [:]
    private var fades: [Int: (Float,Float,Double,Double)] = [:]
    private var themePlayer: AVAudioPlayer?
    private var themeVolume: Float = 1
    private var lastBed: JSONValue = .null
    var muted = false { didSet { updateState() } }
    var paused = false { didSet { updateState() } }
    private var requestedVolumes: [Int: Float] = [:]
    func start() throws {
        guard source == nil else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100,channels: 2) else { throw TranceError("Unable to create stereo format") }
        let source = Self.makeSource(format: format, storage: storage)
        engine.attach(source); engine.connect(source,to: engine.mainMixerNode,format: format)
        try engine.start(); self.source = source
    }
    nonisolated private static func makeSource(format: AVAudioFormat, storage: SynthStorage) -> AVAudioSourceNode {
        return AVAudioSourceNode(format: format) { _,_,count,list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self), let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            storage.state.withLock { value in
                for i in 0..<Int(count) { let sample = value.sample(rate: 44100); l[i] = sample.0; r[i] = sample.1 }
            }
            return noErr
        }
    }
    func configure(_ bed: JSONValue) {
        guard bed != lastBed else { return }; lastBed = bed
        let tones = bed["layer"].array.map { Tone(center: max(20,min(1000,$0["center_hz"].number)),binaural: max(0,min(40,$0["binaural_hz"].number)),pulse: max(0,min(40,$0["pulse_hz"].number)),amplitude: pow(10,max(-60,min(0,$0["amplitude_db"].number))/20)) }
        var calibration = SynthState(tones: tones,targets: tones,gain: 1,targetGain: 1)
        var squares = 0.0, peak = 0.0
        for _ in 0..<88200 { let sample = calibration.sample(rate: 44100, clamp: false); let l = Double(sample.0), r = Double(sample.1); squares += l*l+r*r; peak = max(peak,abs(l),abs(r)) }
        let rms = sqrt(squares/176400)
        let db = bed["master_db"].number == 0 ? -28 : max(-60,min(-6,bed["master_db"].number))
        let gain = tones.isEmpty || rms == 0 ? 0 : min(pow(10,db/20)/rms,peak > 0 ? 0.8/peak : 1)
        storage.state.withLock { state in
            while state.tones.count < tones.count { var t = tones[state.tones.count]; t.amplitude = 0; state.tones.append(t) }
            state.targets = tones; state.targetGain = gain; state.remaining = 13230
        }
    }
    func convertedEvents(_ events: [JSONValue], session: Session) async throws {
        let converted = events
        for i in converted.indices where converted[i]["type"].string == "play" {
            let original = try session.resolve(converted[i]["path"].string)
            if original.pathExtension.lowercased() == "ogg" {
                let compatible = try await CodecService.shared.compatibleURL(original)
                playConverted[i] = compatible
            }
        }
        defer { playConverted = [:] }
        try self.events(converted,session:session)
    }
    private var playConverted: [Int:URL] = [:]
    func events(_ events: [JSONValue], session: Session) throws {
        for (eventIndex,event) in events.enumerated() {
            var channel = Int(event["channel"].number)
            switch event["type"].string {
            case "play":
                if event["next_unused_channel"].bool { while channels[channel]?.isPlaying == true { channel += 1 } }
                let player = try AVAudioPlayer(contentsOf: playConverted[eventIndex] ?? session.resolve(event["path"].string))
                player.numberOfLoops = event["loop"].bool ? -1 : 0
                requestedVolumes[channel] = Float(min(100,max(0,event["volume"].number))/100)
                player.volume = muted ? 0 : requestedVolumes[channel] ?? 1
                channels[channel] = player; fades[channel] = nil
                if !paused { player.play() }
            case "stop": channels[channel]?.stop(); channels[channel] = nil; fades[channel] = nil
            case "fade": fades[channel] = (requestedVolumes[channel] ?? 1,Float(event["volume"].number/100),0,max(0,event["time_seconds"].number))
            default: throw TranceError("Unknown audio event: \(event["type"].string)")
            }
        }
    }
    func tick(_ seconds: Double) {
        guard !paused else { return }
        for (channel,fade) in fades {
            let elapsed = fade.2+seconds, p = fade.3 == 0 ? 1 : min(1,elapsed/fade.3)
            let volume = fade.0+(fade.1-fade.0)*Float(p); requestedVolumes[channel] = volume
            channels[channel]?.volume = muted ? 0 : volume
            fades[channel] = p >= 1 ? nil : (fade.0,fade.1,elapsed,fade.3)
        }
    }
    func theme(path: URL?, loop: Bool = false) throws {
        themePlayer?.stop(); themePlayer = nil
        guard let path else { return }
        let player = try AVAudioPlayer(contentsOf: path); player.numberOfLoops = loop ? -1 : 0
        player.volume = muted ? 0 : themeVolume; themePlayer = player
        if !paused { player.play() }
    }
    func themeGain(_ volume: Double) { themeVolume = Float(max(0,min(1,volume))); themePlayer?.volume = muted ? 0 : themeVolume }
    private func updateState() {
        storage.state.withLock { $0.paused = paused; $0.muted = muted }
        for (channel,player) in channels { player.volume = muted ? 0 : requestedVolumes[channel] ?? 1; if paused { player.pause() } else { player.play() } }
        themePlayer?.volume = muted ? 0 : themeVolume
        if paused { themePlayer?.pause() } else { themePlayer?.play() }
    }
    func stop() { engine.stop(); channels.values.forEach { $0.stop() }; channels = [:]; themePlayer?.stop() }
}
