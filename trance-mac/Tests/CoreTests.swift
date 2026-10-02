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

@Test func archiveRoundTripWithSystemZip() throws {
    let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let session = try Session.new(at:root.appendingPathComponent("session.json"))
    let archive = root.appendingPathComponent("portable.trance")
    try ArchiveExporter.export(session,to:archive)
    let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/unzip"); process.arguments = ["-t",archive.path]; process.standardOutput = FileHandle.nullDevice
    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    let extract = root.appendingPathComponent("extracted")
    let unzip = Process(); unzip.executableURL = URL(fileURLWithPath:"/usr/bin/unzip"); unzip.arguments = ["-q",archive.path,"-d",extract.path]
    try unzip.run(); unzip.waitUntilExit(); #expect(unzip.terminationStatus == 0)
    let restored = try Session.load(extract.appendingPathComponent("session.json"))
    #expect(restored.json["first_playlist_item"].string == "main")
}
@Test func legacySessionKeepsOriginal() throws {
    let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let input = root.appendingPathComponent("old.session")
    let text = """
    first_playlist_item: "main"
    program_map { key: "default" value { global_fps: 60 visual_type { type: PARALLEL random_weight: 1 } } }
    playlist { key: "main" value { program: "default" play_time_seconds: 0 } }
    """
    try text.write(to:input,atomically:true,encoding:.utf8)
    let migrated = try LegacyImporter.importSession(input)
    #expect(migrated.json["program_map"]["default"]["visual_type"].array.first?["type"].string == "parallel")
    #expect(try String(contentsOf:input,encoding:.utf8) == text)
    #expect(FileManager.default.fileExists(atPath:root.appendingPathComponent("old.json").path))
}
@Test func subroutineReturnsToNextChild() throws {
    var session = try Session.new(at:URL(fileURLWithPath:"/private/tmp/no-media/session.json"))
    session.json["playlist"] = .object([
        "main":.object(["subroutine":.array([.string("one"),.string("two")])]),
        "one":.object(["standard":.object(["program":.string("default"),"play_time_seconds":.number(1)])]),
        "two":.object(["standard":.object(["program":.string("default"),"play_time_seconds":.number(1)])])])
    var runner = PlaylistRunner(); _ = try runner.start(session:session)
    _ = try runner.advance(0,session:session); #expect(runner.current == "one")
    _ = try runner.advance(1,session:session); #expect(runner.current == "two")
}
