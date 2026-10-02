import SwiftUI

struct AudioControls: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.muted || store.paused {
                Label(store.muted ? "Audio is muted. Turn sound on above to hear changes." : "Playback is paused. Resume above to hear changes.", systemImage: "speaker.slash").font(.callout)
            }
            let bed = store.program["entrainment"]
            if bed["layer"].array.isEmpty {
                Text("Synthesized tones are off").font(.headline)
                Text("Enable tones to add a continuous stereo sound beneath recorded audio.").foregroundStyle(.secondary)
                Button("Enable synthesized tones") { store.updateProgram("entrainment", Session.defaultProgram["entrainment"]) }.accessibilityIdentifier("enable-tones")
            } else {
                Text("Synthesized tones are on").font(.headline).accessibilityIdentifier("tone-state")
                let master = bed["master_db"].number == 0 ? -28 : bed["master_db"].number
                LabeledContent("Overall tone volume", value: String(format: "%.1f dB", master))
                Slider(value: Binding(get: { let value = store.program["entrainment"]["master_db"].number; return value == 0 ? -28 : value }, set: { value in
                    var next = store.program["entrainment"]; next["master_db"] = .number(value); store.updateProgram("entrainment", next)
                }), in: -60 ... -6).accessibilityLabel("Overall tone volume").accessibilityIdentifier("tone-volume")
                Text("Less-negative dB values are louder. This volume affects synthesized tones; recorded audio has its own playlist volume.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(bed["layer"].array.enumerated()), id: \.offset) { index, _ in
                    GroupBox("Tone \(index + 1)") {
                        VStack(alignment: .leading, spacing: 12) {
                            parameter("Tone pitch", detail: "The center pitch shared by the left and right channels.", unit: "Hz", key: "center_hz", index: index, range: 20...1000)
                            parameter("Stereo frequency difference", detail: "The left and right tones differ by this amount. 0 gives both channels the same pitch.", unit: "Hz", key: "binaural_hz", index: index, range: 0...40)
                            parameter("Volume pulse rate", detail: "Controls rhythmic volume changes between channels. 0 keeps the tone steady.", unit: "Hz", key: "pulse_hz", index: index, range: 0...40)
                            parameter("Volume relative to other tones", detail: "0 dB is the full blend level; negative values reduce this tone.", unit: "dB", key: "amplitude_db", index: index, range: -60...0)
                            Button("Remove tone \(index + 1)") {
                                var next = store.program["entrainment"]; var layers = next["layer"].array
                                guard layers.indices.contains(index) else { return }
                                layers.remove(at: index); next["layer"] = .array(layers); store.updateProgram("entrainment", next)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("Add another tone") {
                    var next = store.program["entrainment"]; var layers = next["layer"].array
                    layers.append(.object(["center_hz": .number(200), "binaural_hz": .number(3), "pulse_hz": .number(0), "amplitude_db": .number(-6)]))
                    next["layer"] = .array(layers); store.updateProgram("entrainment", next)
                }.accessibilityIdentifier("add-tone")
                Button("Turn off synthesized tones") {
                    var next = store.program["entrainment"]; next["layer"] = .array([]); store.updateProgram("entrainment", next)
                }.accessibilityIdentifier("disable-tones")
                Text("Tone edits apply with a short fade and save to the current program.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func parameter(_ title: String, detail: String, unit: String, key: String, index: Int, range: ClosedRange<Double>) -> some View {
        let layers = store.program["entrainment"]["layer"].array
        let value = layers.indices.contains(index) ? layers[index][key].number : range.lowerBound
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: String(format: "%.1f %@", value, unit))
            Slider(value: Binding(get: {
                let layers = store.program["entrainment"]["layer"].array
                return layers.indices.contains(index) ? layers[index][key].number : range.lowerBound
            }, set: { value in
                var next = store.program["entrainment"]; var layers = next["layer"].array
                guard layers.indices.contains(index) else { return }
                layers[index][key] = .number(value); next["layer"] = .array(layers); store.updateProgram("entrainment", next)
            }), in: range).accessibilityLabel(title).accessibilityIdentifier("tone-\(index)-\(key)")
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
