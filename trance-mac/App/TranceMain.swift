import SwiftUI
import Foundation

/// Headless operations run before SwiftUI or Core Audio is initialized.
@main enum TranceMain {
    @MainActor static func main() {
        do {
            let options = try LaunchOptions(arguments:Array(CommandLine.arguments.dropFirst()))
            if options.lint || options.archive != nil {
                let url = options.session ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("default.json")
                let session = url.pathExtension == "session" ? try LegacyImporter.importSession(url) : try Session.load(url)
                if options.lint { let count = try SessionLint.validate(session); print("Session valid; \(count) program patterns parsed and evaluated") }
                if let archive = options.archive { try ArchiveExporter.export(session,to:archive); print("Exported \(archive.path)") }
                return
            }
            TranceApp.main()
        } catch {
            try? FileHandle.standardError.write(contentsOf:Data((error.localizedDescription+"\n").utf8))
            exit(1)
        }
    }
}
