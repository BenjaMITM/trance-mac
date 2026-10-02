import AppKit
import Carbon

@MainActor final class HotkeyService {
    static weak var active: HotkeyService?
    weak var store: PlaybackStore?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    init(store: PlaybackStore) { self.store = store; Self.active = self }
    func register() throws {
        var type = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(),{ _,_,_ in
            Task { @MainActor in if let store = HotkeyService.active?.store { store.setHidden(!store.hidden) } }
            return noErr
        },1,&type,nil,&handler)
        guard installed == noErr else { throw TranceError("Global hotkey handler failed: \(installed)") }
        let status = RegisterEventHotKey(UInt32(kVK_F11),UInt32(shiftKey),EventHotKeyID(signature:0x54524e43,id:1),GetApplicationEventTarget(),0,&reference)
        guard status == noErr else { throw TranceError("Shift+F11 registration failed: \(status). Use the menu bar Hide/Show control.") }
    }
    func stop() { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
