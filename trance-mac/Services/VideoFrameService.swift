import AVFoundation
import AppKit

@MainActor final class VideoFrameService {
    private var players: [String:AVPlayer] = [:]
    private var outputs: [String:AVPlayerItemVideoOutput] = [:]
    private var pending = Set<String>()
    private var errors: [String:String] = [:]
    func frame(url: URL,paused: Bool) -> NSImage? {
        let key = url.path
        if players[key] == nil, !pending.contains(key), errors[key] == nil {
            pending.insert(key)
            Task {
                do {
                    let compatible = try await CodecService.shared.compatibleURL(url)
                    let item = AVPlayerItem(url:compatible)
                    let output = AVPlayerItemVideoOutput(pixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
                    item.add(output)
                    let player = AVPlayer(playerItem:item); player.isMuted = true
                    outputs[key] = output; players[key] = player
                    if !paused { player.play() }
                } catch { errors[key] = error.localizedDescription }
                pending.remove(key)
            }
        }
        guard let player = players[key],let output = outputs[key] else { return nil }
        if paused { player.pause() } else if player.rate == 0 { player.play() }
        if let item = player.currentItem,item.duration.isNumeric,player.currentTime() >= item.duration { player.seek(to:.zero); if !paused { player.play() } }
        let time = output.itemTime(forHostTime:CACurrentMediaTime())
        guard let pixel = output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else { return nil }
        let image = CIImage(cvPixelBuffer:pixel)
        guard let cg = CIContext().createCGImage(image,from:image.extent) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
    func error(url: URL) -> String? { errors[url.path] }
    func pauseAll() { players.values.forEach { $0.pause() } }
}
