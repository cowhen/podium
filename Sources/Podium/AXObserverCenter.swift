import AppKit
import ApplicationServices

// Dünner Wrapper um AXObserver (öffentliche API): abonniert AX-Notifications
// (Resize, Move, Destroy) auf konkreten Fenstern. Ein Observer pro PID,
// Handler werden über ein Token-Registry verteilt. Fundament für verbundene
// Ränder (LinkedEdges) und die Tab-Leisten.
final class AXObserverCenter {
    static let shared = AXObserverCenter()

    struct Token: Hashable {
        let id: UInt64
    }

    private struct Subscription {
        let element: AXUIElement
        let notification: String
        let pid: pid_t
        let handler: (AXUIElement, String) -> Void
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var subs: [Token: Subscription] = [:]
    private var nextID: UInt64 = 1

    // Beendet sich eine beobachtete App, feuern deren Fenster nicht immer
    // saubere Destroy-Notifications — Observer + RunLoop-Source + Subs würden
    // für immer liegenbleiben (Leak über die Lebenszeit der Menüleisten-App).
    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.cleanUp(pid: app.processIdentifier)
        }
    }

    private func cleanUp(pid: pid_t) {
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        subs = subs.filter { $0.value.pid != pid }
    }

    // Abonniert eine Notification auf einem Element. Handler läuft auf dem
    // Main-Thread. Rückgabe nil, wenn der Observer nicht erzeugt werden kann
    // (App weg, keine Berechtigung).
    @discardableResult
    func subscribe(element: AXUIElement, pid: pid_t, notification: String,
                   handler: @escaping (AXUIElement, String) -> Void) -> Token? {
        guard let obs = observer(for: pid) else { return nil }
        let token = Token(id: nextID)
        nextID += 1
        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(token.id))
        guard AXObserverAddNotification(obs, element, notification as CFString, refcon) == .success else {
            return nil
        }
        subs[token] = Subscription(element: element, notification: notification, pid: pid, handler: handler)
        return token
    }

    func unsubscribe(_ token: Token) {
        guard let sub = subs.removeValue(forKey: token) else { return }
        if let obs = observers[sub.pid] {
            AXObserverRemoveNotification(obs, sub.element, sub.notification as CFString)
        }
    }

    func unsubscribeAll(_ tokens: [Token]) {
        tokens.forEach(unsubscribe)
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            let id = UInt64(UInt(bitPattern: refcon))
            DispatchQueue.main.async {
                AXObserverCenter.shared.dispatch(id: id, element: element, notification: notification as String)
            }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
        return obs
    }

    private func dispatch(id: UInt64, element: AXUIElement, notification: String) {
        guard let sub = subs[Token(id: id)] else { return }
        sub.handler(element, notification)
    }
}
