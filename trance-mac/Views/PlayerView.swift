import SwiftUI
import AppKit
import AVFoundation
import ImageIO
import CoreText

struct PlayerView: NSViewRepresentable {
    let store: PlaybackStore
    func makeNSView(context: Context) -> PlayerCanvas { let view = PlayerCanvas(); view.store = store; return view }
    func updateNSView(_ view: PlayerCanvas, context: Context) { view.store = store; view.synchronizePlayback(); view.needsDisplay = true }
}
@MainActor final class PlayerCanvas: NSView {
    weak var store: PlaybackStore?
    private var sessionURL: URL?
    private var cache: [String: NSImage] = [:]
    private let videos = VideoFrameService()
    private var lastVideoImages: [String:NSImage] = [:]
    private var gifSources: [String: CGImageSource] = [:]
    private var gifDurations: [String: [Double]] = [:]
    private var failed = Set<String>()
    private var registeredFonts: [String: String] = [:]
    func synchronizePlayback() {
        if sessionURL != store?.session?.url {
            sessionURL = store?.session?.url
            videos.reset(); cache.removeAll(); lastVideoImages.removeAll()
            gifSources.removeAll(); gifDurations.removeAll(); failed.removeAll()
        }
        if store?.paused == true || store?.hidden == true { videos.pauseAll() }
    }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.identifier = NSUserInterfaceItemIdentifier("player"); store?.applyWindow() }
    override func keyDown(with event: NSEvent) {
        guard let store else { return }
        switch event.keyCode {
        case 53: NSApp.terminate(nil)
        case 122: store.showDiagnostics.toggle()
        case 120: store.showControls.toggle()
        case 46: store.muted.toggle()
        case 103 where event.modifierFlags.contains(.shift): store.setHidden(!store.hidden)
        default: super.keyDown(with: event)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let store else { return }
        NSColor.black.setFill(); bounds.fill()
        synchronizePlayback()
        // Resume only players used by this frame; previously selected clips stay paused.
        videos.pauseAll()
        let frame = store.frame
        for layer in frame.layers {
            guard let image = image(layer.path,animated: layer.animated,time: frame.time), image.size.width > 0, image.size.height > 0 else { continue }
            let scale = max(bounds.width/image.size.width,bounds.height/image.size.height) * (1+max(-0.9,layer.zoom-layer.origin))
            let size = NSSize(width: image.size.width*scale,height: image.size.height*scale)
            let rect = NSRect(x: (bounds.width-size.width)/2,y: (bounds.height-size.height)/2,width: size.width,height: size.height)
            if frame.warpAmplitude != 0 {
                let strips = 48, slice = rect.height/Double(strips)
                for i in 0..<strips {
                    let offset = sin(Double(i)/Double(strips)/max(0.001,frame.warpWavelength)*2 * .pi + frame.time*frame.warpSpeed)*frame.warpAmplitude*bounds.width
                    let dest = NSRect(x:rect.minX+offset,y:rect.minY+Double(i)*slice,width:rect.width,height:slice+1)
                    let src = NSRect(x:0,y:Double(i)*image.size.height/Double(strips),width:image.size.width,height:image.size.height/Double(strips))
                    image.draw(in: dest,from: src,operation: .sourceOver,fraction: layer.alpha)
                }
            } else { image.draw(in: rect,from: .zero,operation: .sourceOver,fraction: layer.alpha) }
        }
        if frame.spiralSpeed != 0 { drawSpiral(frame,program: store.program) }
        for text in frame.texts where !text.text.isEmpty { drawText(text,program: store.program,time: frame.time) }
    }
    private func image(_ path: String, animated: Bool, time: Double) -> NSImage? {
        guard let session = store?.session, let url = try? session.resolve(path) else { return nil }
        let path = url.standardizedFileURL.path
        guard !failed.contains(path) else { return nil }
        if animated && url.pathExtension.lowercased() == "webm" {
            if let image = videos.frame(url:url,paused:store?.paused == true || store?.hidden == true) { lastVideoImages[path] = image }
            if let error = videos.error(url:url) { failed.insert(path); store?.message = error }
            return lastVideoImages[path]
        }
        if animated && url.pathExtension.lowercased() == "gif" {
            if gifSources[path] == nil {
                guard let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { failed.insert(path); return nil }
                gifSources[path] = source
                gifDurations[path] = (0..<CGImageSourceGetCount(source)).map { index in
                    let properties = CGImageSourceCopyPropertiesAtIndex(source,index,nil) as? [String: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
                    return max(0.02,(gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1)
                }
            }
            if let source = gifSources[path], let durations = gifDurations[path], !durations.isEmpty {
                var local = time.truncatingRemainder(dividingBy: durations.reduce(0,+)); var selected = 0
                for (i,duration) in durations.enumerated() { if local < duration { selected = i; break }; local -= duration }
                if let frame = CGImageSourceCreateImageAtIndex(source,selected,nil) { return NSImage(cgImage: frame,size: NSSize(width:frame.width,height:frame.height)) }
            }
        }
        if let image = cache[path] { return image }
        guard let image = NSImage(contentsOf: url) else { failed.insert(path); store?.message = "macOS could not decode \(path)"; return nil }
        let limit = max(16,Int(store?.system["image_cache_size"].number ?? 128))
        if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
        cache[path] = image; return image
    }
    private func drawSpiral(_ frame: RenderFrame, program: JSONValue) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.translateBy(x:bounds.midX,y:bounds.midY)
        let reverse = program["reverse_spiral_direction"].bool ? -1.0 : 1.0
        context.rotate(by: frame.time*frame.spiralSpeed*reverse)
        let radius = hypot(bounds.width,bounds.height)*0.6
        let a = NSColor(hex: program["spiral_colour_a"].string, fallback: .white)
        let b = NSColor(hex: program["spiral_colour_b"].string, fallback: .black)
        for arm in 0..<12 {
            let path = CGMutablePath(); path.move(to: .zero)
            let start = Double(arm)/12*2 * .pi
            for step in 1...150 {
                let r = Double(step)/150*radius
                let angle = start + Double(step)/150 * (frame.spiralType == 0 ? 8 : 4) * .pi
                path.addLine(to: CGPoint(x:cos(angle)*r,y:sin(angle)*r))
            }
            for step in stride(from:150,through:1,by:-1) {
                let r = Double(step)/150*radius
                let angle = start + min(0.5,max(0.01,frame.spiralWidth/12))*2 * .pi + Double(step)/150*(frame.spiralType == 0 ? 8 : 4) * .pi
                path.addLine(to:CGPoint(x:cos(angle)*r,y:sin(angle)*r))
            }
            path.closeSubpath(); context.addPath(path)
            context.setFillColor((arm%2 == 0 ? a : b).withAlphaComponent(0.22).cgColor); context.fillPath()
        }
        context.restoreGState()
    }
    private func drawText(_ text: RenderText,program: JSONValue,time: Double) {
        let small = ["caption","subtext"].contains(text.kind)
        let size = max(12,bounds.height*(small ? 0.035 : 0.12)*(1+text.zoom))
        var font = NSFont.systemFont(ofSize:size,weight:.bold)
        if let path = text.fontPath, let session = store?.session, let url = try? session.resolve(path) {
            if registeredFonts[path] == nil {
                CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
                if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first,
                   let name = CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String { registeredFonts[path] = name }
            }
            if let name = registeredFonts[path], let loaded = NSFont(name:name,size:size) { font = loaded }
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let shadow = NSShadow(); shadow.shadowColor = NSColor(hex:program["shadow_text_colour"].string,fallback:.black); shadow.shadowOffset = NSSize(width:2,height:-2); shadow.shadowBlurRadius = 3
        let attributes: [NSAttributedString.Key: Any] = [.font:font,.foregroundColor:NSColor(hex:program["main_text_colour"].string,fallback:.white).withAlphaComponent(max(0,min(1,text.alpha))),.paragraphStyle:paragraph,.shadow:shadow]
        let height = size*3
        var y = small ? bounds.height*0.08 : bounds.midY-height/2 + text.origin*bounds.height
        if text.kind == "subtext" { y += (time.truncatingRemainder(dividingBy:4)/4)*bounds.height*0.18 }
        (text.text as NSString).draw(in:NSRect(x:20,y:y,width:bounds.width-40,height:height),withAttributes:attributes)
    }
}
extension NSColor {
    var hexRGBA: String {
        let color = usingColorSpace(.deviceRGB) ?? .black
        let components = [color.redComponent,color.greenComponent,color.blueComponent,color.alphaComponent]
        return "#"+components.map { String(format:"%02X",Int((max(0,min(1,$0))*255).rounded())) }.joined()
    }

    convenience init(hex: String, fallback: NSColor) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn:"#"))
        guard [6,8].contains(cleaned.count), let value = UInt64(cleaned,radix:16) else { self.init(cgColor:fallback.cgColor)!; return }
        let alpha = cleaned.count == 8 ? Double(value&255)/255 : 1
        let rgb = cleaned.count == 8 ? value >> 8 : value
        self.init(red:Double((rgb>>16)&255)/255,green:Double((rgb>>8)&255)/255,blue:Double(rgb&255)/255,alpha:alpha)
    }
}
