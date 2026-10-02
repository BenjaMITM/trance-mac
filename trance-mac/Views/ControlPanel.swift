import SwiftUI
import AppKit

struct ControlPanel: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Trance").font(.largeTitle)
                if store.isLoading { ProgressView("Loading session…") }
                if let session = store.session {
                    Text(session.url.lastPathComponent).font(.headline)
                    Text("\(store.primaryTheme) / \(store.secondaryTheme)").foregroundStyle(.secondary)
                    Picker("Program",selection:Binding(get:{store.programName},set:store.selectProgram)) {
                        ForEach(store.programNames,id:\.self) { Text($0).tag($0) }
                    }
                    if store.hasProgramOverride {
                        Text("Runtime program override until the next playlist item").font(.caption).foregroundStyle(.secondary)
                        Button("Follow Playlist",action:store.releaseProgram)
                    }
                    DisclosureGroup("Visuals",isExpanded:.constant(true)) { VisualControls(store:store) }
                    DisclosureGroup("Custom Patterns") { PatternEditor(store:store) }
                    DisclosureGroup("Program") { ProgramControls(store:store) }
                    DisclosureGroup("Themes") { ThemeEditor(store:store) }
                    DisclosureGroup("Playlist") { PlaylistEditor(store:store) }
                    DisclosureGroup("Audio") { AudioControls(store:store) }
                    DisclosureGroup("Overlay") {
                        Toggle("Click-through overlay",isOn:$store.overlay)
                        Slider(value:$store.opacity,in:0.05...1) { Text("Opacity") }
                        Button("Hide and Silence") { store.setHidden(true) }
                    }
                    DisclosureGroup("Variables") { VariableEditor(store:store) }
                    Button("Export Session JSON…",action:store.exportJSON)
                    Button("Export Portable Archive…",action:store.exportArchive)
                    Button("Choose Media Folder…",action:store.scanFolder)
                    DisclosureGroup("Complete Session Editor") {
                        Text("All session fields are editable here. Apply validates and saves the session.").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text:$store.editorText).font(.system(.caption,design:.monospaced)).frame(height:320)
                        Button("Validate, Apply & Save",action:store.applyEditor)
                    }
                } else { Button("Open Session…",action:store.open); Button("Choose Media Folder…",action:store.scanFolder) }
            }.padding()
        }
    }
}
struct VisualControls: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        VStack(alignment:.leading) {
            Text("Playing: \(store.visualName)").font(.caption)
            ForEach(BuiltinPatterns.sources.keys.sorted(),id:\.self) { name in
                HStack {
                    Button(name) { store.forceVisual(name) }.buttonStyle(.borderless)
                    Spacer()
                    Toggle("Pin",isOn:Binding(get:{store.program["visual_type"].array.first { $0["type"].string == name }?["pinned"].bool ?? false},set:{value in
                        var rows = store.program["visual_type"].array
                        if let i = rows.firstIndex(where:{$0["type"].string == name}) { rows[i]["pinned"] = .bool(value) }
                        else { rows.append(.object(["type":.string(name),"random_weight":.number(0),"pinned":.bool(value)])) }
                        store.updateProgram("visual_type",.array(rows))
                    })).toggleStyle(.checkbox)
                    let rows = store.program["visual_type"].array
                    let weight = rows.first { $0["type"].string == name }?["random_weight"].number ?? 0
                    Stepper(value:Binding(get:{Int(weight)},set:{ value in
                        var rows = store.program["visual_type"].array
                        if let i = rows.firstIndex(where:{$0["type"].string == name}) { rows[i]["random_weight"] = .number(Double(value)) }
                        else { rows.append(.object(["type":.string(name),"random_weight":.number(Double(value))])) }
                        store.updateProgram("visual_type",.array(rows))
                    }),in:0...1000) { Text("\(Int(weight))").monospacedDigit() }.frame(width:110)
                }
            }
            ForEach(store.customVisuals,id: selfID) { pattern in
                Button(pattern["name"].string) { store.forceVisual(pattern["name"].string) }
            }
            Button("Release Visual Force",action:store.releaseVisual).disabled(store.forcedVisual == nil)
        }
    }
    private var selfID: KeyPath<JSONValue,String> { \.patternName }
}
extension JSONValue { var patternName: String { self["name"].string } }
struct ProgramControls: View {
    let store: PlaybackStore
    var body: some View {
        VStack(alignment:.leading) {
            Stepper(value:Binding(get:{Int(store.program["global_fps"].number)},set:{store.updateProgram("global_fps",.number(Double($0)))}),in:1...240) { Text("Content speed: \(Int(store.program["global_fps"].number)) fps") }
            Slider(value:Binding(get:{store.program["zoom_intensity"].number},set:{store.updateProgram("zoom_intensity",.number($0))}),in:0...1) { Text("Zoom intensity") }
            Toggle("Reverse Spiral",isOn:Binding(get:{store.program["reverse_spiral_direction"].bool},set:{store.updateProgram("reverse_spiral_direction",.bool($0))}))
            ForEach(["spiral_colour_a","spiral_colour_b","main_text_colour","shadow_text_colour"],id:\.self) { key in
                ColorPicker(key.replacingOccurrences(of:"_",with:" "),selection:Binding(get:{Color(nsColor:NSColor(hex:store.program[key].string,fallback:.clear))},set:{color in store.updateProgram(key,.string(NSColor(color).hexRGBA))}),supportsOpacity:true)
            }
        }
    }
}
struct ThemeControls: View {
    let store: PlaybackStore
    var body: some View {
        VStack(alignment:.leading) {
            ForEach(store.themeNames,id:\.self) { name in
                let pool = store.session?.pools[name]
                VStack(alignment:.leading) {
                    HStack {
                        Text(name); Spacer()
                        Button(store.themePins.contains(name) ? "Unpin" : "Pin") {
                            if store.themePins.contains(name) { store.themePins.removeAll { $0 == name } } else { store.themePins.append(name) }
                            store.chooseThemes()
                        }
                    }
                    Text("\(pool?.images.count ?? 0) images · \(pool?.animations.count ?? 0) animations · \(pool?.text.count ?? 0) phrases").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !store.themePins.isEmpty { Text("Runtime pins are not saved").font(.caption); Button("Release Pins") { store.themePins = []; store.chooseThemes() } }
        }
    }
}
