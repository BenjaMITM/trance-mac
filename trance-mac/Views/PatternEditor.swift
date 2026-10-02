import SwiftUI

struct PatternEditor: View {
    let store: PlaybackStore
    @State private var selection = ""
    @State private var name = ""
    @State private var source = ""
    @State private var weight = 1
    @State private var enabled = true
    @State private var pinned = false
    @State private var status = ""
    @State private var template = "parallel"
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("Custom pattern",selection:$selection) {
                Text("New pattern").tag("")
                ForEach(store.customVisuals,id:\.patternName) { Text($0["name"].string).tag($0["name"].string) }
            }.onChange(of:selection) { loadSelection() }
            TextField("Pattern name",text:$name)
            if selection.isEmpty {
                HStack {
                    Picker("Recipe",selection:$template) { ForEach(BuiltinPatterns.sources.keys.sorted(),id:\.self) { Text(VisualLabels.title($0)).tag($0) } }
                    Button("Use this starting recipe") { source = BuiltinPatterns.sources[template] ?? ""; status = "" }
                }
            }
            TextEditor(text:$source).font(.system(.caption,design:.monospaced)).frame(minHeight:220)
            Stepper("Selection frequency: \(weight)",value:$weight,in:0...1000)
            Toggle("Enabled",isOn:$enabled)
            Toggle("Only select this visual (or other marked visuals)",isOn:$pinned).disabled(!enabled)
            HStack {
                Button("Check recipe",action:validate).disabled(source.isEmpty)
                Button("Save custom pattern",action:save).disabled(name.isEmpty || source.isEmpty)
                Button("Preview without saving",action:preview).disabled(source.isEmpty)
            }
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
            Text("Save writes the recipe file and session settings. Preview temporarily plays this recipe; return to automatic visuals on the Playback page to finish previewing.").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of:store.programName) { selection = ""; name = ""; source = ""; status = "" }
    }
    private func loadSelection() {
        status = ""
        guard let row = store.customVisuals.first(where:{$0["name"].string == selection}) else { name = ""; source = ""; weight = 1; enabled = true; pinned = false; return }
        name = selection; weight = Int(row["random_weight"].number); enabled = row["enabled"].bool; pinned = row["pinned"].bool
        do { source = try store.source(selection) } catch { status = error.localizedDescription }
    }
    private func validate() {
        do { let node = try PatternAuthoring.validate(source:source,program:store.program); status = "Valid · \(node.span) content frames" }
        catch { status = error.localizedDescription }
    }
    private func save() {
        guard let session = store.session else { return }
        do {
            let updated = try PatternAuthoring.save(session:session,programName:store.programName,originalName:selection.isEmpty ? nil : selection,name:name,source:source,weight:weight,enabled:enabled,pinned:pinned)
            store.session = updated; store.editorText = try updated.json.text(); selection = name; status = "Saved"
        } catch { status = error.localizedDescription }
    }
    private func preview() {
        do { try store.forceSource(name:name.isEmpty ? "preview" : name,source:source); store.forcedVisual = "runtime"; status = "Previewing" }
        catch { status = error.localizedDescription }
    }
}
