import Foundation
import Network
import AppKit

@MainActor final class CommandService {
    private weak var store: PlaybackStore?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label:"org.trance.mac.commands")
    init(store: PlaybackStore) { self.store = store }
    func start(port: UInt16) throws {
        guard port > 0 else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
        let listener = try NWListener(using:parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { Task { @MainActor in self?.store?.message = "Command listener: \(error.localizedDescription)" } }
        }
        listener.start(queue:queue); self.listener = listener
    }
    private func accept(_ connection: NWConnection) { connections.append(connection); connection.start(queue:queue); receive(connection,buffer:Data()) }
    private func receive(_ connection: NWConnection,buffer: Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] data,_,complete,error in
            Task { @MainActor in
                guard let self else { return }
                var pending = buffer; if let data { pending.append(data) }
                guard pending.count <= 1_048_576 else { connection.cancel(); return }
                while let newline = pending.firstIndex(of:10) {
                    let line = String(decoding:pending[..<newline],as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
                    pending.removeSubrange(...newline)
                    let reply = self.execute(line)+"\n"
                    connection.send(content:Data(reply.utf8),completion:.contentProcessed { _ in })
                }
                if complete || error != nil { connection.cancel(); self.connections.removeAll { $0 === connection } }
                else { self.receive(connection,buffer:pending) }
            }
        }
    }
    func startMCP() {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receiveMCP(data) }
        }
    }
    private var mcpBuffer = Data()
    private func receiveMCP(_ data: Data) {
        if data.isEmpty { NSApp.terminate(nil); return }
        mcpBuffer.append(data)
        guard mcpBuffer.count <= 1_048_576 else { mcpBuffer = Data(); return }
        while let newline = mcpBuffer.firstIndex(of:10) {
            let line = Data(mcpBuffer[..<newline]); mcpBuffer.removeSubrange(...newline)
            do {
                let request = try JSONDecoder().decode(JSONValue.self,from:line)
                if request["id"] == .null { continue }
                let result = try mcp(request)
                let response: JSONValue = .object(["jsonrpc":.string("2.0"),"id":request["id"],"result":result])
                // JSON-RPC transport must use one line per response.
                let encoded = try JSONEncoder().encode(response); try FileHandle.standardOutput.write(contentsOf:encoded+Data([10]))
            } catch { let response: JSONValue = .object(["jsonrpc":.string("2.0"),"id":.null,"error":.object(["code":.number(-32700),"message":.string(error.localizedDescription)])]); if let encoded = try? JSONEncoder().encode(response) { try? FileHandle.standardOutput.write(contentsOf:encoded+Data([10])) } }
        }
    }
    private func mcp(_ request: JSONValue) throws -> JSONValue {
        switch request["method"].string {
        case "initialize": return .object(["protocolVersion":.string("2024-11-05"),"capabilities":.object(["tools":.object([:])]),"serverInfo":.object(["name":.string("trance-mac"),"version":.string("0.1.0")])])
        case "ping": return .object([:])
        case "tools/list": return .object(["tools":.array([.object(["name":.string("trance_command"),"description":.string("Control the running trance session with the documented line protocol"),"inputSchema":.object(["type":.string("object"),"properties":.object(["command":.object(["type":.string("string")])]),"required":.array([.string("command")])])])])])
        case "tools/call":
            guard request["params"]["name"].string == "trance_command" else { throw TranceError("Unknown tool") }
            let reply = execute(request["params"]["arguments"]["command"].string)
            return .object(["content":.array([.object(["type":.string("text"),"text":.string(reply)])]),"isError":.bool(reply.hasPrefix("err"))])
        default: throw TranceError("Unknown JSON-RPC method")
        }
    }
    func execute(_ line: String) -> String {
        guard let store else { return "err player unavailable" }
        let split = line.split(separator:" ",maxSplits:1).map(String.init)
        let verb = split.first ?? "", rest = split.count > 1 ? split[1] : ""
        do {
            switch verb {
            case "pause": store.paused = true
            case "resume": store.paused = false
            case "hide": store.setHidden(true)
            case "show": store.setHidden(false)
            case "status": return "ok visual=\(store.visualName) bed=\(store.program["entrainment"]["layer"].array.isEmpty ? "off":"on") muted=\(store.muted ? "on":"off") overlay=\(store.overlay ? "on":"off") hidden=\(store.hidden ? "on":"off") xr=off themes=\(store.previousTheme)|\(store.primaryTheme)|\(store.secondaryTheme)|\(store.nextTheme) themepin=\(store.themePins.joined(separator:",")) text=\(store.textPins.isEmpty ? "theme":"pinned:\(store.textPins.count)")"
            case "mute": store.muted = try onOff(rest)
            case "ui": if try onOff(rest) { store.revealControls() } else { store.showControls = false }
            case "overlay":
                if rest.hasPrefix("opacity "), let opacity = Double(rest.dropFirst(8)), opacity.isFinite { store.opacity = max(0,min(1,opacity)) }
                else { store.overlay = try onOff(rest) }
            case "themes": return "ok "+store.themeNames.map { name in let row = store.program["enabled_theme"].array.first { $0["theme_name"].string == name }; return "\(name):\(Int(row?["random_weight"].number ?? 0))\(store.themePins.contains(name) ? "*":"")\([store.primaryTheme,store.secondaryTheme].contains(name) ? "+":"")" }.joined(separator:" ")
            case "theme":
                if rest == "unpin" { store.themePins = [] }
                else if rest.hasPrefix("pin ") { let names = rest.dropFirst(4).split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }; guard !names.isEmpty,names.allSatisfy(store.themeNames.contains) else { throw TranceError("Unknown theme") }; store.themePins = names }
                else { throw TranceError("Expected theme pin or unpin") }; store.chooseThemes()
            case "text":
                if rest == "unpin" { store.textPins = [] } else if rest.hasPrefix("pin ") { store.textPins = rest.dropFirst(4).split(separator:",").map(String.init) } else { throw TranceError("Expected text pin or unpin") }
            case "visuals": return "ok "+(BuiltinPatterns.sources.keys.sorted()+store.customVisuals.map { $0["name"].string }).joined(separator:",")+" forced=\(store.forcedVisual == nil ? "no":"yes")"
            case "visual": try store.forceSource(name:rest,source:store.source(rest)); store.forcedVisual = rest
            case "load":
                let source: String
                if rest.hasPrefix("pattern source ") { source = String(rest.dropFirst(15)).replacingOccurrences(of:"\\n",with:"\n") }
                else if rest.hasPrefix("pattern ") { source = try String(contentsOf:URL(fileURLWithPath:String(rest.dropFirst(8))),encoding:.utf8) }
                else { throw TranceError("Expected load pattern") }
                try store.forceSource(name:"runtime",source:source); store.forcedVisual = "runtime"
            case "unload": guard rest == "pattern" else { throw TranceError("Expected unload pattern") }; store.releaseVisual()
            case "bed": return try bed(rest,store:store)
            case "screenshot": try screenshot(rest)
            default: throw TranceError("Unknown verb: \(verb)")
            }
            return "ok"
        } catch { return "err "+error.localizedDescription.replacingOccurrences(of:"\n",with:" ") }
    }
    private func onOff(_ text: String) throws -> Bool { guard ["on","off"].contains(text) else { throw TranceError("Expected on or off") }; return text == "on" }
    private func bed(_ rest: String,store: PlaybackStore) throws -> String {
        var bed = store.program["entrainment"]; var layers = bed["layer"].array
        let args = rest.split(separator:" ").map(String.init)
        if rest == "off" { bed["layer"] = .array([]) }
        else if rest == "on" { if layers.isEmpty { layers = [.object(["center_hz":.number(312),"binaural_hz":.number(3),"pulse_hz":.number(5),"amplitude_db":.number(0)]),.object(["center_hz":.number(60),"binaural_hz":.number(3),"pulse_hz":.number(3.25),"amplitude_db":.number(-6)])]; bed["layer"] = .array(layers); bed["master_db"] = .number(-28) } }
        else if rest == "layers" { return "ok count=\(layers.count) master=\(bed["master_db"].number) "+layers.enumerated().map { "\($0.offset):carrier=\($0.element["center_hz"].number),binaural=\($0.element["binaural_hz"].number),pulse=\($0.element["pulse_hz"].number),level=\($0.element["amplitude_db"].number)" }.joined(separator:" ") }
        else if args.count == 2,args[0] == "master",let value = Double(args[1]),value.isFinite { guard !layers.isEmpty else { throw TranceError("No active bed") }; bed["master_db"] = .number(max(-60,min(-6,value))) }
        else if rest == "layer add" { layers.append(.object(["center_hz":.number(200),"binaural_hz":.number(3),"pulse_hz":.number(0),"amplitude_db":.number(-6)])); bed["layer"] = .array(layers) }
        else if args.count == 3,args[0] == "layer",args[1] == "remove",let index = Int(args[2]),layers.indices.contains(index) { layers.remove(at:index); bed["layer"] = .array(layers) }
        else if args.count == 4,args[0] == "layer",let index = Int(args[1]),layers.indices.contains(index),let value = Double(args[3]),value.isFinite {
            let fields: [String:(String,ClosedRange<Double>)] = ["carrier":("center_hz",20...1000),"binaural":("binaural_hz",0...40),"pulse":("pulse_hz",0...40),"level":("amplitude_db",-24...0)]
            guard let field = fields[args[2]] else { throw TranceError("Unknown layer field") }; layers[index][field.0] = .number(max(field.1.lowerBound,min(field.1.upperBound,value))); bed["layer"] = .array(layers)
        } else { throw TranceError("Invalid bed command") }
        store.updateProgram("entrainment",bed,save:false); return "ok count=\(bed["layer"].array.count)"
    }
    private func screenshot(_ path: String) throws {
        guard !path.isEmpty,let view = NSApp.windows.first(where:{$0.identifier?.rawValue == "player"})?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw TranceError("No desktop frame available") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw TranceError("PNG encoding failed") }; try data.write(to:URL(fileURLWithPath:path),options:.atomic)
    }
}
