import AppKit
import ApplicationServices

// Verbundene Ränder: Zieht man am ECHTEN Rand eines Fensters, das Teil einer
// von Podium gekachelten Gruppe ist, folgen die Raster-Nachbarn — mit
// kontinuierlichem Ratio, ohne Rast-Stufen. Beobachtet per AXObserver
// (öffentliche API) ausschließlich Gruppen, die Podium selbst angelegt hat,
// solange die App läuft. Abschaltbar in den Einstellungen.
final class LinkedEdges {
    static let shared = LinkedEdges()

    private struct Group {
        let display: Display
        var wins: [AXUIElement]   // Slot-Reihenfolge wie beim Kacheln
        var tokens: [AXObserverCenter.Token]
        var mainR: CGFloat
        var crossR: CGFloat
    }

    private var groups: [CGDirectDisplayID: Group] = [:]
    private var suppressUntil = Date.distantPast
    private var pending: DispatchWorkItem?

    // Nach jedem Kacheln aufgerufen: Gruppe (neu) registrieren.
    func track(displayID id: CGDirectDisplayID, display: Display, wins: [AXUIElement],
               mainR: CGFloat, crossR: CGFloat) {
        untrack(id)
        guard SettingsStore.shared.linkedEdges, wins.count >= 2 else { return }
        var tokens: [AXObserverCenter.Token] = []
        for (idx, w) in wins.enumerated() {
            let pid = axPid(w)
            for note in [kAXResizedNotification as String, kAXUIElementDestroyedNotification as String] {
                if let t = AXObserverCenter.shared.subscribe(element: w, pid: pid, notification: note,
                                                             handler: { [weak self] _, n in
                    self?.handle(displayID: id, slot: idx, notification: n)
                }) {
                    tokens.append(t)
                }
            }
        }
        groups[id] = Group(display: display, wins: wins, tokens: tokens, mainR: mainR, crossR: crossR)
    }

    func untrack(_ id: CGDirectDisplayID) {
        if let g = groups.removeValue(forKey: id) {
            AXObserverCenter.shared.unsubscribeAll(g.tokens)
        }
    }

    func untrackAll() {
        Array(groups.keys).forEach(untrack)
    }

    // Podium setzt gleich selbst Frames — die dadurch ausgelösten Resize-
    // Events kurz ignorieren, sonst Rückkopplungsschleife.
    func suppress(for seconds: TimeInterval = 0.5) {
        suppressUntil = Date().addingTimeInterval(seconds)
    }

    private func handle(displayID id: CGDirectDisplayID, slot: Int, notification: String) {
        if notification == kAXUIElementDestroyedNotification as String {
            untrack(id)
            return
        }
        guard Date() >= suppressUntil, groups[id] != nil else { return }
        // Debounce: während des Drags feuern Events im Dauerfeuer — die
        // Nachbarn folgen jeweils dem letzten Stand.
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.follow(id: id, slot: slot) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    // Neue Ratios aus dem umgroßten Fenster ableiten und NUR die Nachbarn
    // nachziehen — das gezogene Fenster selbst bleibt unangetastet, sonst
    // kämpfen wir gegen die Maus des Nutzers.
    private func follow(id: CGDirectDisplayID, slot: Int) {
        guard var g = groups[id], slot < g.wins.count, let f = axFrame(g.wins[slot]) else { return }
        let d = g.display
        let inner = d.visible.insetBy(dx: Layout.gap, dy: Layout.gap)
        let totalW = inner.width - Layout.gap
        let totalH = inner.height - Layout.gap
        func clamp(_ v: CGFloat) -> CGFloat { max(0.15, min(0.85, v)) }

        switch g.wins.count {
        case 2:
            let frac = d.vertical ? f.height / totalH : f.width / totalW
            g.mainR = clamp(slot == 0 ? frac : 1 - frac)
        case 3:
            if d.vertical {
                if slot == 0 {
                    g.mainR = clamp(f.height / totalH)
                } else {
                    g.mainR = clamp(1 - f.height / totalH)
                    g.crossR = clamp(slot == 1 ? f.width / totalW : 1 - f.width / totalW)
                }
            } else {
                if slot == 0 {
                    g.mainR = clamp(f.width / totalW)
                } else {
                    g.mainR = clamp(1 - f.width / totalW)
                    g.crossR = clamp(slot == 1 ? f.height / totalH : 1 - f.height / totalH)
                }
            }
        default:   // 2x2, zeilen-major: Spalten = main, Reihen = cross
            g.mainR = clamp(slot % 2 == 0 ? f.width / totalW : 1 - f.width / totalW)
            g.crossR = clamp(slot < 2 ? f.height / totalH : 1 - f.height / totalH)
        }
        groups[id] = g

        let frames = Layout.frames(visible: d.visible, vertical: d.vertical, count: g.wins.count,
                                   split: 0, cross: 0, mainR: g.mainR, crossR: g.crossR)
        suppress(for: 0.4)
        for (i, w) in g.wins.enumerated() where i != slot {
            axSetFrame(w, frames[i])
        }
    }
}
