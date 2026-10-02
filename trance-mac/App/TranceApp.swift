import SwiftUI
import AppKit

@main struct TranceApp: App {
    @NSApplicationDelegateAdaptor(TranceDelegate.self) private var delegate
    @State private var store = PlaybackStore()
    var body: some Scene {
        WindowGroup("Trance",id:"player") { ContentView(store:store).frame(minWidth:800,minHeight:500).onAppear { delegate.store = store; delegate.configure() } }
            .commands {
                CommandGroup(replacing:.newItem) {
                    Button("Open Session…",action:store.open).keyboardShortcut("o")
                    Button("Choose Media Folder…",action:store.scanFolder)
                    Button("Save Session",action:store.autosave).keyboardShortcut("s")
                    Button("Export Session…",action:store.exportJSON)
                }
                CommandMenu("Playback") {
                    Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }.keyboardShortcut(.space,modifiers:[])
                    Button(store.muted ? "Unmute" : "Mute") { store.muted.toggle() }.keyboardShortcut("m",modifiers:[])
                    Button("Controls") { store.showControls.toggle() }.keyboardShortcut(KeyEquivalent("\u{F705}"),modifiers:[])
                    Button("Diagnostics") { store.showDiagnostics.toggle() }.keyboardShortcut(KeyEquivalent("\u{F704}"),modifiers:[])
                    Button(store.hidden ? "Show" : "Hide") { store.setHidden(!store.hidden) }.keyboardShortcut(KeyEquivalent("\u{F70E}"),modifiers:.shift)
                    Button("Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f",modifiers:[.command,.control])
                }
            }
        Settings { SystemSettings(store:store) }
        MenuBarExtra("Trance",systemImage:"circle.hexagongrid") {
            Button(store.hidden ? "Show" : "Hide") { store.setHidden(!store.hidden) }
            Button("Show Controls",action:store.revealControls)
            Toggle("Paused",isOn:$store.paused)
            Toggle("Muted",isOn:$store.muted)
            Toggle("Overlay",isOn:$store.overlay)
            Divider()
            Button("Quit Trance") { NSApp.terminate(nil) }
        }
    }
}
@MainActor final class TranceDelegate: NSObject, NSApplicationDelegate {
    weak var store: PlaybackStore?
    private var configured = false
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
    private var commands: CommandService?
    private var hotkey: HotkeyService?
    func configure() {
        guard !configured, let store else { return }; configured = true
        do {
            let options = try LaunchOptions(arguments:Array(CommandLine.arguments.dropFirst()))
            store.muted = options.muted; store.overlay = options.overlay; store.opacity = options.opacity
            store.variables = options.variables; store.forcedVisual = options.visual
            let url = options.session ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("default.json")
            if options.session != nil || FileManager.default.fileExists(atPath:url.path) {
                let session = url.pathExtension == "session" ? try LegacyImporter.importSession(url) : try Session.load(url)
                if options.lint {
                    for (_,source) in BuiltinPatterns.sources { var parser = try PatternParser(source); _ = try parser.parse() }
                    for program in session.json["program_map"].object.values {
                        let pulsed = program["entrainment"]["layer"].array.filter { $0["pulse_hz"].number > 0 }.max { $0["amplitude_db"].number <= $1["amplitude_db"].number }
                        let pulse = pulsed?["pulse_hz"].number ?? 0
                        let beat = pulse > 0 ? Int((program["global_fps"].number/pulse).rounded()) : 0
                        for pattern in program["custom_visual_pattern"].array { var parser = try PatternParser(String(contentsOf:session.resolve(pattern["file"].string),encoding:.utf8),beat:beat); _ = try parser.parse() }
                    }
                    print("Session and patterns valid")
                    exit(0)
                }
                if let archive = options.archive { try ArchiveExporter.export(session,to:archive); print("Exported \(archive.path)"); exit(0) }
                store.install(session)
            } else if options.lint || options.archive != nil { throw TranceError("Supply a session file") }
            if let system = options.system { store.system = try JSONDecoder().decode(JSONValue.self,from:Data(contentsOf:system)) }
            if let pattern = options.pattern { try store.forceSource(name:"runtime",source:String(contentsOf:pattern,encoding:.utf8)); store.forcedVisual = "runtime" }
            if options.hidden { store.setHidden(true) }
            let commands = CommandService(store:store); self.commands = commands
            try commands.start(port:options.port); if options.mcp { commands.startMCP() }
            let hotkey = HotkeyService(store:store); self.hotkey = hotkey; try hotkey.register()
        } catch {
            try? FileHandle.standardError.write(contentsOf:Data((error.localizedDescription+"\n").utf8))
            if CommandLine.arguments.contains("--lint") || CommandLine.arguments.contains(where:{$0.hasPrefix("--export_archive")}) { exit(1) }
            store.message = error.localizedDescription
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { if let path = filenames.first { store?.load(URL(fileURLWithPath:path)) }; sender.reply(toOpenOrPrint:.success) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { hotkey?.stop(); store?.audio.stop() }
}
struct SystemSettings: View {
    let store: PlaybackStore
    var body: some View {
        Form {
            Toggle("VSync",isOn:Binding(get:{store.system["enable_vsync"].bool},set:{store.system["enable_vsync"] = .bool($0); store.saveSystem()}))
            Stepper(value:Binding(get:{Int(store.system["image_cache_size"].number)},set:{store.system["image_cache_size"] = .number(Double($0)); store.saveSystem()}),in:16...4096) { Text("Image cache: \(Int(store.system["image_cache_size"].number))") }
            Slider(value:Binding(get:{store.system["draw_depth"].number},set:{store.system["draw_depth"] = .number($0); store.saveSystem()}),in:0...1) { Text("Draw depth") }
            Text("Settings are saved beside the session as system.json.").foregroundStyle(.secondary)
        }.padding().frame(width:440)
    }
}
