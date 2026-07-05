import CoreGraphics

// Der pure Zuordnungs-Kern des Overlays: welche Fenster liegen in welcher
// Monitor-Box (dicht, max maxAssigned), welche auf der Bühne, welche
// Split-Stufen gelten. Kein AppKit, keine AX-Aufrufe — vollständig testbar.
// Hier saßen historisch alle echten Bugs (Lücken-Array, Verdrängung,
// Slot-Reihenfolge), deshalb lebt die Logik jetzt isoliert vom Controller.
struct ArrangementModel {
    var assigned: [CGDirectDisplayID: [WinInfo]] = [:]
    var stage: [WinInfo] = []
    var splitMode: [CGDirectDisplayID: Int] = [:]   // Hauptachse, 0=50/50 1=67/33 2=33/67
    var crossMode: [CGDirectDisplayID: Int] = [:]   // Querachse (3er-Stapel / 2x2-Reihen)

    // MARK: Abfragen

    func boxOwner(of windowID: CGWindowID) -> CGDirectDisplayID? {
        assigned.first { $0.value.contains { $0.windowID == windowID } }?.key
    }

    func onStage(_ windowID: CGWindowID) -> Bool {
        stage.contains { $0.windowID == windowID }
    }

    func info(for windowID: CGWindowID) -> WinInfo? {
        for arr in assigned.values { if let w = arr.first(where: { $0.windowID == windowID }) { return w } }
        return stage.first { $0.windowID == windowID }
    }

    // MARK: Mutationen

    // Entfernt das Fenster überall und liefert die Box zurück, in der es war.
    @discardableResult
    mutating func removeEverywhere(_ windowID: CGWindowID) -> CGDirectDisplayID? {
        stage.removeAll { $0.windowID == windowID }
        let sourceBox = boxOwner(of: windowID)
        if let sourceBox { assigned[sourceBox]?.removeAll { $0.windowID == windowID } }
        return sourceBox
    }

    // Von außen in eine Box: anhängen solange Platz (Raster wächst), sonst
    // gezielt ersetzen — das Verdrängte wandert an den Bühnen-Anfang.
    // Liefert die Quell-Box (falls das Fenster vorher woanders zugeordnet war).
    @discardableResult
    mutating func dropFromOutside(_ info: WinInfo, onto id: CGDirectDisplayID,
                                  preferredSlot: Int? = nil,
                                  maxAssigned: Int = Tuning.maxAssigned) -> CGDirectDisplayID? {
        let sourceBox = removeEverywhere(info.windowID)
        var arr = assigned[id] ?? []
        if arr.count < maxAssigned {
            arr.append(info)
        } else {
            let slot = min(max(preferredSlot ?? arr.count - 1, 0), arr.count - 1)
            stage.insert(arr[slot], at: 0)
            arr[slot] = info
        }
        assigned[id] = arr
        return sourceBox
    }

    mutating func swapInBox(_ id: CGDirectDisplayID, _ a: Int, _ b: Int) {
        guard var arr = assigned[id], arr.indices.contains(a), arr.indices.contains(b), a != b else { return }
        arr.swapAt(a, b)
        assigned[id] = arr
    }

    // Aus der Box zurück auf die Bühne (ans Ende).
    @discardableResult
    mutating func demote(_ info: WinInfo) -> CGDirectDisplayID? {
        guard let sourceBox = boxOwner(of: info.windowID) else { return nil }
        assigned[sourceBox]?.removeAll { $0.windowID == info.windowID }
        stage.append(info)
        return sourceBox
    }

    // MARK: Ratio-Logik (pure Funktionen)

    // Rast-Reihenfolge entlang "erste Gruppe wächst": 33 -> 50 -> 67, geklemmt.
    static func stepMode(_ current: Int, up: Bool) -> Int {
        let order = [2, 0, 1]
        let i = order.firstIndex(of: current) ?? 1
        return order[max(0, min(order.count - 1, i + (up ? 1 : -1)))]
    }

    // Klick-Zyklus: jeder Klick macht das angeklickte Fenster prominenter —
    // 1. eigene Seite groß (Hauptachse), 2. innerhalb der Seite groß
    // (Querachse, nur 3er/2x2), 3. alles zurück auf 50/50.
    static func clickCycle(count: Int, idx: Int, main: Int, cross: Int) -> (main: Int, cross: Int) {
        // Hauptachsen-Gruppe: 2er/3er Slot 0 vs. Rest, 2x2 linke vs. rechte
        // Spalte (zeilen-major: gerade Slots = links).
        let mainFavor = (count == 4 ? idx % 2 == 0 : idx == 0) ? 1 : 2
        // Querachsen-Gruppe: 3er-Stapel Slot 1 vs. 2, 2x2 obere vs. untere
        // Reihe. Das große Fenster im 3er hat keine Querachse.
        let crossFavor: Int? = switch count {
        case 3 where idx > 0: idx == 1 ? 1 : 2
        case 4: idx < 2 ? 1 : 2
        default: nil
        }
        if main != mainFavor { return (mainFavor, cross) }
        if let crossFavor, cross != crossFavor { return (main, crossFavor) }
        return (0, 0)
    }
}
