import SwiftUI

struct AudioControls: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        VStack(alignment:.leading) {
            Toggle("Mute all audio",isOn:$store.muted)
            let bed = store.program["entrainment"]
            if bed["layer"].array.isEmpty {
                Button("Enable Synthesized Bed") {
                    store.updateProgram("entrainment",.object(["master_db":.number(-28),"layer":.array([.object(["center_hz":.number(312),"binaural_hz":.number(3),"pulse_hz":.number(5),"amplitude_db":.number(0)]),.object(["center_hz":.number(60),"binaural_hz":.number(3),"pulse_hz":.number(3.25),"amplitude_db":.number(-6)])])]))
                }
            } else {
                Slider(value:Binding(get:{bed["master_db"].number == 0 ? -28 : bed["master_db"].number},set:{value in var next = bed; next["master_db"] = .number(value); store.updateProgram("entrainment",next)}),in:-60 ... -6) { Text("Master dB") }
                ForEach(Array(bed["layer"].array.enumerated()),id:\.offset) { index,layer in
                    GroupBox("Layer \(index+1)") {
                        VStack {
                            parameter("Carrier Hz",key:"center_hz",index:index,range:20...1000)
                            parameter("Binaural Hz",key:"binaural_hz",index:index,range:0...40)
                            parameter("Pulse Hz",key:"pulse_hz",index:index,range:0...40)
                            parameter("Mix dB",key:"amplitude_db",index:index,range:-24...0)
                            Button("Remove Layer") { var next = bed; var layers = next["layer"].array; layers.remove(at:index); next["layer"] = .array(layers); store.updateProgram("entrainment",next) }
                        }
                    }
                }
                Button("Add Layer") { var next = bed; var layers = next["layer"].array; layers.append(.object(["center_hz":.number(200),"binaural_hz":.number(3),"pulse_hz":.number(0),"amplitude_db":.number(-6)])); next["layer"] = .array(layers); store.updateProgram("entrainment",next) }
                Button("Disable Bed") { var next = bed; next["layer"] = .array([]); store.updateProgram("entrainment",next) }
            }
        }
    }
    private func parameter(_ title: String,key: String,index: Int,range: ClosedRange<Double>) -> some View {
        let value = store.program["entrainment"]["layer"].array[index][key].number
        return HStack {
            Text(title).frame(width:90,alignment:.leading)
            Slider(value:Binding(get:{value},set:{ value in
                var next = store.program["entrainment"]; var layers = next["layer"].array; layers[index][key] = .number(value); next["layer"] = .array(layers); store.updateProgram("entrainment",next)
            }),in:range)
            Text(value,format:.number.precision(.fractionLength(1))).frame(width:45,alignment:.trailing)
        }
    }
}
