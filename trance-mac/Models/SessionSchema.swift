import Foundation

/// The original JSON format rejects unknown fields and wrong types before repairing
/// references. Comment keys are removed at every level, including named maps.
public enum SessionSchema {
    private indirect enum Field: Sendable {
        case string, boolean, number, unsigned, integer, color, path
        case enumeration(Set<String>), array(Field), object([String:Field]), map(Field), either(Field,Field)
    }
    private static let scan = Field.either(.path,.object(["dir":.path,"inherit":.boolean,"exclude":.array(.path)]))
    private static let theme = Field.object(["scan":scan,"image_path":.array(.path),"animation_path":.array(.path),"font_path":.array(.path),"audio_path":.array(.path),"text_line":.array(.string)])
    private static let variable = Field.object(["description":.string,"value":.array(.string),"default_value":.string])
    private static let branch = Field.object(["playlist_item_name":.string,"random_weight":.unsigned,"condition_variable_name":.string,"condition_variable_value":.string])
    private static let cue = Field.object(["type":.enumeration(["play","stop","fade"]),"channel":.unsigned,"next_unused_channel":.boolean,"path":.path,"loop":.boolean,"volume":.unsigned,"time_seconds":.unsigned])
    private static let item = Field.object(["standard":.object(["program":.string,"play_time_seconds":.unsigned]),"subroutine":.array(.string),"next_item":.array(branch),"audio_event":.array(cue)])
    private static let program = Field.object([
        "enabled_theme":.array(.object(["theme_name":.string,"random_weight":.unsigned,"pinned":.boolean])),
        "visual_type":.array(.object(["type":.enumeration(Set(BuiltinPatterns.sources.keys)),"random_weight":.unsigned,"pinned":.boolean])),
        "custom_visual_pattern":.array(.object(["name":.string,"file":.path,"random_weight":.unsigned,"enabled":.boolean,"pinned":.boolean])),
        "global_fps":.unsigned,"zoom_intensity":.number,"spiral_colour_a":.color,"spiral_colour_b":.color,
        "main_text_colour":.color,"shadow_text_colour":.color,"reverse_spiral_direction":.boolean,
        "entrainment":.object(["master_db":.number,"layer":.array(.object(["center_hz":.number,"binaural_hz":.number,"pulse_hz":.number,"amplitude_db":.number]))])])
    private static let session = Field.object([
        "format":.enumeration(["trance-session"]),"format_version":.integer,"first_playlist_item":.string,
        "playlist":.map(item),"program_map":.map(program),"theme_map":.map(theme),"variable_map":.map(variable),
        "theme_scan_root":.either(.path,.object(["dir":.path,"auto_rescan":.boolean]))])
    public static func checked(_ json: JSONValue) throws -> JSONValue {
        let value = stripComments(json)
        try check(value, against: session, at: "session")
        guard value.object["format"] != nil, value.object["format_version"] != nil else { throw TranceError("session: format and format_version are required") }
        guard value["format_version"].number <= 1 else { throw TranceError("session/format_version: unsupported version") }
        for (name,item) in value["playlist"].object {
            let path = "session/playlist/\(name)"
            guard (item.object["standard"] != nil) != (item.object["subroutine"] != nil) else { throw TranceError("\(path): exactly one standard or subroutine is required") }
            for branch in item["next_item"].array {
                guard (branch.object["condition_variable_name"] != nil) == (branch.object["condition_variable_value"] != nil) else { throw TranceError("\(path)/next_item: both condition fields are required together") }
            }
        }
        for (name,program) in value["program_map"].object {
            var names = Set<String>()
            for pattern in program["custom_visual_pattern"].array {
                let identity = pattern["name"].string
                guard !identity.isEmpty, !pattern["file"].string.isEmpty else { throw TranceError("session/program_map/\(name): pattern name and file are required") }
                guard names.insert(identity).inserted else { throw TranceError("session/program_map/\(name): duplicate pattern name \(identity)") }
            }
        }
        for (name,theme) in value["theme_map"].object {
            if case .object(let scan) = theme["scan"], scan["dir"] == nil { throw TranceError("session/theme_map/\(name)/scan: dir is required") }
        }
        if case .object(let scan) = value["theme_scan_root"], scan["dir"] == nil { throw TranceError("session/theme_scan_root: dir is required") }
        return value
    }
    public static func stripComments(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object): return .object(object.filter { !$0.key.hasPrefix("_") }.mapValues(stripComments))
        case .array(let array): return .array(array.map(stripComments))
        default: return value
        }
    }
    public static func checkPath(_ path: String) throws {
        let normalized = path.replacingOccurrences(of:"\\",with:"/")
        guard !normalized.hasPrefix("/"), !normalized.hasPrefix("~"), !normalized.contains(":"), !normalized.split(separator:"/").contains(".."), !normalized.contains("\0") else { throw TranceError("Asset path must be relative to the session: \(path)") }
    }
    private static func check(_ value: JSONValue, against field: Field, at path: String) throws {
        func fail(_ description: String) throws -> Never { throw TranceError("\(path): \(description)") }
        switch field {
        case .string: guard case .string = value else { try fail("expected string") }
        case .boolean: guard case .bool = value else { try fail("expected boolean") }
        case .number,.integer,.unsigned:
            guard case .number(let number) = value, number.isFinite else { try fail("expected finite number") }
            switch field {
            case .unsigned: guard number >= 0, number <= Double(UInt32.max), number.rounded(.towardZero) == number else { try fail("expected unsigned 32-bit integer") }
            case .integer: guard number.rounded(.towardZero) == number else { try fail("expected integer") }
            default: break
            }
        case .color:
            guard case .string(let text) = value, text.hasPrefix("#"), [7,9].contains(text.count), UInt64(text.dropFirst(),radix:16) != nil else { try fail("expected #RRGGBB or #RRGGBBAA color") }
        case .path:
            guard case .string(let text) = value else { try fail("expected path string") }; try checkPath(text)
        case .enumeration(let choices):
            guard case .string(let text) = value, choices.contains(text) else { try fail("expected one of \(choices.sorted().joined(separator:", "))") }
        case .array(let element):
            guard case .array(let values) = value else { try fail("expected array") }
            for (i,elementValue) in values.enumerated() { try check(elementValue,against:element,at:"\(path)[\(i)]") }
        case .object(let fields):
            guard case .object(let values) = value else { try fail("expected object") }
            for key in values.keys.sorted() {
                guard let shape = fields[key] else { try fail("unknown field '\(key)'") }
                try check(values[key]!,against:shape,at:path+"/"+key)
            }
        case .map(let shape):
            guard case .object(let values) = value else { try fail("expected named map") }
            for key in values.keys.sorted() { try check(values[key]!,against:shape,at:path+"/"+key) }
        case .either(let a,let b):
            switch value { case .string: try check(value,against:a,at:path); default: try check(value,against:b,at:path) }
        }
    }
}
