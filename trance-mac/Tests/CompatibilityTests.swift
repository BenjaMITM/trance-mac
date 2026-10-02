import Foundation
import Testing
@testable import TranceCore

private func minimal() -> JSONValue {
    .object(["format":.string("trance-session"),"format_version":.number(1),"theme_scan_root":.object(["dir":.string("."),"auto_rescan":.bool(false)])])
}
private func fixture(_ json: JSONValue) throws -> Session {
    try Session(json:json,url:URL(fileURLWithPath:"/private/tmp/trance-no-assets-compat/session.json"))
}
@Test func malformedSessionFieldsAreRejected() throws {
    let cases: [(String,JSONValue)] = [
        ("unexpected",.string("value")),("format_version",.string("1")),("program_map",.array([])),
        ("theme_map",.null),("first_playlist_item",.number(4))]
    for (key,value) in cases { var json = minimal(); json[key] = value; #expect(throws:TranceError.self) { try fixture(json) } }
    for fps in [-1.0,1.5,Double(UInt32.max)+1] {
        var json = minimal(); json["program_map"] = .object(["p":.object(["global_fps":.number(fps)])])
        #expect(throws:TranceError.self) { try fixture(json) }
    }
    var color = minimal(); color["program_map"] = .object(["p":.object(["main_text_colour":.string("white")])])
    #expect(throws:TranceError.self) { try fixture(color) }
}
@Test func commentsAreIgnoredInNamedMapsAndNestedFields() throws {
    var json = minimal(); json["_comment"] = .string("hello")
    json["program_map"] = .object(["_notes":.string("not a program"),"p":.object(["_note":.string("comment"),"global_fps":.number(60)])])
    let session = try fixture(json)
    #expect(session.programs == ["p"])
    #expect(session.json.object["_comment"] == nil)
    #expect(session.json["program_map"]["p"].object["_note"] == nil)
}
@Test func emptyMapsAndMissingReferencesAreRepaired() throws {
    let empty = try fixture(minimal())
    #expect(empty.programs == ["default"])
    #expect(empty.json["first_playlist_item"].string == "default")
    var json = minimal()
    json["first_playlist_item"] = .string("missing")
    json["playlist"] = .object(["a":.object(["standard":.object(["program":.string("recovered")]),"next_item":.array([.object(["playlist_item_name":.string("missing"),"random_weight":.number(1)])])])])
    let session = try fixture(json)
    #expect(session.programs.contains("recovered"))
    #expect(session.json["playlist"]["a"]["next_item"].array.isEmpty)
    #expect(session.json["first_playlist_item"].string == "a")
}
@Test func sourceVariableAndVisualFallbackRules() throws {
    var json = minimal()
    json["variable_map"] = .object(["mood":.object([:])])
    json["program_map"] = .object(["p":.object(["global_fps":.number(400),"zoom_intensity":.number(2),"visual_type":.array([])])])
    let session = try fixture(json)
    #expect(session.json["variable_map"]["mood"]["default_value"].string == "Default")
    #expect(session.json["program_map"]["p"]["global_fps"].number == 240)
    #expect(session.json["program_map"]["p"]["zoom_intensity"].number == 1)
    #expect(session.json["program_map"]["p"]["visual_type"].array.count == 8)
    #expect(session.json["program_map"]["p"]["main_text_colour"].string == "#00000000")
}
@Test func conditionFieldsMustAppearTogether() throws {
    var json = minimal()
    json["playlist"] = .object(["a":.object(["standard":.object([:]),"next_item":.array([.object(["playlist_item_name":.string("a"),"random_weight":.number(1),"condition_variable_name":.string("mood")])])])])
    #expect(throws:TranceError.self) { try fixture(json) }
}
@Test func exhaustedSubroutineNeverRestarts() throws {
    var session = try fixture(minimal())
    session.json["first_playlist_item"] = .string("S")
    session.json["playlist"] = .object([
        "S":.object(["subroutine":.array([.string("C"),.string("C")])]),
        "C":.object(["standard":.object(["program":.string("default"),"play_time_seconds":.number(1)]),"audio_event":.array([.object(["type":.string("stop"),"channel":.number(0)])])])])
    var runner = PlaylistRunner(); _ = try runner.start(session:session)
    #expect(try runner.advance(0,session:session).count == 1)
    #expect(try runner.advance(1,session:session).count == 1)
    #expect(try runner.advance(1,session:session).isEmpty)
    #expect(runner.current == "S")
    #expect(try runner.advance(60,session:session).isEmpty)
    #expect(runner.current == "S")
}
@Test func sourceHandoffResetsClockRatherThanCarryingOverflow() throws {
    var session = try fixture(minimal())
    session.json["first_playlist_item"] = .string("a")
    session.json["playlist"] = .object([
        "a":.object(["standard":.object(["program":.string("default"),"play_time_seconds":.number(1)]),"next_item":.array([.object(["playlist_item_name":.string("b"),"random_weight":.number(1)])])]),
        "b":.object(["standard":.object(["program":.string("default"),"play_time_seconds":.number(1)])])])
    var runner = PlaylistRunner(); _ = try runner.start(session:session); _ = try runner.advance(20,session:session)
    #expect(runner.current == "b"); #expect(runner.elapsed == 0)
}
@Test func recursiveSubroutineIsBoundedAndHolds() throws {
    var session = try fixture(minimal()); session.json["first_playlist_item"] = .string("R")
    session.json["playlist"] = .object(["R":.object(["subroutine":.array([.string("R")])])])
    var runner = PlaylistRunner(); _ = try runner.start(session:session); _ = try runner.advance(0,session:session)
    #expect(runner.current == "R"); #expect(!runner.warnings.isEmpty)
    _ = try runner.advance(60,session:session); #expect(runner.current == "R")
}
@Test func immediateCycleProducesActionableError() throws {
    var session = try fixture(minimal()); session.json["first_playlist_item"] = .string("a")
    session.json["playlist"] = .object(["a":.object(["standard":.object(["program":.string("default")]),"next_item":.array([.object(["playlist_item_name":.string("a"),"random_weight":.number(1)])])])])
    var runner = PlaylistRunner(); _ = try runner.start(session:session)
    #expect(throws:TranceError.self) { try runner.advance(0,session:session) }
}
@Test func scannedPhrasesSplitAtNearestMiddleSpace() {
    #expect(Session.scannedText("one two three") == "ONE TWO\nTHREE")
    #expect(Session.scannedText("word") == "WORD")
    #expect(Session.scannedText("") == "")
}

@Test func patternAuthoringSavesAndReservesCollisionFreePaths() throws {
    let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let session = try Session.new(at:root.appendingPathComponent("session.json"))
    let source = try #require(BuiltinPatterns.sources["parallel"])
    let saved = try PatternAuthoring.save(session:session,programName:"default",originalName:nil,name:"My Pattern",source:source,weight:3,enabled:true,pinned:true)
    let first = try #require(saved.json["program_map"]["default"]["custom_visual_pattern"].array.first)
    #expect(first["file"].string == "patterns/my_pattern.pattern")
    #expect(try String(contentsOf:saved.resolve(first["file"].string),encoding:.utf8) == source)
    #expect(throws:TranceError.self) { try PatternAuthoring.save(session:saved,programName:"default",originalName:nil,name:"My Pattern",source:source,weight:1,enabled:true,pinned:false) }
    let second = try PatternAuthoring.save(session:saved,programName:"default",originalName:nil,name:"My.Pattern",source:source,weight:2,enabled:false,pinned:true)
    #expect(second.json["program_map"]["default"]["custom_visual_pattern"].array.last?["file"].string == "patterns/my_pattern-2.pattern")
    #expect(second.json["program_map"]["default"]["custom_visual_pattern"].array.last?["pinned"].bool == false)
    let edited = try PatternAuthoring.save(session:second,programName:"default",originalName:"My Pattern",name:"Renamed",source:source,weight:4,enabled:true,pinned:false)
    #expect(edited.json["program_map"]["default"]["custom_visual_pattern"].array.count == 2)
    #expect(edited.json["program_map"]["default"]["custom_visual_pattern"].array.first?["file"].string == first["file"].string)
    _ = try Session.load(session.url)
}
@Test func invalidPatternDoesNotWriteSessionOrAsset() throws {
    let root = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let session = try Session.new(at:root.appendingPathComponent("session.json")); try session.save()
    let before = try Data(contentsOf:session.url)
    #expect(throws:TranceError.self) { try PatternAuthoring.save(session:session,programName:"default",originalName:nil,name:"Bad",source:"pattern bad for 0f {}",weight:1,enabled:true,pinned:false) }
    #expect(try Data(contentsOf:session.url) == before)
    #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("patterns/bad.pattern").path))
}

@Test func namedAncestorRegistersResolveToTheirOwningPattern() throws {
    var parser = try PatternParser("pattern Scene for 8f { image primary -> saved pattern Child for 4f { draw Scene.saved image secondary -> saved } }")
    var runtime = PatternRuntime(root:try parser.parse())
    let draws = runtime.advance()
    let outer = try #require(draws.first { $0.effect.kind == "image" && $0.scope == $0.registerScopes["Scene"] })
    let ancestor = try #require(draws.first { $0.effect.kind == "draw" })
    let inner = try #require(draws.last { $0.effect.kind == "image" })
    #expect(outer.registerKey("saved") == ancestor.registerKey("Scene.saved"))
    #expect(inner.registerKey("saved") != outer.registerKey("saved"))
}
@Test func sampledRampSegmentsHaveDistinctRegisterScopes() throws {
    var parser = try PatternParser("pattern Scene for 8f { every ramp 4f -> 4f steps 2 { image primary } }")
    var runtime = PatternRuntime(root:try parser.parse())
    let first = try #require(runtime.advance().first)
    for _ in 0..<3 { _ = runtime.advance() }
    let second = try #require(runtime.advance().first)
    #expect(first.scope != second.scope)
    #expect(first.registerKey("cur") != second.registerKey("cur"))
}
@Test func explicitThemeWeightsAreNotExpandedWhenDiscoveryIsDisabled() throws {
    var json = minimal()
    json["theme_map"] = .object(["a":.object([:]),"b":.object([:])])
    json["program_map"] = .object(["p":.object(["enabled_theme":.array([.object(["theme_name":.string("a"),"random_weight":.number(2)])])])])
    let session = try fixture(json)
    #expect(session.json["program_map"]["p"]["enabled_theme"].array.count == 1)
}

@Test func playlistRenameUpdatesBranchesChildrenAndEntryPoint() throws {
    var session = try fixture(minimal())
    session.json["first_playlist_item"] = .string("old")
    session.json["playlist"] = .object([
        "old":.object(["standard":.object(["program":.string("default")]),"next_item":.array([.object(["playlist_item_name":.string("old"),"random_weight":.number(1)])])]),
        "caller":.object(["subroutine":.array([.string("old"),.string("old")])])])
    let updated = try PlaylistAuthoring.save(session:session,originalName:"old",name:"new",item:session.json["playlist"]["old"],first:false)
    #expect(updated.json["playlist"].object["old"] == nil)
    #expect(updated.json["first_playlist_item"].string == "new")
    #expect(updated.json["playlist"]["new"]["next_item"].array.first?["playlist_item_name"].string == "new")
    #expect(updated.json["playlist"]["caller"]["subroutine"].array == [.string("new"),.string("new")])
}
@Test func playlistEditorRejectsMissingReferencesBeforeRepair() throws {
    let session = try fixture(minimal())
    let invalid: JSONValue = .object(["standard":.object(["program":.string("missing")])])
    #expect(throws:TranceError.self) { try PlaylistAuthoring.save(session:session,originalName:nil,name:"new",item:invalid,first:false) }
    let missingChild: JSONValue = .object(["subroutine":.array([.string("missing")])])
    #expect(throws:TranceError.self) { try PlaylistAuthoring.save(session:session,originalName:nil,name:"new",item:missingChild,first:false) }
    #expect(session.json["playlist"].object["new"] == nil)
}

@Test func originalRepositorySessionFixtureLoadsAndLints() throws {
    let workspace = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let input = workspace.appendingPathComponent("trance-original-windows-dotnet/tests/fixtures/xr-baseline/session-used-default.json")
    let before = try Data(contentsOf:input)
    let session = try Session.load(input)
    #expect(session.json["first_playlist_item"].string == "default")
    #expect(try SessionLint.validate(session) >= 8)
    #expect(try Data(contentsOf:input) == before)
}
