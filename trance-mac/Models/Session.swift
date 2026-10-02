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
        self.json = json; self.url = url; pools = [:]
        try validate(); try scan()
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
        let path = path.replacingOccurrences(of: "\\", with: "/")
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains(":"), !path.split(separator: "/").contains("..") else {
            throw TranceError("Asset path must be relative to the session: \(path)")
        }
        return root.appendingPathComponent(path)
    }
    public func save(to destination: URL? = nil) throws { try json.encoded().write(to: destination ?? url, options: .atomic) }
    mutating func validate() throws {
        guard json["format"].string == "trance-session", json["format_version"].number <= 1 else { throw TranceError("Unsupported session format/version") }
        guard !programs.isEmpty, !json["playlist"].object.isEmpty else { throw TranceError("Session needs a program and playlist") }
        for (name, item) in json["playlist"].object where !name.hasPrefix("_") {
            guard (item.object["standard"] != nil) != (item.object["subroutine"] != nil) else { throw TranceError("Playlist \(name) needs exactly one standard or subroutine") }
            if let standard = item.object["standard"], json["program_map"].object[standard["program"].string] == nil { throw TranceError("Unknown program in \(name)") }
        }
        guard json["playlist"].object[json["first_playlist_item"].string] != nil else { throw TranceError("Unknown first playlist item") }
        for name in programs {
            var program = json["program_map"][name]
            program["global_fps"] = .number(min(240, max(1, program["global_fps"].number)))
            program["zoom_intensity"] = .number(min(1, max(0, program["zoom_intensity"].number)))
            for pattern in program["custom_visual_pattern"].array {
                let path = try resolve(pattern["file"].string)
                guard FileManager.default.fileExists(atPath: path.path) else { throw TranceError("Missing pattern: \(path.path)") }
            }
            json["program_map"][name] = program
        }
    }
    public mutating func scan() throws {
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
                }
            }
        }
        var own: [String: ThemePool] = [:]; var directories: [String: String] = [:]
        for (name, theme) in json["theme_map"].object where !name.hasPrefix("_") {
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
            for theme in pools.keys.sorted() where !enabled.contains(where: { $0["theme_name"].string == theme }) {
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
                pool.text += contents.components(separatedBy: .newlines).filter { !$0.isEmpty }.map { $0.uppercased() }
            default: pool.images.append(path)
            }
        }
        return pool
    }
}
