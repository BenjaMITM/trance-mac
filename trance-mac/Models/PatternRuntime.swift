import Foundation

public struct PatternDraw: Sendable {
    public var effect: PatternEffect
    public var key: String
    public var scope: String
    public var entry: Bool
    public var clocks: [String: PatternClock]
    public var registerScopes: [String:String]
    public func value(_ name: String, default fallback: Double = 0) -> Double { effect.values[name]?.evaluate(clocks) ?? fallback }
    public func registerKey(_ name: String) -> String {
        let pieces = name.split(separator:".",maxSplits:1).map(String.init)
        if pieces.count == 2 { return (registerScopes[pieces[0]] ?? scope)+":"+pieces[1] }
        return scope+":"+name
    }
    public var visible: Bool { effect.gates.allSatisfy { $0.evaluate(clocks) != 0 } }
}
public struct PatternRuntime: Sendable {
    public let root: PatternNode
    public private(set) var frame = -1
    private var entries: [String: Int] = [:]
    private var burstState: [String: BurstState] = [:]
    public private(set) var diagnostics: [String] = []
    private struct BurstState: Sendable { var held = false; var start = 0; var length = 0; var ready = 0; var lastParentFrame = -1 }
    public init(root: PatternNode) { self.root = root }
    public mutating func advance() -> [PatternDraw] {
        frame += 1; var output: [PatternDraw] = []; diagnostics = []
        visit(root, parentFrame: frame, parentClocks: [:], scope: "", path: "", output: &output)
        return output
    }
    private mutating func visit(_ node: PatternNode, parentFrame: Int, parentClocks: [String: PatternClock], scope: String, path: String, output: inout [PatternDraw], forcedLength: Int? = nil, registerScopes: [String:String] = [:]) {
        let identity = path + "/\(node.id)"
        var local = parentFrame; var length = forcedLength ?? node.length; var occurrence = 0; var index = 0
        switch node.kind {
        case .pattern: occurrence = parentFrame / max(1,node.length); local = parentFrame % max(1,node.length)
        case .cadence: let shifted = parentFrame-node.offset; occurrence = Int(floor(Double(shifted)/Double(max(1,node.length)))); local = ((shifted % max(1,node.length))+max(1,node.length)) % max(1,node.length)
        case .ramp:
            var remainder = parentFrame % max(1,node.length)
            for (i, segment) in node.segments.enumerated() { if remainder < segment { local = remainder; length = segment; index = i; break }; remainder -= segment }
            occurrence = (parentFrame / max(1,node.length))*max(1,node.segments.count)+index
        case .burst:
            var state = burstState[identity] ?? BurstState()
            if parentFrame < state.lastParentFrame { state = BurstState() }
            state.lastParentFrame = parentFrame
            if state.held, parentFrame-state.start >= state.length { state.held = false; state.start = parentFrame; state.ready = parentFrame + ((node.cooldown+node.length-1)/node.length)*node.length; state.ready = max(state.ready,parentFrame+node.length) }
            if !state.held, parentFrame >= state.ready, parentFrame % node.length == 0, node.chanceDenominator > 0, Int.random(in: 0..<node.chanceDenominator) == 0 {
                state.held = true; state.start = parentFrame
                let low = (node.burstMinimum+node.length-1)/node.length, high = (node.burstMaximum+node.length-1)/node.length
                state.length = Int.random(in: low...max(low,high))*node.length
            }
            burstState[identity] = state
            var clocks = parentClocks
            let outer = parentClocks["this"] ?? PatternClock(frame: Double(parentFrame),length: Double(length))
            clocks[node.name] = PatternClock(frame: Double(parentFrame),length: outer.length,index: state.held ? 1 : 0)
            for child in node.children where state.held ? [.held,.enter].contains(child.kind) : child.kind == .base {
                if child.kind == .enter && parentFrame != state.start { continue }
                visit(child,parentFrame: parentFrame-state.start,parentClocks: clocks,scope: scope,path: identity,output: &output,forcedLength: state.held ? state.length : 0,registerScopes:registerScopes)
            }
            return
        case .base,.held,.enter: local = parentFrame; occurrence = 0
        }
        let actualScope = node.kind == .pattern ? identity : node.kind == .ramp ? identity+"/segment\(index)" : scope
        var scopes = registerScopes
        if node.kind == .pattern || node.kind == .ramp { scopes[node.name] = actualScope }
        var clocks = parentClocks
        let clock = PatternClock(frame: Double(local),length: Double(length),index: Double(index))
        clocks[node.name] = clock; clocks["this"] = clock; clocks["self"] = clock
        let previous = entries[identity]; let isEntry = previous == nil || previous != occurrence || local == 0
        entries[identity] = occurrence
        if diagnostics.count < 8 { diagnostics.append("\(node.name): \(local)/\(length)f") }
        for (i,effect) in node.effects.enumerated() {
            output.append(PatternDraw(effect: effect,key: identity+"/e\(i)",scope: actualScope,entry: isEntry,clocks: clocks,registerScopes:scopes))
        }
        if node.sequential {
            let total = node.children.reduce(0) { $0 + max(1,$1.span) }
            var position = local % max(1,total)
            for child in node.children {
                if position < child.span { visit(child,parentFrame: position,parentClocks: clocks,scope: actualScope,path: identity,output: &output,registerScopes:scopes); break }
                position -= child.span
            }
        } else {
            for child in node.children { visit(child,parentFrame: local,parentClocks: clocks,scope: actualScope,path: identity,output: &output,registerScopes:scopes) }
        }
    }
}
