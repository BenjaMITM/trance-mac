import SwiftUI
import AppKit
import Observation

@MainActor @Observable final class PlaybackStore {
    var session: Session?
    var programName = ""
    private var manualProgram: String?
    private var manualProgramItem = ""
    var hasProgramOverride: Bool { manualProgram != nil }
    var visualName = "parallel"
    var primaryTheme = ""
    var secondaryTheme = ""
    var previousTheme = ""
    var nextTheme = ""
    var frame = RenderFrame()
    var paused = false { didSet { audio.paused = paused || hidden } }
    var muted = false { didSet { audio.muted = muted || hidden } }
    var hidden = false
    var overlay = false { didSet { applyWindow() } }
    var opacity = 0.35 { didSet { applyWindow() } }
    var showControls = true
    var showDiagnostics = false
    var message: String?
    var diagnostics: [String] = []
    var themePins: [String] = []
    var textPins: [String] = []
    var forcedVisual: String?
    var editorText = ""
    var variables: [String: String] = [:]
    var isLoading = false
    var system: JSONValue = SessionSchema.defaultSystem
    var systemURL: URL?
    @ObservationIgnored let audio = AudioService()
    @ObservationIgnored private var queuedAudio: Task<Void,Never>?
    @ObservationIgnored private var themeAudioGeneration = 0
    @ObservationIgnored private var visualCatalog: VisualCatalog?
    @ObservationIgnored private var visualCatalogKey = ""
    @ObservationIgnored private var runtime: PatternRuntime?
    @ObservationIgnored private var playlist = PlaylistRunner()
    @ObservationIgnored private var registers: [String: (String,Bool)] = [:]
    @ObservationIgnored private var selections: [String: String] = [:]
    @ObservationIgnored private var chances: [String: Bool] = [:]
    @ObservationIgnored private var alternates: [String: Bool] = [:]
    @ObservationIgnored private var counts: [String: Int] = [:]
    @ObservationIgnored private var sharedAnimation = ""
    @ObservationIgnored private var textIndex = 0
    @ObservationIgnored private var lastTime = Date()
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var themeClock = 0.0
    @ObservationIgnored private var contentTime = 0.0
    @ObservationIgnored private var failedPaths = Set<String>()
    var program: JSONValue { session?.json["program_map"][programName] ?? .null }
    var themeNames: [String] { session?.pools.keys.sorted() ?? [] }
    var programNames: [String] { session?.programs ?? [] }
    var customVisuals: [JSONValue] { program["custom_visual_pattern"].array }
    func start() { do { try audio.start() } catch { message = error.localizedDescription }; lastTime = Date() }
    func open() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Open trance session JSON"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func scanFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.title = "Choose media folder"
        if panel.runModal() == .OK, let root = panel.url {
            let url = root.appendingPathComponent("default.json")
            if FileManager.default.fileExists(atPath: url.path) { load(url) }
            else { do { let session = try Session.new(at: url); try session.save(); install(session) } catch { message = error.localizedDescription } }
        }
    }
    func load(_ url: URL) {
        isLoading = true
        Task {
            do {
                let loaded = try await SessionLoader.load(url)
                install(loaded)
            } catch { message = error.localizedDescription }
            isLoading = false
        }
    }
    func install(_ session: Session) {
        do {
            queuedAudio?.cancel(); queuedAudio = nil; themeAudioGeneration += 1; audio.resetPlayback()
            manualProgram = nil; manualProgramItem = ""
            self.session = session; editorText = try session.json.text(); themePins = []; forcedVisual = nil
            for (name, definition) in session.json["variable_map"].object where variables[name] == nil {
                variables[name] = definition["default_value"].string
            }
            playlist = PlaylistRunner(); playlist.variables = variables
            let initialEvents = try playlist.start(session: session)
            dispatchAudio(initialEvents,session:session)
            programName = playlist.program; contentTime = 0; accumulator = 0; themeClock = 0
            let settingsURL = systemURL ?? session.root.appendingPathComponent("system.json")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                system = try SessionSchema.checkedSystem(JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: settingsURL)))
            } else { system = SessionSchema.defaultSystem }
            chooseThemes(); try chooseVisual(); audio.configure(program["entrainment"]); lastTime = Date()
        } catch { message = error.localizedDescription }
    }
    private func dispatchAudio(_ events: [JSONValue],session: Session) {
        guard !events.isEmpty else { return }
        let previous = queuedAudio
        queuedAudio = Task {
            if let previous { await previous.value }
            guard !Task.isCancelled else { return }
            do { try await audio.convertedEvents(events,session:session) }
            catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
    func tick() {
        let now = Date(), delta = min(0.25,now.timeIntervalSince(lastTime)); lastTime = now
        guard let session, !paused, !hidden else { return }
        do {
            playlist.variables = variables
            let events = try playlist.advance(delta,session:session)
            dispatchAudio(events,session:session)
            if manualProgram != nil, playlist.current != manualProgramItem { manualProgram = nil }
            let desiredProgram = manualProgram ?? playlist.program
            if !desiredProgram.isEmpty, desiredProgram != programName { programName = desiredProgram; chooseThemes(); try chooseVisual(); audio.configure(program["entrainment"]) }
            audio.tick(delta); contentTime += delta; themeClock += delta
            if themeClock > 15 { chooseThemes(); themeClock = 0 }
            accumulator += delta*max(1,program["global_fps"].number)
            var steps = 0
            while accumulator >= 1, steps < 60 {
                accumulator -= 1; steps += 1
                if let runtime, runtime.frame+1 >= runtime.root.span, forcedVisual != "runtime" { try chooseVisual() }
                if let draws = runtime?.advance() { evaluate(draws) }
            }
            diagnostics = (runtime?.diagnostics ?? []) + (visualCatalog?.warnings ?? [])
        } catch { paused = true; message = error.localizedDescription }
    }
    func saveProgram(name: String, rename: Bool, copy: Bool) throws {
        guard let session else { throw TranceError("Open a session first") }
        let original = programName
        let updated = try LibraryAuthoring.program(session: session, original: rename ? original : nil,
            name: name, copyFrom: copy ? original : nil)
        try updated.save()
        self.session = updated; editorText = try updated.json.text()
        if rename {
            playlist.renameProgram(from: original, to: name)
            if manualProgram == original { manualProgram = name }
            programName = name
        } else { selectProgram(name) }
    }
    func selectProgram(_ name: String) {
        guard programNames.contains(name) else { return }
        manualProgram = name; manualProgramItem = playlist.current; programName = name
        chooseThemes(); audio.configure(program["entrainment"])
        do { try chooseVisual() } catch { message = error.localizedDescription }
    }
    func releaseProgram() {
        manualProgram = nil
        if !playlist.program.isEmpty { programName = playlist.program }
        chooseThemes(); audio.configure(program["entrainment"])
        do { try chooseVisual() } catch { message = error.localizedDescription }
    }
    func chooseThemes() {
        let rows = program["enabled_theme"].array.filter { session?.pools[$0["theme_name"].string] != nil }
        let pins = themePins.isEmpty ? rows.filter { $0["pinned"].bool }.map { $0["theme_name"].string } : themePins
        let weighted = rows.map { ($0["theme_name"].string,$0["random_weight"].number) }
        previousTheme = primaryTheme
        if !themePins.isEmpty, pins.count == 1 { primaryTheme = pins[0]; secondaryTheme = pins[0] }
        else if pins.count == 1 { primaryTheme = pins[0]; secondaryTheme = WeightedChoice.choose(weighted.filter { $0.0 != primaryTheme }) ?? primaryTheme }
        else if pins.count >= 2 { primaryTheme = pins.randomElement() ?? ""; secondaryTheme = pins.filter { $0 != primaryTheme }.randomElement() ?? primaryTheme }
        else { primaryTheme = WeightedChoice.choose(weighted) ?? themeNames.first ?? ""; secondaryTheme = WeightedChoice.choose(weighted.filter { $0.0 != primaryTheme }) ?? primaryTheme }
        nextTheme = WeightedChoice.choose(weighted) ?? primaryTheme
    }
    func chooseVisual() throws {
        if let forcedVisual { try forceSource(name: forcedVisual, source: source(forcedVisual)); return }
        guard let session else { return }
        var key = session.url.path + programName + (try program.text())
        for row in customVisuals where row["enabled"].bool {
            let url = try session.resolve(row["file"].string)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            key += "|\(url.path)|\(attributes?[.modificationDate] ?? "missing")|\(attributes?[.size] ?? 0)"
        }
        if visualCatalog == nil || key != visualCatalogKey {
            visualCatalog = try VisualCatalog(program: program) { row in
                try String(contentsOf: session.resolve(row["file"].string), encoding: .utf8)
            }
            visualCatalogKey = key
            for warning in visualCatalog?.warnings ?? [] {
                try? FileHandle.standardError.write(contentsOf: Data((warning + "\n").utf8))
            }
        }
        guard let selected = visualCatalog?.choose() else { throw TranceError("No playable visual") }
        runtime = PatternRuntime(root: selected.node); visualName = selected.name
        registers = [:]; selections = [:]; chances = [:]; counts = [:]; alternates = [:]
    }

    func source(_ name: String) throws -> String {
        if let source = BuiltinPatterns.sources[name == "simple" ? "parallel" : name] { return source }
        guard let custom = customVisuals.first(where: { $0["name"].string == name }), let session else { throw TranceError("Unknown visual \(name)") }
        return try String(contentsOf: session.resolve(custom["file"].string),encoding: .utf8)
    }
    func forceSource(name: String, source: String) throws {
        let node = try PatternAuthoring.validate(source:source,program:program)
        runtime = PatternRuntime(root: node); visualName = name
        registers = [:]; selections = [:]; chances = [:]; counts = [:]; alternates = [:]
    }
    func forceVisual(_ name: String) { do { try forceSource(name: name,source: source(name)); forcedVisual = name } catch { message = error.localizedDescription } }
    func releaseVisual() { forcedVisual = nil; do { try chooseVisual() } catch { message = error.localizedDescription } }
    private func lane(_ draw: PatternDraw) -> String {
        switch draw.effect.content {
        case "primary": return primaryTheme
        case "secondary": return secondaryTheme
        case "alternate":
            if draw.entry, Double.random(in: 0..<1) < (draw.effect.alternateChance ?? 1) { alternates[draw.key] = !(alternates[draw.key] ?? false) }
            return alternates[draw.key] == true ? secondaryTheme : primaryTheme
        default: return Bool.random() ? primaryTheme : secondaryTheme
        }
    }
    private func registerKey(_ name: String, scope: String) -> String { scope + ":" + name }
    private func pickImage(_ pool: ThemePool) -> String? {
        let tiers = pool.imageTiers.map { name, paths in (paths, program["enabled_theme"].array.first { $0["theme_name"].string == name }?["random_weight"].number ?? 1) }.filter { !$0.0.isEmpty }
        return WeightedChoice.choose(tiers.map { ($0.0,max(1,$0.1)) })?.randomElement() ?? pool.images.randomElement()
    }
    private func evaluate(_ draws: [PatternDraw]) {
        var result = RenderFrame(); result.time = contentTime
        for draw in draws {
            let effect = draw.effect, key = draw.registerKey(effect.register)
            if draw.entry {
                let chance = effect.chance.map { min(0.99,max(0.01,$0)) } ?? 1
                chances[draw.key] = Double.random(in: 0..<1) < chance
                if chances[draw.key] == true {
                    let theme = lane(draw), pool = session?.pools[theme] ?? ThemePool()
                    counts[draw.key,default: 0] += 1
                    switch effect.kind {
                    case "image":
                        let animated = effect.animated && counts[draw.key,default: 0] % effect.animationEvery == 0
                        if animated, let path = pool.animations.randomElement() { sharedAnimation = path }
                        if let path = pickImage(pool) ?? (animated ? pool.animations.randomElement() : nil) { registers[key] = (path,animated) }
                    case "copy": if let value = registers[key] { registers[draw.registerKey(effect.destination)] = value }
                    case "word","line","caption","subtext":
                        var text = pool.text.randomElement() ?? ""
                        if !textPins.isEmpty { text = textPins[textIndex % textPins.count]; textIndex += 1 }
                        if effect.kind == "word" { text = text.split(whereSeparator: \.isWhitespace).randomElement().map(String.init) ?? text }
                        selections[draw.key] = text
                        selections[draw.key+"font"] = pool.fonts.randomElement()
                    case "anim": sharedAnimation = pool.animations.randomElement() ?? ""
                    case "audio":
                        do {
                            if effect.content == "stop" { themeAudioGeneration += 1; try audio.theme(path: nil) }
                            else if let path = pool.audio.randomElement(), let session { let url = try session.resolve(path)
                            themeAudioGeneration += 1
                            let generation = themeAudioGeneration
                            Task {
                                do {
                                    let compatible = try await CodecService.shared.compatibleURL(url)
                                    guard generation == themeAudioGeneration else { return }
                                    try audio.theme(path:compatible,loop:effect.loop)
                                } catch { if generation == themeAudioGeneration { message = error.localizedDescription } }
                            } }
                        } catch { message = error.localizedDescription }
                    default: break
                    }
                }
            }
            guard draw.visible else { continue }
            switch effect.kind {
            case "image","draw":
                if let value = registers[key] {
                    let useAnimation = (value.1 || effect.animated) && !sharedAnimation.isEmpty
                    result.layers.append(RenderLayer(path: useAnimation ? sharedAnimation : value.0,animated: useAnimation,alpha: max(0,min(1,draw.value("alpha",default: 1))),zoom: draw.value("zoom")*program["zoom_intensity"].number,origin: draw.value("origin")))
                }
            case "word","line","caption","subtext":
                if chances[draw.key] == true { result.texts.append(RenderText(text: selections[draw.key] ?? "",kind: effect.kind,alpha: draw.value("alpha",default: 1),zoom: draw.value("zoom"),origin: draw.value("origin"),fontPath: selections[draw.key+"font"])) }
            case "spiral": result.spiralSpeed = draw.value("speed",default: 1)
            case "look": result.spiralType = draw.value("type"); result.spiralWidth = draw.value("width",default: 1)
            case "warp","drunk": result.warpAmplitude = draw.value("amplitude"); result.warpWavelength = draw.value("wavelength",default: 0.15); result.warpSpeed = draw.value("speed",default: 2)
            case "audio": if effect.values["volume"] != nil { audio.themeGain(draw.value("volume")) }
            default: break
            }
        }
        frame = result
    }
    func applyEditor() {
        guard let session else { return }
        do { let json = try JSONDecoder().decode(JSONValue.self,from: Data(editorText.utf8)); let updated = try Session(json: json,url: session.url); try updated.save(); install(updated) } catch { message = error.localizedDescription }
    }
    func updateProgram(_ key: String, _ value: JSONValue, save: Bool = true) {
        session?.json["program_map"][programName][key] = value
        audio.configure(program["entrainment"])
        if save { autosave() }
    }
    func autosave() { do { try session?.save(); if let session { editorText = try session.json.text() } } catch { message = error.localizedDescription } }
    func exportJSON() { guard let session else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "export.session.json"; if panel.runModal() == .OK, let url = panel.url { do { try session.save(to: url) } catch { message = error.localizedDescription } } }
    func exportArchive() {
        guard let session else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "portable.trance"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do { try await ArchiveWriter.shared.export(session,to:url) }
                catch { message = error.localizedDescription }
            }
        }
    }
    func saveSystem() { guard let session else { return }; do { system = try SessionSchema.checkedSystem(system); try system.encoded().write(to: systemURL ?? session.root.appendingPathComponent("system.json"),options: .atomic) } catch { message = error.localizedDescription } }
    func setHidden(_ value: Bool) {
        hidden = value
        if value { overlay = false; NSApp.windows.filter { $0.identifier?.rawValue == "player" || $0.title == "Trance" }.forEach { $0.orderOut(nil) } }
        else { NSApp.windows.filter { $0.identifier?.rawValue == "player" || $0.title == "Trance" }.forEach { $0.makeKeyAndOrderFront(nil) }; NSApp.activate(ignoringOtherApps: true) }
        audio.paused = paused || hidden; audio.muted = muted || hidden
    }
    func applyWindow() {
        for window in NSApp.windows where window.identifier?.rawValue == "player" || window.title == "Trance" {
            window.ignoresMouseEvents = overlay; window.level = overlay ? .floating : .normal
            window.alphaValue = overlay ? opacity : 1
            window.collectionBehavior = overlay ? [.canJoinAllSpaces,.fullScreenAuxiliary] : [.managed,.fullScreenPrimary]
        }
    }
    func revealControls() { setHidden(false); overlay = false; showControls = true }
}
private actor SessionLoader {
    static let shared = SessionLoader()
    static func load(_ url: URL) async throws -> Session { try await shared.read(url) }
    private func read(_ url: URL) throws -> Session { url.pathExtension == "session" ? try LegacyImporter.importSession(url) : try Session.load(url) }
}

private actor ArchiveWriter {
    static let shared = ArchiveWriter()
    func export(_ session: Session,to url: URL) throws { try ArchiveExporter.export(session,to:url) }
}
