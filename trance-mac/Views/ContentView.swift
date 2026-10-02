import SwiftUI

struct ContentView: View {
    @Bindable var store: PlaybackStore
    var body: some View {
        HSplitView {
            if store.showControls { ControlPanel(store:store).frame(minWidth:380,idealWidth:420,maxWidth:560) }
            ZStack(alignment:.topLeading) {
                PlayerView(store:store)
                if store.session == nil {
                    ContentUnavailableView {
                        Label("Trance",systemImage:"circle.hexagongrid")
                    } description: {
                        Text("Open a session or choose a media folder to begin.")
                    } actions: {
                        Button("Open Session…",action:store.open)
                        Button("Choose Media Folder…",action:store.scanFolder)
                    }.foregroundStyle(.white)
                }
                if store.showDiagnostics {
                    VStack(alignment:.leading) {
                        Text("\(store.visualName) · \(store.programName)")
                        Text("\(store.primaryTheme) / \(store.secondaryTheme)")
                        ForEach(store.diagnostics,id:\.self) { Text($0) }
                    }.font(.system(.caption,design:.monospaced)).padding().background(.regularMaterial)
                }
            }.frame(minWidth:480,minHeight:640)
        }
        .toolbar {
            Button("Open session file…",systemImage:"folder",action:store.open).help("Open a saved Trance session")
            Button(store.paused ? "Resume" : "Pause",systemImage:store.paused ? "play.fill" : "pause.fill") { store.paused.toggle() }.disabled(store.session == nil)
            Button(store.muted ? "Unmute" : "Mute",systemImage:store.muted ? "speaker.slash" : "speaker.wave.2") { store.muted.toggle() }
            Button(store.showControls ? "Hide controls" : "Show controls",systemImage:"sidebar.left") { store.showControls.toggle() }
        }
        .alert("Unable to complete action",isPresented:Binding(get:{ store.message != nil },set:{ if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .task {
            store.start()
            while !Task.isCancelled {
                store.tick()
                do { try await Task.sleep(for:.milliseconds(8)) } catch { break }
            }
        }
    }
}
