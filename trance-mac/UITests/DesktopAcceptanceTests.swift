import XCTest
import AppKit

final class DesktopAcceptanceTests: XCTestCase {
    @MainActor func testWindowControlsAndProgramAuthoring() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = root.appendingPathComponent("session.json")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 512, bitsPerPixel: 32))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<128 { for x in 0..<128 {
            let offset = y * 512 + x * 4
            pixels[offset] = 220; pixels[offset+1] = UInt8(x); pixels[offset+2] = UInt8(y); pixels[offset+3] = 255
        } }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("image.png"))
        let fixture: [String: Any] = ["format": "trance-session", "format_version": 1,
            "theme_scan_root": ["dir": ".", "auto_rescan": false],
            "program_map": ["default": ["global_fps": 60, "zoom_intensity": 0.5,
                "spiral_colour_a": "#CC55EE66", "spiral_colour_b": "#22222222", "main_text_colour": "#FFFFFFFF",
                "shadow_text_colour": "#000000FF", "visual_type": [["type": "parallel", "random_weight": 1]],
                "enabled_theme": [["theme_name": "media", "random_weight": 1]]]],
            "theme_map": ["media": ["image_path": ["image.png"], "text_line": ["ACCEPTANCE GRAPHICS"]]]]
        try JSONSerialization.data(withJSONObject: fixture).write(to: session)

        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [session.path, "--muted"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].click(); XCTAssertTrue(app.buttons["Resume"].exists)
        app.buttons["Resume"].click(); XCTAssertTrue(app.buttons["Pause"].exists)
        app.buttons["Unmute"].click(); XCTAssertTrue(app.buttons["Mute"].exists)
        app.buttons["Mute"].click()
        app.buttons["Controls"].click(); XCTAssertFalse(app.textFields["program-name"].exists)
        app.buttons["Controls"].click()
        app.activate()
        app.disclosureTriangles["Visuals"].click()
        app.disclosureTriangles["Program"].click()
        let field = app.textFields["program-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.click(); field.typeText("Acceptance Program")
        app.buttons["Duplicate Current"].click()
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        XCTAssertNotNil((saved["program_map"] as? [String: Any])?["Acceptance Program"])
        let capture = app.windows.firstMatch.screenshot()
        let rendered = try XCTUnwrap(NSBitmapImageRep(data: capture.pngRepresentation))
        var colorfulSamples = 0
        for x in stride(from: rendered.pixelsWide * 2 / 3, to: rendered.pixelsWide * 9 / 10, by: 8) {
            for y in stride(from: rendered.pixelsHigh / 4, to: rendered.pixelsHigh * 3 / 4, by: 8) {
                if let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(color.redComponent, color.greenComponent, color.blueComponent) - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.15 { colorfulSamples += 1 }
            }
        }
        XCTAssertGreaterThan(colorfulSamples, 100, "Generated media must be visible in the actual playback window")
        let screenshot = XCTAttachment(screenshot: capture); screenshot.name = "Desktop controls, saved program and rendered media"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
