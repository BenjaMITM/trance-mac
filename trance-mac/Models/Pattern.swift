import Foundation

public struct PatternClock: Sendable {
    public var frame: Double
    public var length: Double
    public var index: Double = 0
    public var active: Bool = true
    public var progress: Double { length > 0 ? frame / length : 0 }
    public init(frame: Double, length: Double, index: Double = 0, active: Bool = true) { self.frame = frame; self.length = length; self.index = index; self.active = active }
}
public indirect enum Expression: Sendable {
    case constant(Double), attribute(String, String), unary(String, Expression), binary(String, Expression, Expression), conditional(Expression, Expression, Expression), call(String, [Expression])
    public func evaluate(_ clocks: [String: PatternClock]) -> Double {
        switch self {
        case .constant(let v): return v
        case .attribute(let name, let field):
            guard let c = clocks[name] else { return 0 }
            switch field { case "progress": return c.progress; case "frame", "position": return c.frame; case "length": return c.length; case "index": return c.index; case "active": return c.active ? 1 : 0; default: return 0 }
        case .unary(let op, let a): let v = a.evaluate(clocks); return op == "-" ? -v : (v == 0 ? 1 : 0)
        case .binary(let op, let a, let b):
            let x = a.evaluate(clocks), y = b.evaluate(clocks)
            switch op {
            case "+": return x+y; case "-": return x-y; case "*": return x*y; case "/": return y == 0 ? 0 : x/y
            case "%": return y == 0 ? 0 : x.truncatingRemainder(dividingBy: y); case "^": return pow(x,y)
            case "==": return x == y ? 1 : 0; case "!=": return x != y ? 1 : 0; case "<": return x < y ? 1 : 0
            case ">": return x > y ? 1 : 0; case "<=": return x <= y ? 1 : 0; case ">=": return x >= y ? 1 : 0
            case "and", "&&": return x != 0 && y != 0 ? 1 : 0; case "or", "||": return x != 0 || y != 0 ? 1 : 0; default: return 0
            }
        case .conditional(let c, let a, let b): return c.evaluate(clocks) != 0 ? a.evaluate(clocks) : b.evaluate(clocks)
        case .call(let name, let args):
            let values = args.map { $0.evaluate(clocks) }
            switch name { case "abs": return abs(values.first ?? 0); case "min": return values.min() ?? 0; case "max": return values.max() ?? 0; default: return 0 }
        }
    }
}
public struct PatternEffect: Sendable {
    public var kind: String
    public var content = "runtime"
    public var register = "cur"
    public var destination = ""
    public var values: [String: Expression] = [:]
    public var gates: [Expression] = []
    public var animated = false
    public var animationEvery = 1
    public var chance: Double?
    public var alternateChance: Double?
    public var loop = false
    public init(kind: String) { self.kind = kind }
}
public enum ScheduleKind: Sendable { case pattern, cadence, ramp, burst, base, held, enter }
public struct PatternNode: Sendable {
    public var id: Int
    public var name: String
    public var kind: ScheduleKind
    public var length: Int
    public var loops = 1
    public var offset = 0
    public var sequential = false
    public var segments: [Int] = []
    public var chanceDenominator = 0
    public var cooldown = 0
    public var burstMinimum = 0
    public var burstMaximum = 0
    public var children: [PatternNode] = []
    public var effects: [PatternEffect] = []
    public init(id: Int, name: String, kind: ScheduleKind, length: Int) { self.id = id; self.name = name; self.kind = kind; self.length = length }
    public var span: Int { length * loops }
}

