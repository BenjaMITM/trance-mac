import Foundation

public enum PatternAuthoring {
    public static func beatPeriod(program: JSONValue) -> Int {
        let pulsed = program["entrainment"]["layer"].array.filter { $0["pulse_hz"].number > 0 }
        let layer = pulsed.enumerated().max { lhs,rhs in
            let a = lhs.element["amplitude_db"].number,b = rhs.element["amplitude_db"].number
            return a == b ? lhs.offset < rhs.offset : a < b
        }?.element
        let pulse = layer?["pulse_hz"].number ?? 0
        return pulse > 0 ? Int((program["global_fps"].number/pulse).rounded()) : 0
    }
    public static func validate(source: String, program: JSONValue) throws -> PatternNode {
        var parser = try PatternParser(source,beat:beatPeriod(program:program)); return try parser.parse()
    }
    public static func slug(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        let result = String(name.lowercased().map { allowed.contains($0) ? $0 : "_" })
        return result.isEmpty ? "pattern" : result
    }
    public static func save(session: Session,programName: String,originalName: String?,name: String,source: String,weight: Int,enabled: Bool,pinned: Bool) throws -> Session {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !name.hasPrefix("_") else { throw TranceError("Pattern name must be nonempty and must not begin with _") }
        guard let program = session.json["program_map"].object[programName] else { throw TranceError("Unknown program") }
        _ = try validate(source:source,program:program)
        var rows = program["custom_visual_pattern"].array
        guard !rows.contains(where:{$0["name"].string == name && $0["name"].string != originalName}) else { throw TranceError("A pattern named \(name) already exists") }
        let existingIndex = originalName.flatMap { old in rows.firstIndex { $0["name"].string == old } }
        var file = existingIndex.map { rows[$0]["file"].string } ?? ""
        if file.isEmpty {
            let base = "patterns/"+slug(name); file = base+".pattern"; var suffix = 2
            let used = Set(session.json["program_map"].object.values.flatMap { $0["custom_visual_pattern"].array.map { $0["file"].string } })
            while try used.contains(file) || FileManager.default.fileExists(atPath:session.resolve(file).path) { file = base+"-\(suffix).pattern"; suffix += 1 }
        }
        let destination = try session.resolve(file)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try source.write(to:destination,atomically:true,encoding:.utf8)
        let entry: JSONValue = .object(["name":.string(name),"file":.string(file),"random_weight":.number(Double(max(0,weight))),"enabled":.bool(enabled),"pinned":.bool(enabled && pinned)])
        if let existingIndex { rows[existingIndex] = entry } else { rows.append(entry) }
        var updated = session; updated.json["program_map"][programName]["custom_visual_pattern"] = .array(rows)
        try updated.save(); return updated
    }
}
