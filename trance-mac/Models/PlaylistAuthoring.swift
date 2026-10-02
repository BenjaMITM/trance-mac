import Foundation

public enum PlaylistAuthoring {
    public static func save(session: Session,originalName: String?,name: String,item: JSONValue,first: Bool) throws -> Session {
        guard !name.isEmpty, !name.hasPrefix("_") else { throw TranceError("Playlist name must be nonempty and must not begin with _") }
        var json = session.json; var items = json["playlist"].object
        guard items[name] == nil || name == originalName else { throw TranceError("A playlist item named \(name) already exists") }
        if item.object["standard"] != nil {
            guard session.programs.contains(item["standard"]["program"].string) else { throw TranceError("Choose an existing program") }
        }
        let validItems = Set(items.keys).union([name])
        for child in item["subroutine"].array where !validItems.contains(child.string) { throw TranceError("Unknown subroutine child: \(child.string)") }
        for branch in item["next_item"].array {
            guard validItems.contains(branch["playlist_item_name"].string) else { throw TranceError("Unknown branch destination") }
            if !branch["condition_variable_name"].string.isEmpty {
                let variable = session.json["variable_map"][branch["condition_variable_name"].string]
                guard variable != .null, variable["value"].array.contains(branch["condition_variable_value"]) else { throw TranceError("Choose an existing variable and allowed value for the branch") }
            }
        }
        for cue in item["audio_event"].array where cue["type"].string == "play" {
            guard !cue["path"].string.isEmpty, FileManager.default.fileExists(atPath:try session.resolve(cue["path"].string).path) else { throw TranceError("Audio cue file is missing: \(cue["path"].string)") }
        }
        if let originalName, originalName != name {
            items.removeValue(forKey:originalName)
            for key in Array(items.keys) {
                var row = items[key]!
                if row.object["subroutine"] != nil { row["subroutine"] = .array(row["subroutine"].array.map { $0.string == originalName ? .string(name) : $0 }) }
                var branches = row["next_item"].array
                for i in branches.indices where branches[i]["playlist_item_name"].string == originalName { branches[i]["playlist_item_name"] = .string(name) }
                row["next_item"] = .array(branches); items[key] = row
            }
            if json["first_playlist_item"].string == originalName { json["first_playlist_item"] = .string(name) }
        }
        var edited = item
        if let originalName, originalName != name {
            if edited.object["subroutine"] != nil { edited["subroutine"] = .array(edited["subroutine"].array.map { $0.string == originalName ? .string(name) : $0 }) }
            var branches = edited["next_item"].array
            for i in branches.indices where branches[i]["playlist_item_name"].string == originalName { branches[i]["playlist_item_name"] = .string(name) }
            edited["next_item"] = .array(branches)
        }
        items[name] = edited; json["playlist"] = .object(items)
        if first { json["first_playlist_item"] = .string(name) }
        return try Session(json:json,url:session.url)
    }
}
