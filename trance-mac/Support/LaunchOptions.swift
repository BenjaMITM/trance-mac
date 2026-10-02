import Foundation

struct LaunchOptions {
    var session: URL?
    var system: URL?
    var visual: String?
    var pattern: URL?
    var variables: [String:String] = [:]
    var port: UInt16 = 0
    var muted = false
    var hidden = false
    var overlay = false
    var opacity = 0.35
    var mcp = false
    var lint = false
    var archive: URL?
    init(arguments: [String]) throws {
        var positional: [String] = []
        for arg in arguments {
            let pair = arg.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false).map(String.init)
            let value = pair.count > 1 ? pair[1] : ""
            switch pair[0] {
            case "--visual": visual = value
            case "--pattern": pattern = URL(fileURLWithPath:value)
            case "--variables": variables = try Self.parseVariables(value)
            case "--command_port": guard let p = UInt16(value) else { throw TranceError("Invalid command port") }; port = p
            case "--muted": muted = true
            case "--hidden": hidden = true
            case "--overlay": overlay = true
            case "--overlay_opacity": guard let v = Double(value),v.isFinite else { throw TranceError("Invalid overlay opacity") }; opacity = max(0,min(1,v))
            case "--mcp": mcp = true
            case "--lint": lint = true
            case "--export_archive": archive = URL(fileURLWithPath:value)
            default: if arg.hasPrefix("-") { throw TranceError("Unknown argument: \(arg)") }; positional.append(arg)
            }
        }
        guard visual == nil || pattern == nil else { throw TranceError("--visual and --pattern are mutually exclusive") }
        if !positional.isEmpty { session = URL(fileURLWithPath:positional[0]) }
        if positional.count > 1 { system = URL(fileURLWithPath:positional[1]) }
    }
    static func parseVariables(_ source: String) throws -> [String:String] {
        var result: [String:String] = [:]; var key = "",value = "",isValue = false,escaped = false
        func commit() throws { if key.isEmpty && value.isEmpty { return }; guard !key.isEmpty,isValue else { throw TranceError("Variables need name=value") }; result[key] = value }
        for c in source {
            if escaped { if isValue { value.append(c) } else { key.append(c) }; escaped = false }
            else if c == "\\" { escaped = true }
            else if c == ";" { try commit(); key = ""; value = ""; isValue = false }
            else if c == "=" && !isValue { isValue = true }
            else if isValue { value.append(c) } else { key.append(c) }
        }
        guard !escaped else { throw TranceError("Trailing variable escape") }; try commit(); return result
    }
}
