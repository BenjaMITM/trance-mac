import SwiftUI

struct ProgramEditor: View {
    let store: PlaybackStore
    @State private var name = ""
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Program name", text: $name).accessibilityIdentifier("program-name")
            VStack(alignment: .leading, spacing: 6) {
                Button("New Default") { save(rename: false, copy: false) }
                Button("Duplicate Current") { save(rename: false, copy: true) }
                Button("Rename Current") { save(rename: true, copy: false) }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Renaming preserves playlist references and playback timing. New programs become a runtime selection until the playlist advances.").font(.caption).foregroundStyle(.secondary)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
            Divider()
        }
    }
    private func save(rename: Bool, copy: Bool) {
        do {
            try store.saveProgram(name: name, rename: rename, copy: copy)
            status = "Saved program \(name)"; name = ""
        } catch { status = error.localizedDescription }
    }
}
