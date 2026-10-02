import Foundation

/// Mirrors the source player's stack machine. Elapsed time resets at each handoff;
/// exhausted subroutines remain exhausted when held at the top level.
public struct PlaylistRunner: Sendable {
    private struct Entry: Sendable { var name: String; var step = 0 }
    public var current: String { stack.last?.name ?? "" }
    public private(set) var elapsed: Double = 0
    public private(set) var program = ""
    public private(set) var warnings: [String] = []
    private var stack: [Entry] = []
    private var pending: [JSONValue] = []
    public var variables: [String: String] = [:]
    public init() {}
    public mutating func start(session: Session) throws -> [JSONValue] {
        elapsed = 0; program = ""; warnings = []; pending = []
        stack = [Entry(name: session.json["first_playlist_item"].string)]
        try entered(session: session)
        return drainEvents()
    }
    /// A library rename changes identity without restarting clocks or replaying cues.
    public mutating func renameProgram(from original: String, to name: String) {
        if program == original { program = name }
    }
    private mutating func entered(session: Session) throws {
        guard let item = session.json["playlist"].object[current] else { throw TranceError("Missing playlist item: \(current)") }
        pending += item["audio_event"].array
        if item.object["standard"] != nil { program = item["standard"]["program"].string }
    }
    public mutating func advance(_ seconds: Double, session: Session) throws -> [JSONValue] {
        guard seconds.isFinite, seconds >= 0 else { throw TranceError("Playlist elapsed time must be finite and nonnegative") }
        guard !stack.isEmpty else { throw TranceError("Playlist has not started") }
        elapsed += seconds
        for _ in 0..<1024 {
            let item = session.json["playlist"][current]
            if item.object["standard"] != nil, elapsed < item["standard"]["play_time_seconds"].number { return drainEvents() }
            if item.object["subroutine"] != nil {
                let children = item["subroutine"].array.map(\.string)
                let step = stack[stack.count - 1].step
                if step < children.count {
                    if stack.count >= 256 {
                        warnings.append("Playlist subroutine stack limit reached at \(current)")
                        stack[stack.count - 1].step = children.count
                    } else {
                        stack[stack.count - 1].step += 1
                        stack.append(Entry(name: children[step])); elapsed = 0
                        try entered(session: session); continue
                    }
                }
            }
            let branches = item["next_item"].array.filter {
                let variable = $0["condition_variable_name"].string
                return variable.isEmpty || (variables[variable] ?? "") == $0["condition_variable_value"].string
            }
            if let next = WeightedChoice.choose(branches.map { ($0["playlist_item_name"].string, $0["random_weight"].number) }) {
                stack[stack.count - 1] = Entry(name: next); elapsed = 0
                try entered(session: session)
            } else if stack.count > 1 {
                stack.removeLast()
            } else {
                return drainEvents()
            }
        }
        throw TranceError("Playlist exceeded 1024 immediate transitions; give cyclic items positive durations")
    }
    private mutating func drainEvents() -> [JSONValue] { let events = pending; pending = []; return events }
}
