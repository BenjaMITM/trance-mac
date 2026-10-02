import Foundation

public enum SessionLint {
    public static func validate(_ session: Session) throws -> Int {
        var count = 0
        for program in session.json["program_map"].object.values {
            let sources = Array(BuiltinPatterns.sources.values) + (try program["custom_visual_pattern"].array.map { try String(contentsOf:session.resolve($0["file"].string),encoding:.utf8) })
            for source in sources {
                let node = try PatternAuthoring.validate(source:source,program:program)
                var runtime = PatternRuntime(root:node)
                for _ in 0..<min(node.span,4096) {
                    for draw in runtime.advance() {
                        guard draw.effect.values.values.allSatisfy({ $0.evaluate(draw.clocks).isFinite }) else { throw TranceError("Pattern expression produced a nonfinite value") }
                    }
                }
                count += 1
            }
        }
        return count
    }
}
