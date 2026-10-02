import SwiftUI
import AppKit

struct TranceApp: App {
    @NSApplicationDelegateAdaptor(TranceDelegate.self) private var delegate
    @State private var store: PlaybackStore
    init() {
        let state = PlaybackStore()
        _store = State(initialValue: state)
        delegate.store = state
    }
    var body: some Scene {
        WindowGroup("Trance",id:"player") { ContentView(store:store).frame(minWidth:800,minHeight:500).onAppear { delegate.store = store; delegate.configure() } }
            .defaultLaunchBehavior(.presented)
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
    var store: PlaybackStore?
    private var startupWindow: NSWindow?
    private var configured = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); configure()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard let store, !store.hidden else { return }
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "player" || $0.title == "Trance" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                // SwiftUI restoration can omit its initial window when launched by Xcode.
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = "Trance"; window.identifier = NSUserInterfaceItemIdentifier("player")
                window.contentView = NSHostingView(rootView: ContentView(store: store))
                window.center(); startupWindow = window; window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    private var commands: CommandService?
    private var hotkey: HotkeyService?
    func configure() {
        guard !configured, let store else { return }; configured = true
        do {
            let options = try LaunchOptions(arguments:Array(CommandLine.arguments.dropFirst()))
            store.muted = options.muted; store.overlay = options.overlay; store.opacity = options.opacity
            store.variables = options.variables; store.forcedVisual = options.visual
            if let system = options.system { store.systemURL = system; store.system = try SessionSchema.checkedSystem(JSONDecoder().decode(JSONValue.self,from:Data(contentsOf:system))) }
            let url = options.session ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("default.json")
            if options.session != nil || FileManager.default.fileExists(atPath:url.path) {
                let session = url.pathExtension == "session" ? try LegacyImporter.importSession(url) : try Session.load(url)
                store.install(session)
            } else if options.lint || options.archive != nil { throw TranceError("Supply a session file") }
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
