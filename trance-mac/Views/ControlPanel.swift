import SwiftUI
import AppKit

private enum ControlPage: String, CaseIterable {
    case playback = "Playback"
    case appearance = "Picture & text"
    case audio = "Sound"
    case media = "Media libraries"
    case playlist = "Playlist"
    case programs = "Saved programs"
    case patterns = "Custom patterns"
    case variables = "Playlist conditions"
    case files = "Session files"
    var explanation: String {
        switch self {
        case .playback: "Choose what plays now and which visuals can play automatically."
        case .appearance: "Changes apply to the current program and save automatically."
        case .audio: "Control synthesized tones. Recorded audio is configured in the playlist and media libraries."
        case .media: "A library groups images, animations, phrases, fonts and audio. Save library edits to apply them."
        case .playlist: "Arrange programs, transitions and recorded audio. Save an item to restart the playlist."
        case .programs: "A program stores visual choices, picture settings, media choices and synthesized tones."
        case .patterns: "Create or edit custom visual recipes. Save changes separately from previewing them."
        case .variables: "Conditions let playlist transitions depend on a selected value."
        case .files: "Save, export or open sessions and media folders."
        }
    }
}

struct ControlPanel: View {
    @Bindable var store: PlaybackStore
    @State private var page = ControlPage.playback
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isLoading { ProgressView("Opening session…") }
            if let session = store.session {
                Text(session.url.lastPathComponent).font(.headline).lineLimit(1).help(session.url.path)
                HStack {
                    Button { store.paused.toggle() } label: {
                        Label(store.paused ? "Resume playback" : "Pause playback", systemImage: store.paused ? "play.fill" : "pause.fill")
                    }.accessibilityIdentifier("toggle-playback").buttonStyle(.borderedProminent)
                    Button { store.muted.toggle() } label: {
                        Label(store.muted ? "Turn sound on" : "Mute sound", systemImage: store.muted ? "speaker.slash" : "speaker.wave.2")
                    }.accessibilityIdentifier("toggle-sound").buttonStyle(.bordered)
                }.labelStyle(.titleAndIcon)
                GroupBox("Now playing") {
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent("Playback", value: store.paused ? "Paused" : "Playing").accessibilityIdentifier("playback-state")
                        LabeledContent("Sound", value: store.muted ? "Muted" : "On")
                        LabeledContent("Program", value: store.programName)
                        LabeledContent("Visual", value: VisualLabels.title(store.visualName)).accessibilityIdentifier("current-visual")
                        LabeledContent("Selection", value: store.forcedVisual == nil ? "Automatic" : "Manual visual")
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("Control page", selection: $page) {
                    ForEach(ControlPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("control-page")
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(page.rawValue).font(.title2.bold()).id("page-top")
                            Text(page.explanation).font(.callout).foregroundStyle(.secondary)
                            ZStack(alignment: .topLeading) {
                                ForEach(ControlPage.allCases, id: \.self) { candidate in
                                    contents(for: candidate)
                                        .frame(height: candidate == page ? nil : 0, alignment: .top)
                                        .opacity(candidate == page ? 1 : 0).clipped()
                                        .allowsHitTesting(candidate == page).accessibilityHidden(candidate != page)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                    }.onChange(of: page) { proxy.scrollTo("page-top", anchor: .top) }
                }
                Divider()
                if !store.controlFeedback.isEmpty {
                    Text(store.controlFeedback).font(.callout).textSelection(.enabled).accessibilityIdentifier("control-feedback")
                }
                if let saved = store.lastSavedAt {
                    Text("Session saved at \(saved.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                } else { Text("Program settings save automatically. Editors have a Save button.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Open a session to start").font(.title2.bold())
                Text("A session contains your media libraries, programs and playlist.").foregroundStyle(.secondary)
                Button("Open a session file…", action: store.open)
                Button("Create a session from a media folder…", action: store.scanFolder)
            }
        }.padding(16).disclosureGroupStyle(SectionDisclosureStyle())
    }
    @ViewBuilder private func contents(for selected: ControlPage) -> some View {
        switch selected {
        case .playback:
            Picker("Play program", selection: Binding(get: { store.programName }, set: store.selectProgram)) {
                ForEach(store.programNames, id: \.self) { Text($0).tag($0) }
            }
            if store.hasProgramOverride {
                Text("This program is selected until the playlist moves to its next item.").font(.caption).foregroundStyle(.secondary)
                Button("Return to playlist program", action: store.releaseProgram)
            }
            VisualControls(store: store)
        case .appearance:
            ProgramControls(store: store)
            GroupBox("Window overlay") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Float over other apps and let clicks pass through", isOn: $store.overlay)
                    Text("The Trance menu bar icon can restore the controls. Shift–F11 hides or shows playback.").font(.caption).foregroundStyle(.secondary)
                    if store.overlay {
                        LabeledContent("Window opacity", value: "\(Int(store.opacity * 100))%")
                        Slider(value: $store.opacity, in: 0.05...1).accessibilityLabel("Window opacity")
                    }
                    Button("Hide playback window and silence audio") { store.setHidden(true) }
                }
            }
        case .audio: AudioControls(store: store)
        case .media: ThemeEditor(store: store)
        case .playlist: PlaylistEditor(store: store)
        case .programs: ProgramEditor(store: store)
        case .patterns: PatternEditor(store: store)
        case .variables: VariableEditor(store: store)
        case .files:
            Button("Open another session…", action: store.open)
            Button("Create session from a media folder…", action: store.scanFolder)
            Button("Save current session", action: store.autosave)
            Button("Export session settings (.json)…", action: store.exportJSON)
            Button("Export session with media (.trance)…", action: store.exportArchive)
            Text("A portable archive includes media files. A JSON export contains settings and file references.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Advanced: edit complete session JSON") {
                Text("Apply validates, saves and restarts the session. Keep this for settings outside the visual editors.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $store.editorText).font(.system(.caption, design: .monospaced)).frame(height: 320)
                Button("Validate, save and restart session", action: store.applyEditor)
            }
        }
    }
}

enum VisualLabels {
    static func title(_ name: String) -> String {
        ["parallel": "Images & captions", "super_parallel": "Layered images", "accelerate": "Accelerating image changes", "slow_flash": "Slow-to-fast sequence", "sub_text": "Images & subtext", "flash_text": "Crossfading images & text", "animation": "Animations & captions", "super_fast": "Rapid bursts"][name] ?? name
    }
    static func description(_ name: String) -> String {
        ["parallel": "Zooming images, occasional animations and full captions.", "super_parallel": "Overlapping images from both media libraries with individual words.", "accelerate": "Image changes speed up while the spiral accelerates.", "slow_flash": "A slow image sequence followed by faster changes and words.", "sub_text": "Zooming images with smaller text from the secondary library.", "flash_text": "Crossfading images with words and captions.", "animation": "Animated media with still-image overlays and captions.", "super_fast": "Fast image changes with occasional animation bursts."][name] ?? "Custom visual recipe."
    }
}

struct VisualControls: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.forcedVisual != nil {
                Text("Manual visual selection stays active until you return to automatic visuals.").font(.callout)
                Button("Return to automatic visuals", action: store.releaseVisual).accessibilityIdentifier("automatic-visuals")
            }
            Text("Automatic selection").font(.headline)
            Text("Frequency sets relative likelihood. Zero excludes an unmarked visual. Marking any visuals restricts automatic playback to that marked set; marked visuals still play at zero. ‘Play now’ overrides automatic selection.").font(.caption).foregroundStyle(.secondary)
            ForEach(BuiltinPatterns.sources.keys.sorted(), id: \.self) { name in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(VisualLabels.title(name)).font(.headline)
                        Text(VisualLabels.description(name)).font(.caption).foregroundStyle(.secondary)
                        Button("Play this visual now") { store.forceVisual(name) }
                            .accessibilityIdentifier("play-visual-" + name)
                        Toggle("Include in exclusive selection", isOn: Binding(get: {
                            row(name)["pinned"].bool
                        }, set: { set(name, key: "pinned", value: .bool($0)) }))
                            .accessibilityIdentifier("pin-visual-" + name)
                        Stepper("Selection frequency: \(Int(row(name)["random_weight"].number))", value: Binding(get: {
                            Int(row(name)["random_weight"].number)
                        }, set: { set(name, key: "random_weight", value: .number(Double($0))) }), in: 0...1000)
                            .accessibilityIdentifier("weight-visual-" + name)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(store.customVisuals, id: \.patternName) { pattern in
                Button("Play custom visual: \(pattern["name"].string)") { store.forceVisual(pattern["name"].string) }
            }
        }
    }
    private func row(_ name: String) -> JSONValue { store.program["visual_type"].array.first { $0["type"].string == name } ?? .null }
    private func set(_ name: String, key: String, value: JSONValue) {
        var rows = store.program["visual_type"].array
        if let i = rows.firstIndex(where: { $0["type"].string == name }) { rows[i][key] = value }
        else { rows.append(.object(["type": .string(name), key: value])) }
        store.updateProgram("visual_type", .array(rows))
    }
}
extension JSONValue { var patternName: String { self["name"].string } }

