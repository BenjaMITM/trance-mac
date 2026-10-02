import Testing
import Foundation
@testable import TranceCore

@Test func allBuiltinPatternsParseAndRun() throws {
    for (name, source) in BuiltinPatterns.sources {
        var parser = try PatternParser(source)
        let node = try parser.parse()
        #expect(node.length > 0, "\(name)")
        var runtime = PatternRuntime(root: node)
        for _ in 0..<4096 {
            for draw in runtime.advance() {
                #expect(draw.value("zoom").isFinite)
                #expect(draw.value("alpha", default: 1).isFinite)
            }
        }
    }
}
@Test func weightedTickets() {
    #expect(WeightedChoice.choose([("a",1),("b",3)], unit: 0.24) == "a")
    #expect(WeightedChoice.choose([("a",1),("b",3)], unit: 0.25) == "b")
    #expect(WeightedChoice.choose([("a",0)]) == nil)
}
@Test func cadenceEntriesAndNamedClocks() throws {
    var parser = try PatternParser("pattern scene for 8f { every 4f { image primary zoom (curve 0 -> 1) alpha (curve 0 -> 1 over scene) } }")
    var runtime = PatternRuntime(root: try parser.parse())
    for i in 0..<8 {
        let draw = try #require(runtime.advance().first)
        #expect(draw.entry == (i % 4 == 0))
        #expect(draw.value("zoom") == Double(i%4)/4)
        #expect(draw.value("alpha") == Double(i)/8)
    }
}
@Test func sessionPreservesFieldsAndRejectsTraversal() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathComponent("session.json")
    var session = try Session.new(at: url)
    session.json["variable_map"] = .object(["mood": .object(["value": .array([.string("calm")]), "default_value": .string("calm")])])
    #expect(throws: TranceError.self) { try session.resolve("../outside") }
    #expect(throws: TranceError.self) { try session.resolve("C:\\outside") }
    let restored = try JSONDecoder().decode(JSONValue.self,from: session.json.encoded())
    #expect(restored["variable_map"]["mood"]["default_value"].string == "calm")
}
@Test func playlistConditionalAndPauseClock() throws {
    var session = try Session.new(at: URL(fileURLWithPath:"/private/tmp/trance-tests/session.json"))
    session.json["playlist"]["main"] = .object(["standard": .object(["program": .string("default"),"play_time_seconds": .number(2)]),"next_item": .array([.object(["playlist_item_name": .string("hold"),"random_weight": .number(1),"condition_variable_name": .string("mode"),"condition_variable_value": .string("go")])])])
    session.json["playlist"]["hold"] = .object(["standard": .object(["program": .string("default")])])
    var runner = PlaylistRunner(); runner.variables["mode"] = "go"; _ = try runner.start(session: session)
    _ = try runner.advance(1,session: session); #expect(runner.current == "main")
    _ = try runner.advance(1,session: session); #expect(runner.current == "hold")
}
