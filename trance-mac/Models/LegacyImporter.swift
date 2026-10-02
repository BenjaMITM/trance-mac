import Foundation

/// Frozen upstream text-protobuf conversion; leaves the input file intact.
public enum LegacyImporter {
    public static func importSession(_ url: URL) throws -> Session {
        var parser = try ProtoTextParser(String(contentsOf:url,encoding:.utf8))
        let raw = try parser.parse()
        var json: JSONValue = .object(["format":.string("trance-session"),"format_version":.number(1),"first_playlist_item":raw["first_playlist_item"]])
        for key in ["theme_map","program_map","playlist","variable_map"] {
            var map: [String:JSONValue] = [:]
            for entry in values(raw[key]) { let name = entry["key"].string; guard !name.isEmpty else { throw TranceError("Legacy map \(key) has no key") }; map[name] = entry["value"] }
            json[key] = .object(map)
        }
        for (name,value) in json["program_map"].object {
            var program = value
            for key in ["enabled_theme","visual_type"] { program[key] = .array(values(value[key])) }
            for theme in values(value["enabled_theme_name"]) { var rows = program["enabled_theme"].array; rows.append(.object(["theme_name":theme,"random_weight":.number(1)])); program["enabled_theme"] = .array(rows) }
            var object = program.object; object.removeValue(forKey:"enabled_theme_name"); program = .object(object)
            var visuals = program["visual_type"].array
            let types = ["NONE":"none","ACCELERATE":"accelerate","SLOW_FLASH":"slow_flash","SUB_TEXT":"sub_text","FLASH_TEXT":"flash_text","PARALLEL":"parallel","SUPER_PARALLEL":"super_parallel","ANIMATION":"animation","SUPER_FAST":"super_fast"]
            for i in visuals.indices { visuals[i]["type"] = .string(types[visuals[i]["type"].string] ?? "parallel") }
            program["visual_type"] = .array(visuals)
            for key in ["spiral_colour_a","spiral_colour_b","main_text_colour","shadow_text_colour"] where program[key] != .null {
                let color = program[key]; let bytes = ["r","g","b","a"].map { UInt8(max(0,min(255,(color[$0].number*255).rounded()))) }
                program[key] = .string("#"+bytes.map { String(format:"%02X",$0) }.joined())
            }
            json["program_map"][name] = program
        }
        for (name,value) in json["theme_map"].object {
            var theme = value
            for key in ["image_path","animation_path","font_path","text_line"] { theme[key] = .array(values(value[key])) }
            json["theme_map"][name] = theme
        }
        for (name,value) in json["variable_map"].object { var variable = value; variable["value"] = .array(values(value["value"])); json["variable_map"][name] = variable }
        for (name,value) in json["playlist"].object {
            var item = value
            if item.object["standard"] == nil, item.object["subroutine"] == nil { item["standard"] = .object(["program":item["program"],"play_time_seconds":item["play_time_seconds"]]); var object = item.object; object.removeValue(forKey:"program"); object.removeValue(forKey:"play_time_seconds"); item = .object(object) }
            if item["subroutine"] != .null { item["subroutine"] = .array(values(item["subroutine"]["playlist_item_name"])) }
            item["next_item"] = .array(values(item["next_item"]))
            var audio = values(item["audio_event"])
            for i in audio.indices { let type = audio[i]["type"].string; audio[i]["type"] = .string(["AUDIO_PLAY":"play","AUDIO_STOP":"stop","AUDIO_FADE":"fade"][type] ?? "none") }
            item["audio_event"] = .array(audio); json["playlist"][name] = item
        }
        let destination = url.deletingPathExtension().appendingPathExtension("json")
        // Do not overwrite an existing migration result.
        if FileManager.default.fileExists(atPath:destination.path) { return try Session.load(destination) }
        let session = try Session(json:json,url:destination); try session.save(); return session
    }
    private static func values(_ value: JSONValue) -> [JSONValue] { if value == .null { return [] }; if case .array(let a) = value { return a }; return [value] }
}
private struct ProtoTextParser {
    var tokens: [String]; var index = 0
    init(_ source: String) throws {
        let regex = try NSRegularExpression(pattern:#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|#[^\n]*|//[^\n]*|[A-Za-z_][A-Za-z_0-9]*|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?|[^\s]"#)
        let ns = source as NSString
        tokens = regex.matches(in:source,range:NSRange(location:0,length:ns.length)).map { ns.substring(with:$0.range) }.filter { !$0.hasPrefix("#") && !$0.hasPrefix("//") }
    }
    mutating func parse(end: String? = nil) throws -> JSONValue {
        var object: [String:JSONValue] = [:]
        while index < tokens.count, tokens[index] != end {
            let key = tokens[index]; index += 1
            if index < tokens.count, tokens[index] == ":" { index += 1 }
            guard index < tokens.count else { throw TranceError("Incomplete legacy field \(key)") }
            let token = tokens[index]; index += 1
            let value: JSONValue
            if token == "{" || token == "<" { value = try parse(end: token == "{" ? "}" : ">"); guard index < tokens.count else { throw TranceError("Unclosed legacy message") }; index += 1 }
            else if token.hasPrefix("\"") {
                guard let string = try? JSONDecoder().decode(String.self,from:Data(token.utf8)) else { throw TranceError("Invalid legacy string escape") }; value = .string(string)
            } else if let number = Double(token) { value = .number(number) }
            else if token == "true" || token == "false" { value = .bool(token == "true") }
            else { value = .string(token) }
            if let old = object[key] { if case .array(let items) = old { object[key] = .array(items+[value]) } else { object[key] = .array([old,value]) } } else { object[key] = value }
            if index < tokens.count, [",",";"].contains(tokens[index]) { index += 1 }
        }
        return .object(object)
    }
}
