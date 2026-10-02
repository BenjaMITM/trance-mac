import XCTest
import AVFoundation

final class AudioAcceptanceTests: XCTestCase {
    @MainActor func testProductionSynthStereoLevelMutePauseAndRemoval() throws {
        let audio = AudioService(); defer { audio.stop() }
        audio.configure(Session.defaultProgram["entrainment"])
        try audio.start(manualRendering: true)
        let samples = try audio.renderOffline(frames: 44100 * 3)
        let settled = samples.map { Array($0.suffix(44100)) }
        for channel in settled {
            XCTAssertTrue(channel.allSatisfy { $0.isFinite && abs($0) <= 0.801 })
            let rms = sqrt(channel.reduce(0.0) { $0 + Double($1 * $1) } / Double(channel.count))
            XCTAssertGreaterThan(rms, 0.01); XCTAssertLessThan(rms, 0.08)
        }
        XCTAssertGreaterThan(zip(settled[0], settled[1]).reduce(0.0) { $0 + abs(Double($1.0 - $1.1)) }, 100)
        audio.muted = true
        XCTAssertTrue(try audio.renderOffline(frames: 4096).joined().allSatisfy { $0 == 0 })
        audio.muted = false; audio.paused = true
        XCTAssertTrue(try audio.renderOffline(frames: 4096).joined().allSatisfy { $0 == 0 })
        audio.paused = false
        XCTAssertTrue(try audio.renderOffline(frames: 4096).joined().contains { abs($0) > 0.001 })
        audio.configure(.object(["layer": .array([])]))
        _ = try audio.renderOffline(frames: 44100)
        XCTAssertTrue(try audio.renderOffline(frames: 4096).joined().allSatisfy { abs($0) < 0.00001 })
    }
    @MainActor func testRecordedAudioPlayLoopPauseMuteFadeAndStop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)); buffer.frameLength = 44100
        for c in 0..<2 { for i in 0..<44100 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.02) } }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        let session = try Session.new(at: root.appendingPathComponent("session.json"))
        let audio = AudioService(); defer { audio.stop() }
        try audio.events([.object(["type": .string("play"), "channel": .number(0), "path": .string("tone.wav"), "volume": .number(20), "loop": .bool(true)])], session: session)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(try XCTUnwrap(audio.channelState(0)).playing)
        XCTAssertGreaterThan(try XCTUnwrap(audio.channelState(0)).time, 0)
        XCTAssertEqual(try XCTUnwrap(audio.channelState(0)).loops, -1)
        audio.paused = true; let pausedTime = try XCTUnwrap(audio.channelState(0)).time
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(try XCTUnwrap(audio.channelState(0)).playing)
        XCTAssertEqual(try XCTUnwrap(audio.channelState(0)).time, pausedTime, accuracy: 0.03)
        audio.muted = true; XCTAssertEqual(try XCTUnwrap(audio.channelState(0)).volume, 0)
        audio.paused = false; audio.muted = false
        try audio.events([.object(["type": .string("fade"), "channel": .number(0), "volume": .number(5), "time_seconds": .number(1)])], session: session)
        audio.tick(1); XCTAssertEqual(try XCTUnwrap(audio.channelState(0)).volume, 0.05, accuracy: 0.001)
        try audio.events([.object(["type": .string("stop"), "channel": .number(0)])], session: session)
        XCTAssertNil(audio.channelState(0))
    }
    @MainActor func testOggAndWebMDecodeThroughApprovedCodecHelper() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helper = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: FileManager.default.isExecutableFile(atPath:))
        let executable = try XCTUnwrap(helper)
        let ogg = root.appendingPathComponent("test.ogg"), webm = root.appendingPathComponent("test.webm")
        for (url, arguments) in [(ogg, ["-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", "-c:a", "libopus"]),
                                  (webm, ["-f", "lavfi", "-i", "testsrc=size=160x120:rate=10:duration=0.3", "-c:v", "libvpx-vp9"])] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["-nostdin", "-v", "error"] + arguments + [url.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        }
        let wav = try await CodecService.shared.compatibleURL(ogg)
        let file = try AVAudioFile(forReading: wav)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        XCTAssertGreaterThan(buffer.frameLength, 8000)
        XCTAssertTrue(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)).contains { abs($0) > 0.01 })
        let movie = try await CodecService.shared.compatibleURL(webm)
        let asset = AVURLAsset(url: movie)
        let playable = try await asset.load(.isPlayable), duration = try await asset.load(.duration)
        XCTAssertTrue(playable); XCTAssertGreaterThan(duration.seconds, 0.2)
    }

}
