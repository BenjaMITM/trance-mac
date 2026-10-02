import Foundation

public struct PlaylistRunner: Sendable {
    public private(set) var current = ""
    public private(set) var elapsed: Double = 0
    public private(set) var program = ""
    private var stack: [(String, Int)] = []
    private var pending: [JSONValue] = []
    public var variables: [String: String] = [:]
    public init() {}
    public mutating func start(session: Session) throws -> [JSONValue] {
        current = ""; elapsed = 0; stack = []; pending = []
        try enter(session.json["first_playlist_item"].string, session: session)
        let events = pending; pending = []; return events
    }
    private mutating func enter(_ name: String, session: Session) throws {
        guard let item = session.json["playlist"].object[name] else { throw TranceError("Missing playlist item: \(name)") }
        current = name; elapsed = 0; pending += item["audio_event"].array
        if item.object["standard"] != nil { program = item["standard"]["program"].string }
    }
    public mutating func advance(_ seconds: Double, session: Session) throws -> [JSONValue] {
        elapsed += seconds
        for _ in 0..<1024 {
            let item = session.json["playlist"][current]
            if item.object["subroutine"] != nil {
                let children = item["subroutine"].array.map(\.string)
                if !children.isEmpty {
                    guard stack.count < 256 else { throw TranceError("Playlist subroutine depth exceeds 256") }
                    stack.append((current, 1)); try enter(children[0], session: session); continue
                }
            } else if elapsed < item["standard"]["play_time_seconds"].number { break }
            let branches = item["next_item"].array.filter { branch in
                let variable = branch["condition_variable_name"].string
                return variable.isEmpty || (variables[variable] ?? "") == branch["condition_variable_value"].string
            }
            if let next = WeightedChoice.choose(branches.map { ($0["playlist_item_name"].string, $0["random_weight"].number) }) {
                try enter(next, session: session); continue
            }
            guard let caller = stack.popLast() else { break }
            let children = session.json["playlist"][caller.0]["subroutine"].array.map(\.string)
            if caller.1 < children.count {
                stack.append((caller.0, caller.1 + 1)); try enter(children[caller.1], session: session)
            } else {
                current = caller.0; elapsed = .infinity
                // Returning to the caller must process its branches, not re-enter its children.
                let callerBranches = session.json["playlist"][current]["next_item"].array.filter {
                    $0["condition_variable_name"].string.isEmpty || (variables[$0["condition_variable_name"].string] ?? "") == $0["condition_variable_value"].string
                }
                if let next = WeightedChoice.choose(callerBranches.map { ($0["playlist_item_name"].string, $0["random_weight"].number) }) { try enter(next, session: session) }
                else if stack.isEmpty { break }
                else { try finishCaller(session: session) }
            }
        }
        if elapsed == 0, session.json["playlist"][current]["standard"]["play_time_seconds"].number == 0,
           !session.json["playlist"][current]["next_item"].array.isEmpty {
            throw TranceError("Playlist made too many immediate transitions; give cyclic items positive durations")
        }
        let events = pending; pending = []; return events
    }
    private mutating func finishCaller(session: Session) throws {
        while let caller = stack.popLast() {
            let children = session.json["playlist"][caller.0]["subroutine"].array.map(\.string)
            if caller.1 < children.count { stack.append((caller.0, caller.1 + 1)); try enter(children[caller.1], session: session); return }
            current = caller.0
            let branches = session.json["playlist"][current]["next_item"].array.filter { $0["condition_variable_name"].string.isEmpty || (variables[$0["condition_variable_name"].string] ?? "") == $0["condition_variable_value"].string }
            if let next = WeightedChoice.choose(branches.map { ($0["playlist_item_name"].string, $0["random_weight"].number) }) { try enter(next, session: session); return }
        }
    }
}
