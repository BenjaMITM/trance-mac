import Foundation

/// Edits named libraries while preserving every reference to renamed entries.
public enum LibraryAuthoring {
    private static func checkName(_ name: String, original: String?, map: JSONValue) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.hasPrefix("_") else { throw TranceError("Name must be nonempty and must not begin with _") }
        guard map.object[name] == nil || original == name else { throw TranceError("An entry named \(name) already exists") }
    }
    public static func theme(session: Session, original: String?, name: String, definition: JSONValue, program: String, weight: Int, pinned: Bool) throws -> Session {
        try checkName(name, original: original, map: session.json["theme_map"])
        guard session.programs.contains(program), weight >= 0, weight <= Int(UInt32.max) else { throw TranceError("Invalid program or theme weight") }
        for key in ["image_path", "animation_path", "font_path", "audio_path"] {
            for path in definition[key].array {
                guard FileManager.default.fileExists(atPath: try session.resolve(path.string).path) else { throw TranceError("Missing asset: \(path.string)") }
            }
        }
        if definition.object["scan"] != nil {
            let scan = definition["scan"]
            let path = scan.object.isEmpty ? scan.string : scan["dir"].string
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: try session.resolve(path).path, isDirectory: &directory), directory.boolValue else { throw TranceError("Scan directory is missing: \(path)") }
        }
        var json = session.json
        var themes = json["theme_map"].object
        if let original, original != name { themes.removeValue(forKey: original) }
        themes[name] = definition; json["theme_map"] = .object(themes)
        for key in session.programs {
            var rows = json["program_map"][key]["enabled_theme"].array
            for i in rows.indices where rows[i]["theme_name"].string == original { rows[i]["theme_name"] = .string(name) }
            if key == program {
                let row: JSONValue = .object(["theme_name": .string(name), "random_weight": .number(Double(weight)), "pinned": .bool(pinned)])
                if let index = rows.firstIndex(where: { $0["theme_name"].string == name }) { rows[index] = row } else { rows.append(row) }
            }
            json["program_map"][key]["enabled_theme"] = .array(rows)
        }
        return try Session(json: json, url: session.url)
    }
    public static func variable(session: Session, original: String?, name: String, description: String, values: [String], defaultValue: String) throws -> Session {
        try checkName(name, original: original, map: session.json["variable_map"])
        guard !values.isEmpty, Set(values).count == values.count, !values.contains(""), values.contains(defaultValue) else { throw TranceError("Allowed values must be unique and nonempty, and include the default") }
        var json = session.json
        for key in json["playlist"].object.keys {
            var branches = json["playlist"][key]["next_item"].array
            for i in branches.indices where branches[i]["condition_variable_name"].string == (original ?? name) {
                guard values.contains(branches[i]["condition_variable_value"].string) else { throw TranceError("Playlist item \(key) still uses value \(branches[i]["condition_variable_value"].string)") }
                branches[i]["condition_variable_name"] = .string(name)
            }
            json["playlist"][key]["next_item"] = .array(branches)
        }
        var variables = json["variable_map"].object
        if let original, original != name { variables.removeValue(forKey: original) }
        variables[name] = .object(["description": .string(description), "value": .array(values.map(JSONValue.string)), "default_value": .string(defaultValue)])
        json["variable_map"] = .object(variables)
        return try Session(json: json, url: session.url)
    }
}
