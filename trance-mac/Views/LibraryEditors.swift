import SwiftUI
import AppKit

private struct PhraseDraft: Identifiable { let id = UUID(); var text: String }

struct ThemeEditor: View {
    let store: PlaybackStore
    @State private var selection = ""
    @State private var name = ""
    @State private var scanEnabled = false
    @State private var directory = "."
    @State private var inherit = false
    @State private var excluded = ""
    @State private var images = ""
    @State private var animations = ""
    @State private var fonts = ""
    @State private var audio = ""
    @State private var phrases: [PhraseDraft] = []
    @State private var weight = 1
    @State private var pinned = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeControls(store: store)
            Divider()
            Picker("Library to edit", selection: $selection) {
                Text("Create a new library").tag("")
                ForEach(store.themeNames, id: \.self) { Text($0).tag($0) }
            }.onChange(of: selection) { load() }
            Text("Edit library details").font(.headline)
            TextField("Library name", text: $name)
            Toggle("Find media by scanning a folder", isOn: $scanEnabled)
            if scanEnabled {
                TextField("Folder path inside this session", text: $directory)
                Button("Choose folder to scan…") { selectDirectory() }
                Toggle("Include media from parent folders", isOn: $inherit)
                lines("Files to exclude from scanning", text: $excluded)
            }
            assetList("Images", text: $images)
            assetList("Animations", text: $animations)
            assetList("Fonts", text: $fonts)
            assetList("Recorded audio", text: $audio)
            Text("Phrases shown in visuals").font(.headline)
            ForEach($phrases) { $phrase in
                VStack(alignment: .leading) {
                    TextEditor(text: $phrase.text).frame(height: 70).accessibilityLabel("Phrase text")
                    Button("Remove this phrase") { phrases.removeAll { $0.id == phrase.id } }
                }
            }
            Button("Add a phrase") { phrases.append(PhraseDraft(text: "")) }
            Text("Choose files within the session folder. Advanced path lists accept one relative file path per line.").font(.caption).foregroundStyle(.secondary)
            Stepper("Selection frequency in \(store.programName): \(weight)", value: $weight, in: 0...1000)
            Toggle("Only select this library (or other marked libraries)", isOn: $pinned)
            Button("Save media library", action: save).disabled(name.isEmpty)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        }.onChange(of: store.programName) { load() }
    }
    private func assetList(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(entries(text.wrappedValue).count) explicitly selected files").font(.headline)
            Button("Choose \(label.lowercased()) files…") {
                let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
                guard panel.runModal() == .OK else { return }
                do {
                    let paths = try panel.urls.map(relativePath)
                    let combined = Array(Set(entries(text.wrappedValue).map(\.string) + paths)).sorted()
                    text.wrappedValue = combined.joined(separator: "\n")
                    status = "Files selected. Save media library to apply."
                } catch { status = error.localizedDescription }
            }
            DisclosureGroup("Advanced: \(label.lowercased()) file paths") { lines("Relative paths", text: text) }
        }
    }
    private func relativePath(_ url: URL) throws -> String {
        guard let root = store.session?.root.standardizedFileURL.path else { throw TranceError("Open a session first") }
        let path = url.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { throw TranceError("Choose a file or folder inside the session folder: \(root)") }
        return path == root ? "." : String(path.dropFirst(root.count + 1))
    }
    private func selectDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { directory = try relativePath(url); status = "Folder selected. Save media library to scan and apply." }
        catch { status = error.localizedDescription }
    }
    private func lines(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption)
            TextEditor(text: text).font(.system(.caption, design: .monospaced)).frame(height: 70)
        }
    }
    private func entries(_ text: String) -> [JSONValue] {
        text.components(separatedBy: .newlines).filter { !$0.isEmpty }.map(JSONValue.string)
    }
    private func load() {
        let theme = store.session?.json["theme_map"][selection] ?? .null
        name = selection; scanEnabled = theme.object["scan"] != nil
        let scan = theme["scan"]
        directory = scan.object.isEmpty ? (scan.string.isEmpty ? "." : scan.string) : scan["dir"].string
        inherit = scan["inherit"].bool
        excluded = scan["exclude"].array.map(\.string).joined(separator: "\n")
        images = theme["image_path"].array.map(\.string).joined(separator: "\n")
        animations = theme["animation_path"].array.map(\.string).joined(separator: "\n")
        fonts = theme["font_path"].array.map(\.string).joined(separator: "\n")
        audio = theme["audio_path"].array.map(\.string).joined(separator: "\n")
        phrases = theme["text_line"].array.map { PhraseDraft(text: $0.string) }
        let row = store.program["enabled_theme"].array.first { $0["theme_name"].string == selection }
        weight = Int(row?["random_weight"].number ?? 1); pinned = row?["pinned"].bool ?? false; status = ""
    }
    private func save() {
        guard let session = store.session else { return }
        var definition: JSONValue = .object(["image_path": .array(entries(images)), "animation_path": .array(entries(animations)), "font_path": .array(entries(fonts)), "audio_path": .array(entries(audio))])
        if scanEnabled { definition["scan"] = .object(["dir": .string(directory), "inherit": .bool(inherit), "exclude": .array(entries(excluded))]) }
        do {
            definition["text_line"] = .array(phrases.map { .string($0.text) })
            let updated = try LibraryAuthoring.theme(session: session, original: selection.isEmpty ? nil : selection, name: name, definition: definition, program: store.programName, weight: weight, pinned: pinned)
            try updated.save(); store.session = updated; store.editorText = try updated.json.text(); store.chooseThemes()
            selection = name; status = "Media library saved and applied."
        } catch { status = error.localizedDescription }
    }
}

