import Foundation

public struct ThemePool: Sendable {
    public var images: [String] = []
    public var animations: [String] = []
    public var fonts: [String] = []
    public var text: [String] = []
    public var audio: [String] = []
    public var imageTiers: [String: [String]] = [:]
    public init() {}
    mutating func merge(_ other: ThemePool) {
        images += other.images; animations += other.animations; fonts += other.fonts; text += other.text; audio += other.audio
        imageTiers.merge(other.imageTiers) { Array(Set($0 + $1)).sorted() }
    }
}

public struct Session: Sendable {
    public var json: JSONValue
    public let url: URL
    public var pools: [String: ThemePool]
    public var root: URL { url.deletingLastPathComponent() }
    public var programs: [String] { json["program_map"].object.keys.sorted() }
    public init(json: JSONValue, url: URL) throws {
        self.json = try SessionSchema.checked(json); self.url = url; pools = [:]
        try scan(); try validate()
    }
    public static func load(_ url: URL) throws -> Session {
        try Session(json: JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)), url: url)
    }
    public static func new(at url: URL) throws -> Session {
        let program: JSONValue = .object([
            "global_fps": .number(120), "zoom_intensity": .number(0.5),
            "spiral_colour_a": .string("#FFFFFF"), "spiral_colour_b": .string("#000000"),
            "main_text_colour": .string("#FFFFFF"), "shadow_text_colour": .string("#000000"),
            "visual_type": .array([.object(["type": .string("parallel"), "random_weight": .number(1)])])])
        return try Session(json: .object(["format": .string("trance-session"), "format_version": .number(1),
            "theme_scan_root": .string("."), "first_playlist_item": .string("main"),
            "playlist": .object(["main": .object(["standard": .object(["program": .string("default")])])]),
            "program_map": .object(["default": program]), "theme_map": .object([:])]), url: url)
    }
    public func resolve(_ path: String) throws -> URL {
        try SessionSchema.checkPath(path)
        let path = path.replacingOccurrences(of: "\\", with: "/")
        return root.appendingPathComponent(path)
    }
    public func save(to destination: URL? = nil) throws { try json.encoded().write(to: destination ?? url, options: .atomic) }
    public static var defaultVisuals: JSONValue {
        .array(BuiltinPatterns.sources.keys.sorted().map { .object(["type":.string($0),"random_weight":.number(1)]) })
    }
    public static var defaultProgram: JSONValue {
        .object(["global_fps":.number(120),"zoom_intensity":.number(0.5),"visual_type":defaultVisuals,
            "spiral_colour_a":.string("#FF96C832"),"spiral_colour_b":.string("#00000032"),
            "main_text_colour":.string("#FF96C8E0"),"shadow_text_colour":.string("#000000C0"),
            "entrainment":.object(["master_db":.number(-28),"layer":.array([
                .object(["center_hz":.number(312),"binaural_hz":.number(3),"pulse_hz":.number(5),"amplitude_db":.number(0)]),
                .object(["center_hz":.number(60),"binaural_hz":.number(3),"pulse_hz":.number(3.25),"amplitude_db":.number(-6)])])])])
    }
    mutating func validate() throws {
        if json["theme_map"].object.isEmpty { json["theme_map"] = .object(["default":.object([:])]); pools["default"] = ThemePool() }
        if programs.isEmpty { json["program_map"] = .object(["default":Self.defaultProgram]) }
        if json["playlist"].object.isEmpty {
            json["playlist"] = .object(["default":.object(["standard":.object(["program":.string(programs[0])])])])
        }
        for name in json["variable_map"].object.keys {
            var variable = json["variable_map"][name]
            if variable["value"].array.isEmpty { variable["value"] = .array([.string("Default")]) }
            if !variable["value"].array.contains(variable["default_value"]) { variable["default_value"] = variable["value"].array[0] }
            json["variable_map"][name] = variable
        }
        let items = Set(json["playlist"].object.keys)
        for name in items {
            var item = json["playlist"][name]
            if item.object["standard"] != nil {
                let program = item["standard"]["program"].string
                if json["program_map"].object[program] == nil { json["program_map"][program] = Self.defaultProgram }
            } else { item["subroutine"] = .array(item["subroutine"].array.filter { items.contains($0.string) }) }
            var branches = item["next_item"].array.filter { $0["random_weight"].number > 0 && items.contains($0["playlist_item_name"].string) }
            for i in branches.indices {
                let variable = json["variable_map"][branches[i]["condition_variable_name"].string]
                if variable == .null || !variable["value"].array.contains(branches[i]["condition_variable_value"]) {
                    var fields = branches[i].object; fields.removeValue(forKey:"condition_variable_name"); fields.removeValue(forKey:"condition_variable_value"); branches[i] = .object(fields)
                }
            }
            item["next_item"] = .array(branches); json["playlist"][name] = item
        }
        if !items.contains(json["first_playlist_item"].string) { json["first_playlist_item"] = .string(items.sorted()[0]) }
        for name in programs {
            var program = json["program_map"][name]
            program["global_fps"] = .number(min(240,max(1,program["global_fps"].number)))
            program["zoom_intensity"] = .number(min(1,max(0,program["zoom_intensity"].number)))
            var themes = program["enabled_theme"].array
            for i in themes.indices where pools[themes[i]["theme_name"].string] == nil { themes[i]["random_weight"] = .number(0); themes[i]["pinned"] = .bool(false) }
            if !themes.contains(where: { $0["random_weight"].number > 0 || $0["pinned"].bool }) {
                themes = pools.keys.sorted().map { .object(["theme_name":.string($0),"random_weight":.number(1)]) }
            }
            program["enabled_theme"] = .array(themes)
            var patterns = program["custom_visual_pattern"].array
            for i in patterns.indices {
                if !patterns[i]["enabled"].bool { patterns[i]["pinned"] = .bool(false) }
                let file = try resolve(patterns[i]["file"].string)
                guard FileManager.default.fileExists(atPath:file.path) else { throw TranceError("Missing pattern: \(file.path)") }
            }
            program["custom_visual_pattern"] = .array(patterns)
            let visuals = program["visual_type"].array
            if !visuals.contains(where:{ $0["random_weight"].number > 0 || $0["pinned"].bool }), !patterns.contains(where:{$0["enabled"].bool && $0["pinned"].bool}) { program["visual_type"] = Self.defaultVisuals }
            // Protobuf color omission means transparent black, not a UI fallback color.
            for key in ["spiral_colour_a","spiral_colour_b","main_text_colour","shadow_text_colour"] where program.object[key] == nil { program[key] = .string("#00000000") }
            json["program_map"][name] = program
        }
    }
    public mutating func scan() throws {
        var discoveredNames = Set<String>()
        let scanRoot = json["theme_scan_root"]
        let auto = scanRoot.object["auto_rescan"]?.bool ?? true
        let dir = scanRoot.string.isEmpty ? (scanRoot["dir"].string.isEmpty ? "." : scanRoot["dir"].string) : scanRoot.string
        let base = try resolve(dir)
        if auto {
            var dirs = [base]
            if let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let child as URL in enumerator {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { dirs.append(child) }
                }
            }
            for directory in dirs {
                let relative = relativePath(directory)
                let name = relative == "." ? "/root/" : relative
                let discovered = try directPool(directory: directory, exclude: [])
                if json["theme_map"].object[name] == nil, !discovered.images.isEmpty || !discovered.animations.isEmpty || !discovered.text.isEmpty || !discovered.audio.isEmpty {
                    json["theme_map"][name] = .object(["scan": .string(relative)])
                    discoveredNames.insert(name)
                }
            }
        }
        var own: [String: ThemePool] = [:]; var directories: [String: String] = [:]
        for (name, originalTheme) in json["theme_map"].object where !name.hasPrefix("_") {
            var theme = originalTheme
            if theme["scan"] == .null {
                let candidate = name == "/root/" ? "." : name
                if let directory = try? resolve(candidate) {
                    let scanned = try directPool(directory:directory,exclude:[])
                    if !scanned.images.isEmpty || !scanned.animations.isEmpty || !scanned.text.isEmpty || !scanned.audio.isEmpty || !scanned.fonts.isEmpty {
                        theme = .object(["scan":.string(candidate)]); json["theme_map"][name] = theme
                    }
                }
            }
            var pool = ThemePool()
            pool.images = theme["image_path"].array.map(\.string); pool.animations = theme["animation_path"].array.map(\.string)
            pool.fonts = theme["font_path"].array.map(\.string); pool.text = theme["text_line"].array.map(\.string); pool.audio = theme["audio_path"].array.map(\.string)
            for path in pool.images + pool.animations + pool.fonts + pool.audio { _ = try resolve(path) }
            let scan = theme["scan"]
            if scan != .null {
                let path = scan.string.isEmpty ? scan["dir"].string : scan.string
                directories[name] = path
                pool.merge(try directPool(directory: resolve(path), exclude: Set(scan["exclude"].array.map(\.string))))
            }
            pool.imageTiers[name] = pool.images; own[name] = pool
        }
        pools = own
        for name in own.keys {
            var seen = Set([name]); var current = name
            while json["theme_map"][current]["scan"]["inherit"].bool, let directory = directories[current] {
                let ancestors = directories.filter { key, value in key != current && (directory.hasPrefix(value + "/") || value == ".") }
                guard let ancestor = ancestors.max(by: { $0.value.count < $1.value.count }), !seen.contains(ancestor.key) else { break }
                seen.insert(ancestor.key); pools[name]?.merge(own[ancestor.key] ?? ThemePool()); current = ancestor.key
            }
        }
        for name in programs {
            var enabled = json["program_map"][name]["enabled_theme"].array
            for theme in discoveredNames.sorted() where !enabled.contains(where: { $0["theme_name"].string == theme }) {
                enabled.append(.object(["theme_name": .string(theme), "random_weight": .number(1)]))
            }
            json["program_map"][name]["enabled_theme"] = .array(enabled)
        }
    }
    func relativePath(_ url: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path == root.standardizedFileURL.path ? "." : String(path.dropFirst(prefix.count))
    }
    public static func scannedText(_ input: String) -> String {
        let text = Array(input.uppercased())
        guard !text.isEmpty else { return "" }
        var left = text.count/2, right = left
        while true {
            if text[right] == " " { return String(text[..<right])+"\n"+String(text[(right+1)...]) }
            if text[left] == " " { return String(text[..<left])+"\n"+String(text[(left+1)...]) }
            if left == 0 || right == text.count-1 { return String(text) }
            left -= 1; right += 1
        }
    }
    func directPool(directory: URL, exclude: Set<String>) throws -> ThemePool {
        var pool = ThemePool()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return pool }
        let skipped: Set<String> = ["json","session","cfg","pattern","trance","ini","log","bak","tmp","swp","part","crdownload","md","mp4","mov","m4v","mkv","avi","wmv","mpg","mpeg"]
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = relativePath(file), ext = file.pathExtension.lowercased()
            guard !exclude.contains(path), !ext.isEmpty, !skipped.contains(ext), !file.lastPathComponent.hasSuffix("~"), file.lastPathComponent.lowercased() != "thumbs.db" else { continue }
            switch ext {
            case "gif", "webm": pool.animations.append(path)
            case "ttf": pool.fonts.append(path)
            case "wav", "flac", "ogg", "aiff", "mp3": pool.audio.append(path)
            case "txt":
                let contents = try String(contentsOf: file, encoding: .utf8)
                pool.text += contents.components(separatedBy: .newlines).filter { !$0.isEmpty }.map(Self.scannedText)
            default: pool.images.append(path)
            }
        }
        return pool
    }
}