public struct PatternParser {
    private var tokens: [String]
    private var index = 0
    private var serial = 0
    private var beat: Int
    private var scopes: [String] = []
    public init(_ source: String, beat: Int = 0) throws {
        self.beat = beat
        let clean = source.components(separatedBy: .newlines).map { String($0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]) }.joined(separator: "\n")
        let regex = try NSRegularExpression(pattern: #"(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z_][A-Za-z_0-9]*|->|\.\.|<=|>=|==|!=|&&|\|\||[^\s]"#)
        let ns = clean as NSString
        tokens = regex.matches(in: clean, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
    public mutating func parse() throws -> PatternNode {
        let node = try schedule(parentLength: 0)
        guard index == tokens.count else { throw failure("Unexpected trailing token") }; return node
    }
    private var peek: String { index < tokens.count ? tokens[index] : "<end>" }
    private mutating func take() throws -> String { guard index < tokens.count else { throw failure("Unexpected end") }; defer { index += 1 }; return tokens[index] }
    private mutating func accept(_ token: String) -> Bool { if peek == token { index += 1; return true }; return false }
    private mutating func expect(_ token: String) throws { guard accept(token) else { throw failure("Expected \(token)") } }
    private func failure(_ text: String) -> TranceError { TranceError("Pattern token \(index + 1) (\(peek)): \(text)") }
    private mutating func number() throws -> Double {
        let sign = accept("-") ? -1.0 : 1.0
        guard let value = Double(try take()) else { throw failure("Expected number") }; return value * sign
    }
    private mutating func frames() throws -> Int {
        let value: Int
        if accept("locked") { value = beat }
        else if accept("beats") { value = Int(try number()) * beat }
        else { value = Int(try number()); try expect("f") }
        guard value > 0, value <= 10_000_000 else { throw failure("Length must be positive (beats require a pulsed bed)") }; return value
    }
    private mutating func schedule(parentLength: Int) throws -> PatternNode {
        let token = try take(); serial += 1
        var node = PatternNode(id: serial, name: "clock\(serial)", kind: .pattern, length: parentLength)
        switch token {
        case "pattern":
            node.name = try take(); try expect("for"); node.length = try frames()
            while peek != "{" { if accept("seq") { node.sequential = true } else if accept("loop") { node.loops = Int(try number()); guard node.loops > 0 else { throw failure("Loop must be positive") } } else { throw failure("Unknown pattern option") } }
        case "every":
            node.kind = .cadence
            if accept("ramp") {
                node.kind = .ramp
                let a = try number(); try expect("f"); try expect("->"); let b = try number(); try expect("f"); try expect("steps"); let count = Int(try number())
                guard a > 0, b > 0, count >= 2, count <= parentLength else { throw failure("Invalid ramp") }
                var ease = "linear"; if accept("ease") { ease = try take() }
                let raw = (0..<count).map { i -> Double in let p = Double(i)/Double(count-1); let q = ease == "early" ? 1-pow(1-p,3) : ease == "late" ? pow(p,3) : p; return a + (b-a)*q }
                let total = raw.reduce(0,+); var sum = 0
                node.segments = raw.enumerated().map { i, v in let end = Int((raw.prefix(i+1).reduce(0,+)/total * Double(parentLength)).rounded()); defer { sum = end }; return max(1, end-sum) }
                let delta = parentLength-node.segments.reduce(0,+); node.segments[count-1] += delta
                guard node.segments.allSatisfy({ $0 > 0 }) else { throw failure("Ramp segment rounded to zero") }
                node.length = parentLength
            } else { node.length = try frames() }
            while peek != "{" {
                if accept("->") { node.name = try take() }
                else if accept("offset") { node.offset = try frames() }
                else { throw failure("Unknown cadence option") }
            }
        case "burst":
            node.kind = .burst
            if accept("->") { node.name = try take() }
            var period = 0
            while peek != "{" {
                switch try take() {
                case "period": period = try frames()
                case "chance": try expect("1"); try expect("/"); node.chanceDenominator = Int(try number())
                case "cooldown": node.cooldown = try frames()
                case "duration": node.burstMinimum = try frames(); node.burstMaximum = accept("..") ? try frames() : node.burstMinimum
                default: throw failure("Unknown burst option")
                }
            }
            guard period > 0, node.chanceDenominator >= 0 else { throw failure("Invalid burst period/chance") }
            node.length = period
            if node.burstMinimum == 0 { node.burstMinimum = period; node.burstMaximum = period }
            guard node.burstMaximum >= node.burstMinimum else { throw failure("Invalid burst duration") }
        default: throw failure("Expected schedule")
        }
        scopes.append(node.name); try expect("{")
        while peek != "}" {
            if ["pattern","every"].contains(peek) { node.children.append(try schedule(parentLength: node.length)) }
            else if peek == "burst" && node.kind != .burst { node.children.append(try schedule(parentLength: node.length)) }
            else if node.kind == .burst && ["base","burst","enter"].contains(peek) {
                let branch = try take(); serial += 1
                var child = PatternNode(id: serial, name: branch, kind: branch == "base" ? .base : branch == "enter" ? .enter : .held, length: branch == "base" ? 0 : node.burstMaximum)
                if accept("->") { child.name = try take() }
                scopes.append(child.name); try expect("{")
                while peek != "}" {
                    if ["every","pattern","burst"].contains(peek) { guard branch != "enter" else { throw failure("Enter cannot contain schedules") }; child.children.append(try schedule(parentLength: child.length)) }
                    else { child.effects.append(try effect(clockLength: child.length)) }
                }
                try expect("}"); scopes.removeLast(); node.children.append(child)
            } else { node.effects.append(try effect(clockLength: node.length)) }
        }
        try expect("}"); scopes.removeLast(); return node
    }
    private mutating func register() throws -> String { var v = try take(); if accept(".") { v += "." + (try take()) }; return v }
    private mutating func effect(clockLength: Int) throws -> PatternEffect {
        var result = PatternEffect(kind: try take())
        let contentEffects = ["image","word","line","caption","subtext","anim","audio"]
        if contentEffects.contains(result.kind) {
            result.content = try take()
            guard ["primary","secondary","runtime","alternate","stop"].contains(result.content) else { throw failure("Unknown content lane") }
            if result.content == "alternate", accept("chance") { result.alternateChance = try number() }
            if accept("->") { result.register = try register() }
        } else if result.kind == "draw" { result.register = try register() }
        else if result.kind == "copy" { result.register = try register(); try expect("->"); result.destination = try register(); return result }
        else if result.kind == "look" {
            try expect("{"); try expect("spiral")
            while peek != "}" { let key = try take(); guard ["type","width"].contains(key) else { throw failure("Unknown spiral property") }; try expect("="); result.values[key] = .constant(try number()) }
            try expect("}"); return result
        } else if result.kind == "drunk" { result.values["amplitude"] = try mod(); return result }
        else if !["spiral","warp"].contains(result.kind) { throw failure("Unknown effect \(result.kind)") }
        while true {
            if ["zoom","origin","alpha","brightness","speed","amplitude","wavelength","volume"].contains(peek) {
                let key = try take(); result.values[key == "brightness" ? "alpha" : key] = try mod()
            } else if accept("chance") { let wrapped = accept("("); result.chance = try number(); if wrapped { try expect(")") } }
            else if accept("loop") { result.loop = true }
            else if accept("anim") {
                result.animated = true
                if accept("every") { result.animationEvery = Int(try number()); guard result.animationEvery > 0 else { throw failure("Animation count must be positive") }; if ["st","nd","rd","th"].contains(peek) { _ = try take() } }
            } else if accept("fade") {
                let kind = try take(); let p = Expression.attribute("this", "progress")
                switch kind { case "in": result.values["alpha"] = p; case "out": result.values["alpha"] = .binary("-", .constant(1),p); case "inout": result.values["alpha"] = .binary("-", .constant(1), .call("abs", [.binary("-", .binary("*", .constant(2),p), .constant(1))])); default: throw failure("Unknown fade") }
            } else if accept("show") {
                if accept("[") { result.gates.append(try expression()); try expect("]") }
                else {
                    let a = try number(), isFrame = accept("f"); try expect(".."); let b = try number(), secondFrame = accept("f")
                    guard isFrame == secondFrame, b > a else { throw failure("Invalid show window") }
                    let clock = Expression.attribute("this", isFrame ? "frame" : "progress")
                    result.gates.append(.binary("and", .binary(">=",clock,.constant(a)), .binary("<",clock,.constant(b))))
                }
            } else if accept("env") {
                try expect("in"); let rise = try envelopeLength(clockLength); var hold = 0.0
                if accept("hold") { hold = try envelopeLength(clockLength) }; try expect("out"); let fall = try envelopeLength(clockLength)
                guard rise > 0, fall > 0, rise+hold+fall <= 1.00001 else { throw failure("Envelope exceeds its clock") }
                let p = Expression.attribute("this","progress")
                result.values["alpha"] = .call("max", [.constant(0), .call("min", [.constant(1), .binary("/",p,.constant(rise)), .binary("/",.binary("-",.constant(rise+hold+fall),p),.constant(fall))])])
            } else { break }
        }
        return result
    }
    private mutating func envelopeLength(_ clock: Int) throws -> Double {
        let value = try number(); if accept("f") { guard clock > 0 else { throw failure("Frame envelope requires known duration") }; return value/Double(clock) }; return value
    }
    private mutating func mod() throws -> Expression {
        let wrapped = accept("("); let result: Expression
        if accept("[") { result = try expression(); try expect("]") }
        else if accept("curve") {
            let a = try number(); try expect("->"); let b = try number(); var ease = "linear"
            if accept("ease") { ease = try take() }; var clock = "this"
            if accept("over") { clock = try take(); guard scopes.contains(clock) else { throw failure("Curve clock is not an ancestor") } }
            let p = Expression.attribute(clock,"progress"); let q: Expression
            switch ease { case "early": q = .binary("-",.constant(1),.binary("^",.binary("-",.constant(1),p),.constant(3))); case "late": q = .binary("^",p,.constant(3)); case "linear": q = p; default: throw failure("Unknown ease") }
            result = .binary("+",.constant(a),.binary("*",.constant(b-a),q))
        } else { result = .constant(try number()) }
        if wrapped { try expect(")") }; return result
    }
    private mutating func expression(minimum: Int = 0) throws -> Expression {
        var left: Expression
        if ["-","!"].contains(peek) { let op = try take(); left = .unary(op,try expression(minimum: 8)) }
        else if accept("(") { left = try expression(); try expect(")") }
        else if Double(peek) != nil { left = .constant(try number()) }
        else {
            let name = try take()
            if accept("(") { var args = [try expression()]; while accept(",") { args.append(try expression()) }; try expect(")"); left = .call(name,args) }
            else if accept(".") { left = .attribute(name,try take()) }
            else { left = .constant(0) }
        }
        let precedence = ["or":1,"||":1,"and":2,"&&":2,"==":3,"!=":3,"<":3,">":3,"<=":3,">=":3,"+":4,"-":4,"*":5,"/":5,"%":5,"^":6]
        while let p = precedence[peek], p >= minimum { let op = try take(); let right = try expression(minimum: p + (op == "^" ? 0 : 1)); left = .binary(op,left,right) }
        if minimum == 0, accept("?") { let a = try expression(); try expect(":"); left = .conditional(left,a,try expression()) }
        return left
    }
}
