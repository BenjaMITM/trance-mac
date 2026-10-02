import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.055, green: 0.035, blue: 0.11, alpha: 1).setFill(); background.fill()
let palette = [NSColor(calibratedRed: 0.78, green: 0.31, blue: 0.9, alpha: 1), NSColor(calibratedRed: 0.27, green: 0.83, blue: 0.81, alpha: 1)]
for arm in 0..<5 {
    let path = NSBezierPath(); path.lineWidth = 30; path.lineCapStyle = .round
    for step in 0...650 {
        let p = Double(step) / 650
        let radius = 32 + 365 * p
        let angle = p * 2.8 * .pi + Double(arm) * 2 * .pi / 5
        let point = NSPoint(x: 512 + cos(angle) * radius, y: 512 + sin(angle) * radius)
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    palette[arm % 2].setStroke(); path.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
