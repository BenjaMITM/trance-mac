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
        let playback = app.buttons["toggle-playback"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5))
        playback.click(); XCTAssertTrue(app.staticTexts["Paused"].exists)
        playback.click(); XCTAssertTrue(app.staticTexts["Playing"].exists)
        app.buttons["toggle-sound"].click(); XCTAssertTrue(app.staticTexts["On"].exists)
        app.buttons["toggle-sound"].click(); XCTAssertTrue(app.staticTexts["Muted"].exists)
        func clickInPage(_ element: XCUIElement) {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<60 {
                if scroll.frame.contains(element.frame) { break }
                scroll.scroll(byDeltaX: 0, deltaY: max(-60, min(60, scroll.frame.midY - element.frame.midY)))
            }
            XCTAssertTrue(scroll.frame.contains(element.frame), "Control must be visible before clicking")
            element.click()
        }
        clickInPage(app.checkBoxes["pin-visual-accelerate"])
        var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        var programs = saved["program_map"] as! [String: Any]
        var program = programs["default"] as! [String: Any]
        let visuals = program["visual_type"] as! [[String: Any]]
        XCTAssertEqual(visuals.first { $0["type"] as? String == "accelerate" }?["pinned"] as? Bool, true)
        clickInPage(app.buttons["play-visual-animation"])
        let actionCapture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); actionCapture.name = "Visual action state"; actionCapture.lifetime = .keepAlways; add(actionCapture)
        XCTAssertTrue(app.staticTexts["Manual visual"].exists)
        XCTAssertTrue(app.staticTexts["Playing Animations & captions. Automatic selection is suspended."].exists)
        clickInPage(app.buttons["automatic-visuals"])
        XCTAssertTrue(app.staticTexts["Automatic"].exists)
        func page(_ title: String) {
            app.popUpButtons["control-page"].click()
            app.menuItems[title].click()
        }
        page("Picture & text")
        app.checkBoxes["reverse-spiral"].click()
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        programs = saved["program_map"] as! [String: Any]; program = programs["default"] as! [String: Any]
        XCTAssertEqual(program["reverse_spiral_direction"] as? Bool, true)
        page("Sound")
        app.buttons["enable-tones"].click()
        XCTAssertTrue(app.staticTexts["Synthesized tones are on"].exists)
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        programs = saved["program_map"] as! [String: Any]; program = programs["default"] as! [String: Any]
        XCTAssertEqual(((program["entrainment"] as? [String: Any])?["layer"] as? [Any])?.count, 2)
        clickInPage(app.buttons["add-tone"])
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        programs = saved["program_map"] as! [String: Any]; program = programs["default"] as! [String: Any]
        XCTAssertEqual(((program["entrainment"] as? [String: Any])?["layer"] as? [Any])?.count, 3)
        clickInPage(app.buttons["disable-tones"])
        XCTAssertTrue(app.staticTexts["Synthesized tones are off"].exists)
        page("Saved programs")
        let field = app.textFields["program-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.click(); field.typeText("Acceptance Program")
        page("Picture & text"); page("Saved programs")
        XCTAssertEqual(field.value as? String, "Acceptance Program", "Unsaved editor drafts must survive page navigation")
        app.buttons["Copy current program with this name"].click()
        saved = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
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
        let screenshot = XCTAttachment(screenshot: capture); screenshot.name = "Redesigned controls, applied settings and rendered media"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
