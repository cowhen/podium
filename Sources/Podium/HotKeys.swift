import Carbon.HIToolbox
import AppKit

// Globale Tastenkürzel via Carbon RegisterEventHotKey (kein Sonderrecht nötig).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    // Liefert false, wenn das System die Kombination ablehnt (z. B. bereits
    // anderweitig belegt) — der Aufrufer soll das sichtbar machen, sonst wirkt
    // das Tool schlicht tot.
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, mods: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        handlers[id] = action
        let hkID = EventHotKeyID(signature: OSType(0x53574D31) /* 'SWM1' */, id: id)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs[id] = ref
        return true
    }

    // Nötig fürs Umbelegen in den Einstellungen.
    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { HotKeyCenter.shared.fire(hkID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
