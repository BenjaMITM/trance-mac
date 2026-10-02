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

@Test func themeRenamePreservesAllProgramReferences() throws {
    var json = minimal()
    json["theme_map"] = .object(["old": .object(["text_line": .array([.string("hello")])])])
    json["program_map"] = .object(["a": .object(["enabled_theme": .array([.object(["theme_name": .string("old"), "random_weight": .number(7), "pinned": .bool(true)])])]), "b": .object(["enabled_theme": .array([.object(["theme_name": .string("old"), "random_weight": .number(3)])])])])
    let session = try fixture(json)
    let updated = try LibraryAuthoring.theme(session: session, original: "old", name: "new", definition: session.json["theme_map"]["old"], program: "a", weight: 9, pinned: false)
    #expect(updated.json["theme_map"].object["old"] == nil)
    #expect(updated.json["program_map"]["a"]["enabled_theme"].array[0]["random_weight"].number == 9)
    #expect(updated.json["program_map"]["b"]["enabled_theme"].array[0]["theme_name"].string == "new")
    #expect(updated.json["program_map"]["b"]["enabled_theme"].array[0]["random_weight"].number == 3)
    #expect(updated.pools["new"]?.text == ["hello"])
    #expect(throws: TranceError.self) { try LibraryAuthoring.theme(session: session, original: nil, name: "bad", definition: .object(["image_path": .array([.string("missing.png")])]), program: "a", weight: 1, pinned: false) }
}

@Test func variableRenamePreservesConditionsAndRejectsUsedValueRemoval() throws {
    var json = minimal()
    json["variable_map"] = .object(["mood": .object(["value": .array([.string("calm"), .string("awake")]), "default_value": .string("calm")])])
    json["playlist"] = .object(["main": .object(["standard": .object(["program": .string("default")]), "next_item": .array([.object(["playlist_item_name": .string("main"), "random_weight": .number(1), "condition_variable_name": .string("mood"), "condition_variable_value": .string("awake")])])])])
    let session = try fixture(json)
    let updated = try LibraryAuthoring.variable(session: session, original: "mood", name: "state", description: "Session state", values: ["calm", "awake"], defaultValue: "awake")
    #expect(updated.json["variable_map"].object["mood"] == nil)
    #expect(updated.json["playlist"]["main"]["next_item"].array[0]["condition_variable_name"].string == "state")
    #expect(throws: TranceError.self) { try LibraryAuthoring.variable(session: session, original: "mood", name: "state", description: "", values: ["calm"], defaultValue: "calm") }
    #expect(throws: TranceError.self) { try LibraryAuthoring.variable(session: session, original: nil, name: "new", description: "", values: ["x", "x"], defaultValue: "x") }
}

@Test func systemSettingsValidateAndPreserveLegacyMetadata() throws {
    var json = SessionSchema.defaultSystem
    json["draw_depth"] = .number(12); json["eye_spacing"] = .number(-3)
    json["image_cache_size"] = .number(0)
    json["last_session_map"] = .object(["folder": .object(["state": .string("awake")])])
    json["last_export_settings"] = .object(["width": .number(1280), "fps": .number(30)])
    let checked = try SessionSchema.checkedSystem(json)
    #expect(checked["draw_depth"].number == 1)
    #expect(checked["eye_spacing"].number == -1)
    #expect(checked["image_cache_size"].number == 16)
    #expect(checked["last_session_map"] == json["last_session_map"])
    #expect(checked["last_export_settings"] == json["last_export_settings"])
    json["font_cache_size"] = .number(-1)
    #expect(throws: TranceError.self) { try SessionSchema.checkedSystem(json) }
    json = SessionSchema.defaultSystem; json["unknown"] = .bool(true)
    #expect(throws: TranceError.self) { try SessionSchema.checkedSystem(json) }
}

@Test func programRenamePreservesPlaybackTimingAndAllReferences() throws {
    var json = minimal()
    json["program_map"] = .object(["old": Session.defaultProgram])
    json["first_playlist_item"] = .string("a")
    json["playlist"] = .object(["a": .object(["standard": .object(["program": .string("old"), "play_time_seconds": .number(60)])]), "b": .object(["standard": .object(["program": .string("old")])])])
    let session = try fixture(json)
    var runner = PlaylistRunner(); _ = try runner.start(session: session)
    _ = try runner.advance(12, session: session)
    let updated = try LibraryAuthoring.program(session: session, original: "old", name: "new")
    runner.renameProgram(from: "old", to: "new")
    #expect(updated.programs == ["new"])
    #expect(updated.json["program_map"]["new"] == session.json["program_map"]["old"])
    #expect(updated.json["playlist"]["b"]["standard"]["program"].string == "new")
    #expect(runner.program == "new")
    #expect(runner.elapsed == 12)
    #expect(try runner.advance(1, session: updated).isEmpty)
    #expect(runner.current == "a")
    #expect(runner.elapsed == 13)
}

@Test func programCopyPreservesDefinitionWithoutRewritingPlaylist() throws {
    let session = try fixture(minimal())
    let copied = try LibraryAuthoring.program(session: session, name: "copy", copyFrom: "default")
    #expect(copied.json["program_map"]["copy"] == session.json["program_map"]["default"])
    #expect(copied.json["playlist"] == session.json["playlist"])
    #expect(throws: TranceError.self) { try LibraryAuthoring.program(session: copied, original: "default", name: "copy") }
    #expect(throws: TranceError.self) { try LibraryAuthoring.program(session: session, name: "new", copyFrom: "missing") }
    let fresh = try LibraryAuthoring.program(session: session, name: "fresh")
    #expect(fresh.json["program_map"]["fresh"]["entrainment"] == Session.defaultProgram["entrainment"])
}

@Test func malformedPinnedCustomVisualCannotBlockValidPlayback() throws {
    var program = Session.defaultProgram
    program["custom_visual_pattern"] = .array([.object(["name": .string("broken"), "enabled": .bool(true), "pinned": .bool(true), "random_weight": .number(1)])])
    let catalog = try VisualCatalog(program: program) { _ in "not a valid recipe" }
    #expect(catalog.warnings.count == 1)
    #expect(catalog.entries.count == 8)
    #expect(catalog.choose(unit: 0)?.name != "broken")
    program["visual_type"] = .array([])
    let fallback = try VisualCatalog(program: program) { _ in throw TranceError("unreadable") }
    #expect(fallback.choose(unit: 0)?.name == "parallel")
}

@Test func validVisualPinsExcludeUnpinnedRecipesAndDisabledFilesAreNotRead() throws {
    var program = Session.defaultProgram
    program["custom_visual_pattern"] = .array([
        .object(["name": .string("pin"), "enabled": .bool(true), "pinned": .bool(true), "random_weight": .number(0)]),
        .object(["name": .string("disabled"), "enabled": .bool(false)])])
    var reads = 0
    let catalog = try VisualCatalog(program: program) { row in
        reads += 1; #expect(row["name"].string == "pin")
        return BuiltinPatterns.sources["parallel"]!
    }
    #expect(reads == 1)
    #expect(catalog.choose(unit: 0)?.name == "pin")
    #expect(catalog.choose(unit: 0.999)?.name == "pin")
    #expect(catalog.warnings.isEmpty)
}
