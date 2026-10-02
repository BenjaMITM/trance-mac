import AVFoundation
import AppKit

@MainActor final class VideoFrameService {
    private let imageContext = CIContext()
    private var generation = 0
    private var players: [String:AVPlayer] = [:]
    private var outputs: [String:AVPlayerItemVideoOutput] = [:]
    private var pending = Set<String>()
    private var errors: [String:String] = [:]
    func frame(url: URL,paused: Bool) -> NSImage? {
        let key = url.path
        if players[key] == nil, !pending.contains(key), errors[key] == nil {
            pending.insert(key)
            let requestedGeneration = generation
            Task {
                do {
                    let compatible = try await CodecService.shared.compatibleURL(url)
                    guard requestedGeneration == generation else { return }
                    let item = AVPlayerItem(url:compatible)
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
                    item.add(output)
                    let player = AVPlayer(playerItem:item); player.isMuted = true
                    outputs[key] = output; players[key] = player
                    // Playback starts only when a current render requests this player.
                } catch { if requestedGeneration == generation { errors[key] = error.localizedDescription } }
                if requestedGeneration == generation { pending.remove(key) }
            }
        }
        guard let player = players[key],let output = outputs[key] else { return nil }
        if paused { player.pause() } else if player.rate == 0 { player.play() }
        if let item = player.currentItem,item.duration.isNumeric,player.currentTime() >= item.duration { player.seek(to:.zero); if !paused { player.play() } }
        let time = output.itemTime(forHostTime:CACurrentMediaTime())
        guard let pixel = output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else { return nil }
        let image = CIImage(cvPixelBuffer:pixel)
        guard let cg = imageContext.createCGImage(image,from:image.extent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
    func error(url: URL) -> String? { errors[url.path] }
    func reset() {
        generation += 1; pauseAll()
        players.removeAll(); outputs.removeAll(); pending.removeAll(); errors.removeAll()
    }
    func pauseAll() { players.values.forEach { $0.pause() } }
}
