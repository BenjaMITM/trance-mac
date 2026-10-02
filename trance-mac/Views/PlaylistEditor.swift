import SwiftUI

private struct BranchDraft: Identifiable {
    let id = UUID()
    var destination: String
    var weight = 1
    var variable = ""
    var value = ""
    var json: JSONValue {
        var fields: [String:JSONValue] = ["playlist_item_name":.string(destination),"random_weight":.number(Double(weight))]
        if !variable.isEmpty { fields["condition_variable_name"] = .string(variable); fields["condition_variable_value"] = .string(value) }
        return .object(fields)
    }
}
private struct CueDraft: Identifiable {
    let id = UUID()
    var type = "play"
    var channel = 0
    var unused = false
    var path = ""
    var loop = false
    var volume = 100
    var seconds = 0
    var json: JSONValue { .object(["type":.string(type),"channel":.number(Double(channel)),"next_unused_channel":.bool(unused),"path":.string(path),"loop":.bool(loop),"volume":.number(Double(volume)),"time_seconds":.number(Double(seconds))]) }
}
private struct StepDraft: Identifiable { let id = UUID(); var name: String }

struct PlaylistEditor: View {
    let store: PlaybackStore
    @State private var selection = ""
    @State private var name = ""
    @State private var program = ""
    @State private var seconds = 0
    @State private var subroutine = false
    @State private var first = false
    @State private var steps: [StepDraft] = []
    @State private var branches: [BranchDraft] = []
    @State private var cues: [CueDraft] = []
    @State private var status = ""
    private var names: [String] { store.session?.json["playlist"].object.keys.sorted() ?? [] }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("Item",selection:$selection) {
                Text("New item").tag("")
                ForEach(names,id:\.self) { Text($0).tag($0) }
            }.onChange(of:selection) { load() }
            TextField("Name",text:$name)
            Toggle("Session entry point",isOn:$first)
            Toggle("Subroutine",isOn:$subroutine)
            if subroutine {
                Text("Children run in order; repeated names are allowed.").font(.caption).foregroundStyle(.secondary)
                ForEach($steps) { $step in
                    HStack {
                        Picker("Child",selection:$step.name) { ForEach(names,id:\.self) { Text($0).tag($0) } }
                        Button("Up") { moveStep(step.id,by:-1) }
                        Button("Down") { moveStep(step.id,by:1) }
                        Button("Remove") { steps.removeAll { $0.id == step.id } }
                    }
                }
                Button("Add Child") { if let name = names.first { steps.append(StepDraft(name:name)) } }.disabled(names.isEmpty)
            } else {
                Picker("Program",selection:$program) { ForEach(store.programNames,id:\.self) { Text($0).tag($0) } }
                Stepper("Duration: \(seconds) seconds",value:$seconds,in:0...Int(UInt32.max))
                Text("Zero duration permits immediate branching. No eligible branch holds the top-level item.").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Branches (\(branches.count))") {
                ForEach($branches) { $branch in
                    GroupBox {
                        VStack {
                            Picker("Destination",selection:$branch.destination) { ForEach(names,id:\.self) { Text($0).tag($0) } }
                            Stepper("Weight: \(branch.weight)",value:$branch.weight,in:0...1000)
                            Picker("Condition",selection:$branch.variable) {
                                Text("Unconditional").tag("")
                                ForEach(store.session?.json["variable_map"].object.keys.sorted() ?? [],id:\.self) { Text($0).tag($0) }
                            }
                            if !branch.variable.isEmpty { TextField("Required value",text:$branch.value) }
                            Button("Remove Branch") { branches.removeAll { $0.id == branch.id } }
                        }
                    }
                }
                Button("Add Branch") { if let name = names.first { branches.append(BranchDraft(destination:name)) } }.disabled(names.isEmpty)
            }
            DisclosureGroup("Audio Cues (\(cues.count))") {
                ForEach($cues) { $cue in
                    GroupBox {
                        VStack {
                            Picker("Action",selection:$cue.type) { Text("Play").tag("play"); Text("Stop").tag("stop"); Text("Fade").tag("fade") }
                            Stepper("Channel: \(cue.channel)",value:$cue.channel,in:0...1000)
                            if cue.type == "play" {
                                TextField("Relative audio file",text:$cue.path)
                                Toggle("Next unused channel",isOn:$cue.unused)
                                Toggle("Loop",isOn:$cue.loop)
                            }
                            if cue.type != "stop" { Stepper("Volume: \(cue.volume)%",value:$cue.volume,in:0...100) }
                            if cue.type == "fade" { Stepper("Fade: \(cue.seconds) seconds",value:$cue.seconds,in:0...Int(UInt32.max)) }
                            Button("Remove Cue") { cues.removeAll { $0.id == cue.id } }
                        }
                    }
                }
                Button("Add Audio Cue") { cues.append(CueDraft()) }
            }
            Button("Save Playlist Item",action:save).disabled(name.isEmpty || (!subroutine && program.isEmpty))
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
            Text("Saving restarts playlist playback from the session entry point.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { if program.isEmpty { program = store.programNames.first ?? "" } }
    }
    private func moveStep(_ id: UUID,by offset: Int) {
        guard let index = steps.firstIndex(where:{$0.id == id}),steps.indices.contains(index+offset) else { return }; steps.swapAt(index,index+offset)
    }
    private func load() {
        status = ""
        guard let item = store.session?.json["playlist"].object[selection] else {
            name = ""; program = store.programNames.first ?? ""; seconds = 0; subroutine = false; first = false; steps = []; branches = []; cues = []; return
        }
        name = selection; first = store.session?.json["first_playlist_item"].string == selection
        subroutine = item.object["subroutine"] != nil; program = item["standard"]["program"].string; seconds = Int(item["standard"]["play_time_seconds"].number)
        steps = item["subroutine"].array.map { StepDraft(name:$0.string) }
        branches = item["next_item"].array.map { BranchDraft(destination:$0["playlist_item_name"].string,weight:Int($0["random_weight"].number),variable:$0["condition_variable_name"].string,value:$0["condition_variable_value"].string) }
        cues = item["audio_event"].array.map { CueDraft(type:$0["type"].string,channel:Int($0["channel"].number),unused:$0["next_unused_channel"].bool,path:$0["path"].string,loop:$0["loop"].bool,volume:Int($0["volume"].number),seconds:Int($0["time_seconds"].number)) }
    }
    private func save() {
        guard let session = store.session else { return }
        var item: JSONValue = .object(["next_item":.array(branches.map(\.json)),"audio_event":.array(cues.map(\.json))])
        if subroutine { item["subroutine"] = .array(steps.map { .string($0.name) }) }
        else { item["standard"] = .object(["program":.string(program),"play_time_seconds":.number(Double(seconds))]) }
        do {
            let updated = try PlaylistAuthoring.save(session:session,originalName:selection.isEmpty ? nil : selection,name:name,item:item,first:first)
            try updated.save(); store.install(updated); selection = name; status = "Saved"
        } catch { status = error.localizedDescription }
    }
}
