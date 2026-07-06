import AppKit
import ApplicationServices

// DIE eine Anwendungs-Routine für Bento-Snapping auf echte Fenster: aus einer
// Zone + "anderen" Fenstern den Slot-Plan (BentoLayout) bauen, alle Frames
// setzen (dieselben Layout.frames wie überall), und die verbundenen Ränder
// registrieren. Drag-to-Edge, Radial-Menü UND der Box-Drop im Overlay rufen
// exakt diese Funktion — damit sich die Positionierung überall identisch
// verhält und wechselseitiges Resizen überall gleich funktioniert.
enum BentoApply {
    // Liefert die platzierten Fenster in Slot-Reihenfolge (für die
    // Modell-Aktualisierung im Overlay). `others` = Front-zuerst sortierte
    // Mitspieler; leere Slots (fehlende others) bleiben bewusst frei, damit
    // ein einzelnes Fenster an einer Kante nur die Hälfte einnimmt (Aero-Snap).
    @discardableResult
    static func apply(zone: BentoZone, dragged: AXUIElement,
                      others: [AXUIElement], display d: Display) -> [AXUIElement] {
        let plan = BentoLayout.plan(zone: zone, othersAvailable: others.count)
        let vertical = plan.vertical ?? d.vertical
        let frames = Layout.frames(visible: d.visible, vertical: vertical,
                                   count: plan.tokens.count, split: 0)
        var placed: [(ax: AXUIElement, slot: Int)] = []
        for (i, token) in plan.tokens.enumerated() {
            switch token {
            case .dragged: placed.append((dragged, i))
            case .other(let n) where n < others.count: placed.append((others[n], i))
            default: break   // fehlender Mitspieler -> Slot bleibt leer
            }
        }
        LinkedEdges.shared.suppress()
        for (ax, slot) in placed { axSetFrame(ax, frames[slot]) }
        axRaise(dragged)
        // Verbundene Ränder registrieren — in Slot-Reihenfolge. Sind Slots
        // lückig (nur 1 Fenster), bricht track() bei count < 2 ohnehin ab.
        let ordered = placed.sorted { $0.slot < $1.slot }.map { $0.ax }
        LinkedEdges.shared.track(displayID: d.id, display: d, wins: ordered,
                                 mainR: 0.5, crossR: 0.5, vertical: vertical)
        return ordered
    }
}