struct VariableEditor: View {
    let store: PlaybackStore
    @State private var selection = ""
    @State private var name = ""
    @State private var description = ""
    @State private var values = ""
    @State private var defaultValue = ""
    @State private var status = ""
    private var allowed: [String] { values.components(separatedBy: .newlines).filter { !$0.isEmpty } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.session?.json["variable_map"].object.keys.sorted() ?? [], id: \.self) { key in
                Picker(key, selection: Binding(get: { store.variables[key] ?? store.session?.json["variable_map"][key]["default_value"].string ?? "" }, set: { store.variables[key] = $0 })) {
                    ForEach(store.session?.json["variable_map"][key]["value"].array.map(\.string) ?? [], id: \.self) { Text($0).tag($0) }
                }
            }
            Divider()
            Picker("Condition to edit", selection: $selection) {
                Text("Create a new condition").tag("")
                ForEach(store.session?.json["variable_map"].object.keys.sorted() ?? [], id: \.self) { Text($0).tag($0) }
            }.onChange(of: selection) { load() }
            TextField("Condition name", text: $name)
            TextField("What this condition represents", text: $description)
            Text("Allowed values, one per line").font(.caption)
            TextEditor(text: $values).frame(height: 90)
            Picker("Default value", selection: $defaultValue) { ForEach(allowed, id: \.self) { Text($0).tag($0) } }
            Button("Save playlist condition", action: save).disabled(name.isEmpty || allowed.isEmpty)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        }.onChange(of: values) { if !allowed.contains(defaultValue) { defaultValue = allowed.first ?? "" } }
    }
    private func load() {
        let row = store.session?.json["variable_map"][selection] ?? .null
        name = selection; description = row["description"].string
        values = row["value"].array.map(\.string).joined(separator: "\n"); defaultValue = row["default_value"].string; status = ""
    }
    private func save() {
        guard let session = store.session else { return }
        do {
            let updated = try LibraryAuthoring.variable(session: session, original: selection.isEmpty ? nil : selection, name: name, description: description, values: allowed, defaultValue: defaultValue)
            try updated.save()
            let current = store.variables[selection]
            if selection != name { store.variables.removeValue(forKey: selection) }
            store.variables[name] = current.flatMap { allowed.contains($0) ? $0 : nil } ?? defaultValue
            store.session = updated; store.editorText = try updated.json.text(); selection = name; status = "Saved"
        } catch { status = error.localizedDescription }
    }
}
