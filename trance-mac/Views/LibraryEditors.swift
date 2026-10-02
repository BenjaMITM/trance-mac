import SwiftUI

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
    @State private var phrases = "[]"
    @State private var weight = 1
    @State private var pinned = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeControls(store: store)
            Divider()
            Picker("Edit theme", selection: $selection) {
                Text("New theme").tag("")
                ForEach(store.themeNames, id: \.self) { Text($0).tag($0) }
            }.onChange(of: selection) { load() }
            TextField("Theme name", text: $name)
            Toggle("Scan directory", isOn: $scanEnabled)
            if scanEnabled {
                TextField("Directory relative to session", text: $directory)
                Toggle("Inherit media from parent themes", isOn: $inherit)
                lines("Excluded paths", text: $excluded)
            }
            lines("Image paths", text: $images)
            lines("Animation paths", text: $animations)
            lines("Font paths", text: $fonts)
            lines("Audio paths", text: $audio)
            lines("Phrases (JSON array of strings)", text: $phrases)
            Text("One entry per line. Paths are relative to the session folder.").font(.caption).foregroundStyle(.secondary)
            Stepper("Weight in \(store.programName): \(weight)", value: $weight, in: 0...1000)
            Toggle("Saved theme pin in this program", isOn: $pinned)
            Button("Save Theme", action: save).disabled(name.isEmpty)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        }.onChange(of: store.programName) { load() }
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
        phrases = (try? JSONValue.array(theme["text_line"].array).text()) ?? "[]"
        let row = store.program["enabled_theme"].array.first { $0["theme_name"].string == selection }
        weight = Int(row?["random_weight"].number ?? 1); pinned = row?["pinned"].bool ?? false; status = ""
    }
    private func save() {
        guard let session = store.session else { return }
        var definition: JSONValue = .object(["image_path": .array(entries(images)), "animation_path": .array(entries(animations)), "font_path": .array(entries(fonts)), "audio_path": .array(entries(audio))])
        if scanEnabled { definition["scan"] = .object(["dir": .string(directory), "inherit": .bool(inherit), "exclude": .array(entries(excluded))]) }
        do {
            definition["text_line"] = try JSONDecoder().decode(JSONValue.self, from: Data(phrases.utf8))
            let updated = try LibraryAuthoring.theme(session: session, original: selection.isEmpty ? nil : selection, name: name, definition: definition, program: store.programName, weight: weight, pinned: pinned)
            try updated.save(); store.session = updated; store.editorText = try updated.json.text(); store.chooseThemes()
            selection = name; status = "Saved"
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
            Picker("Edit variable", selection: $selection) {
                Text("New variable").tag("")
                ForEach(store.session?.json["variable_map"].object.keys.sorted() ?? [], id: \.self) { Text($0).tag($0) }
            }.onChange(of: selection) { load() }
            TextField("Name", text: $name)
            TextField("Description", text: $description)
            Text("Allowed values, one per line").font(.caption)
            TextEditor(text: $values).frame(height: 90)
            Picker("Default value", selection: $defaultValue) { ForEach(allowed, id: \.self) { Text($0).tag($0) } }
            Button("Save Variable", action: save).disabled(name.isEmpty || allowed.isEmpty)
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        }
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
