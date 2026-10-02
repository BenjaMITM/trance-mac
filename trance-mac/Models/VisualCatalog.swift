import Foundation

/// Compiles one program's lottery. Invalid custom recipes are reported and excluded,
/// including their pins, so they cannot interrupt otherwise valid playback.
public struct VisualCatalog: Sendable {
    public struct Entry: Sendable {
        public let name: String
        public let node: PatternNode
        public let weight: Double
        public let pinned: Bool
    }
    public let entries: [Entry]
    public let warnings: [String]
    public init(program: JSONValue, loadCustom: (JSONValue) throws -> String) throws {
        var entries: [Entry] = []; var warnings: [String] = []
        for row in program["visual_type"].array {
            let name = row["type"].string
            guard let source = BuiltinPatterns.sources[name] else { continue }
            entries.append(Entry(name: name, node: try PatternAuthoring.validate(source: source, program: program), weight: row["random_weight"].number, pinned: row["pinned"].bool))
        }
        for row in program["custom_visual_pattern"].array where row["enabled"].bool {
            do {
                let node = try PatternAuthoring.validate(source: loadCustom(row), program: program)
                entries.append(Entry(name: row["name"].string, node: node, weight: row["random_weight"].number, pinned: row["pinned"].bool))
            } catch { warnings.append("Skipping custom pattern '\(row["name"].string)': \(error.localizedDescription)") }
        }
        if !entries.contains(where: { $0.weight > 0 || $0.pinned }) {
            entries.append(Entry(name: "parallel", node: try PatternAuthoring.validate(source: BuiltinPatterns.sources["parallel"]!, program: program), weight: 1, pinned: false))
        }
        self.entries = entries; self.warnings = warnings
    }
    public func choose(unit: Double = Double.random(in: 0..<1)) -> Entry? {
        let pinned = entries.contains { $0.pinned }
        let choices = entries.indices.filter { !pinned || entries[$0].pinned }.map {
            ($0, entries[$0].pinned ? max(1, entries[$0].weight) : entries[$0].weight)
        }
        guard let index = WeightedChoice.choose(choices, unit: unit) else { return nil }
        return entries[index]
    }
}