struct ProgramControls: View {
    let store: PlaybackStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Motion") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Visual timeline speed: \(Int(store.program["global_fps"].number)) frames/second", value: Binding(get: { Int(store.program["global_fps"].number) }, set: { store.updateProgram("global_fps", .number(Double($0))) }), in: 1...240).accessibilityIdentifier("timeline-speed")
                    Text("Higher values make image changes, text timing and spiral motion faster. This is the visual timeline, not the monitor refresh rate.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Zoom strength", value: "\(Int(store.program["zoom_intensity"].number * 100))%")
                    Slider(value: Binding(get: { store.program["zoom_intensity"].number }, set: { store.updateProgram("zoom_intensity", .number($0)) }), in: 0...1).accessibilityLabel("Zoom strength")
                    Toggle("Reverse spiral rotation", isOn: Binding(get: { store.program["reverse_spiral_direction"].bool }, set: { store.updateProgram("reverse_spiral_direction", .bool($0)) })).accessibilityIdentifier("reverse-spiral")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Colors") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(["spiral_colour_a", "spiral_colour_b", "main_text_colour", "shadow_text_colour"], id: \.self) { key in
                        ColorPicker(colorTitle(key), selection: Binding(get: { Color(nsColor: NSColor(hex: store.program[key].string, fallback: .clear)) }, set: { store.updateProgram(key, .string(NSColor($0).hexRGBA)) }), supportsOpacity: true)
                    }
                    Text("Each color includes opacity. A transparent color hides that part of the visual.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func colorTitle(_ key: String) -> String {
        ["spiral_colour_a": "Spiral foreground", "spiral_colour_b": "Spiral background", "main_text_colour": "Caption & word color", "shadow_text_colour": "Text shadow color"][key] ?? key
    }
}

struct ThemeControls: View {
    let store: PlaybackStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media in use").font(.headline)
            LabeledContent("Primary library", value: store.primaryTheme)
            LabeledContent("Secondary library", value: store.secondaryTheme)
            Text("Choose libraries for this playback run. These temporary selections do not change the program’s saved library settings.").font(.caption).foregroundStyle(.secondary)
            ForEach(store.themeNames, id: \.self) { name in
                let pool = store.session?.pools[name]
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(name, isOn: Binding(get: { store.themePins.contains(name) }, set: { value in
                        if value { store.themePins.append(name) } else { store.themePins.removeAll { $0 == name } }
                        store.chooseThemes(); store.controlFeedback = "Media selection applied for this playback run."
                    }))
                    Text("\(pool?.images.count ?? 0) images • \(pool?.animations.count ?? 0) animations • \(pool?.text.count ?? 0) phrases • \(pool?.audio.count ?? 0) audio files").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !store.themePins.isEmpty { Button("Return to program’s library selection") { store.themePins = []; store.chooseThemes(); store.controlFeedback = "Using the program’s saved media selection." } }
        }
    }
}

struct SectionDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right").font(.caption).frame(width: 14)
                    configuration.label
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}
