import AppKit
import ApplicationServices

// Verbundene Ränder: Zieht man am ECHTEN Rand eines von Podium gekachelten
// Fensters, folgen die Fenster, die GENAU JETZT tatsächlich daneben liegen.
//
// Bewusst KEIN Gruppen-/Slot-/Ratio-Zustand mehr (frühere Version): der wurde
// beim Kacheln einmal eingefroren und niemals mehr überprüft — verschob man
// ein Fenster später solo (Loop-Modus, Direkt-Hotkey, von Hand) auf einen
// anderen Monitor, blieb sein Resize-Abo trotzdem an die alte Gruppe gebunden
// und verzerrte beim nächsten Resize Fenster auf dem völlig falschen Monitor.
//
// Stattdessen: bei JEDEM Resize wird live und geometrisch neu bestimmt, wer
// gerade wirklich angrenzt (gleicher Monitor + Kante deckt sich mit der ALTEN
// Position der bewegten Kante, Toleranz für den Kachel-Gap). Kein Fenster
// kann sich je an einer veralteten Zuordnung "festbeißen" — jede Entscheidung
// kommt frisch aus der Realität. Beobachtet weiterhin nur Fenster, die Podium
// selbst über BentoApply gekachelt hat (kein Desktop-weites Abo). Abschaltbar
// in den Einstellungen.
final class LinkedEdges {
    static let shared = LinkedEdges()

    private struct Watched {
        let id: UInt64            // stabile Kennung für den per-Fenster-Debounce
        let ax: AXUIElement
        var lastFrame: CGRect
        var tokens: [AXObserverCenter.Token]
    }

    // Zwei Kanten gelten als "verbunden", wenn sie höchstens so weit auseinander
    // liegen — deckt den Standard-Kachel-Gap (Layout.gap) plus Rundungstoleranz ab.
    private static let edgeTolerance: CGFloat = 16

    private var watched: [Watched] = []
    private var suppressUntil = Date.distantPast
    // Debounce PRO Fenster — ein geteilter WorkItem würde bei zwei schnell
    // aufeinanderfolgenden Resizes verschiedener Fenster das erste follow()
    // canceln (Nachbarn folgen nie, Baseline bleibt stale).
    private var pendings: [UInt64: DispatchWorkItem] = [:]
    private var nextID: UInt64 = 1
    // Nachbarn folgen NUR, wenn beim Resizen ⌃ (Control) gehalten wird —
    // sonst würde JEDES Resize eines gekachelten Fensters ungefragt Nachbarn
    // mitziehen. ⇧ und ⌥ scheiden aus: macOS belegt beide beim Ziehen einer
    // Fensterkante bereits nativ (⇧ = Seitenverhältnis beibehalten, ⌥ =
    // symmetrisch von der Mitte aus, zusammen beides kombiniert) — ⌃ hat
    // dort keine native Bedeutung. AX-Events tragen keinen Tastatur-Zustand;
    // dafür global den Control-Status mitlesen (öffentliche API, rein
    // lesend, wie bei DragSnap).
    private var isControlHeld = false
    private var flagsMonitor: Any?

    // Einmal beim App-Start aufrufen (main.swift, neben DragSnapManager.start()).
    func start() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isControlHeld = event.modifierFlags.contains(.control)
        }
    }

    // Nach jedem Kacheln aufgerufen: Fenster fürs Beobachten anmelden (idempotent —
    // bereits beobachtete Fenster werden nicht doppelt abonniert, nur ihr
    // Referenz-Frame aktualisiert). Räumt dabei tote Einträge auf (Fenster,
    // deren App ohne Destroy-Notification verschwunden ist), damit die Liste
    // über die App-Lebenszeit nicht unbegrenzt wächst.
    func track(_ wins: [AXUIElement]) {
        guard SettingsStore.shared.linkedEdges else { return }
        sweepDead()
        for w in wins { ensureWatched(w) }
    }

    private func sweepDead() {
        var alive: [Watched] = []
        for w in watched {
            if axFrame(w.ax) != nil {
                alive.append(w)
            } else {
                AXObserverCenter.shared.unsubscribeAll(w.tokens)
                pendings.removeValue(forKey: w.id)?.cancel()
            }
        }
        watched = alive
    }

    private func ensureWatched(_ ax: AXUIElement) {
        if let idx = watched.firstIndex(where: { CFEqual($0.ax, ax) }) {
            watched[idx].lastFrame = axFrame(ax) ?? watched[idx].lastFrame
            return
        }
        guard let frame = axFrame(ax) else { return }
        let pid = axPid(ax)
        var tokens: [AXObserverCenter.Token] = []
        // Move MIT abonnieren: ein reines Verschieben ändert den Frame, feuert
        // aber kein Resized — ohne Move-Abo veraltet lastFrame und der nächste
        // Resize diffte gegen den Stand von VOR dem Verschieben (Phantom-Folgen
        // auf längst entfernte Ex-Nachbarn).
        for note in [kAXResizedNotification as String, kAXMovedNotification as String,
                     kAXUIElementDestroyedNotification as String] {
            if let t = AXObserverCenter.shared.subscribe(element: ax, pid: pid, notification: note,
                                                         handler: { [weak self] el, n in
                self?.handle(ax: el, notification: n)
            }) {
                tokens.append(t)
            }
        }
        // Ohne ein einziges erfolgreiches Abo wäre der Eintrag ein Zombie
        // (nie Events, nie Destroy-Aufräumen) — dann lieber gar nicht aufnehmen.
        guard !tokens.isEmpty else { return }
        watched.append(Watched(id: nextID, ax: ax, lastFrame: frame, tokens: tokens))
        nextID += 1
    }

    func untrackAll() {
        for w in watched { AXObserverCenter.shared.unsubscribeAll(w.tokens) }
        watched = []
        pendings.values.forEach { $0.cancel() }
        pendings = [:]
    }

    // Podium setzt gleich selbst Frames — die dadurch ausgelösten Resize-
    // Events kurz ignorieren, sonst Rückkopplungsschleife.
    func suppress(for seconds: TimeInterval = 0.5) {
        suppressUntil = Date().addingTimeInterval(seconds)
    }

    private func handle(ax: AXUIElement, notification: String) {
        if notification == kAXUIElementDestroyedNotification as String {
            forget(ax)
            return
        }
        guard let idx = watched.firstIndex(where: { CFEqual($0.ax, ax) }) else { return }
        if notification == kAXMovedNotification as String {
            // Reines Verschieben: nur die Baseline mitziehen, niemand folgt.
            watched[idx].lastFrame = axFrame(ax) ?? watched[idx].lastFrame
            return
        }
        guard Date() >= suppressUntil else { return }
        // Debounce: während des Drags feuern Events im Dauerfeuer — erst
        // reagieren, wenn eine Weile Ruhe ist, dann mit dem dann aktuellen Stand.
        let id = watched[idx].id
        pendings[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendings.removeValue(forKey: id)
            self?.follow(watchedID: id)
        }
        pendings[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func forget(_ ax: AXUIElement) {
        guard let idx = watched.firstIndex(where: { CFEqual($0.ax, ax) }) else { return }
        AXObserverCenter.shared.unsubscribeAll(watched[idx].tokens)
        pendings.removeValue(forKey: watched[idx].id)?.cancel()
        watched.remove(at: idx)
    }

    // MARK: AX-Seite — live Kandidaten einsammeln, an die reine Geometrie
    // delegieren, Ergebnis anwenden.

    private func follow(watchedID: UInt64) {
        guard let idx = watched.firstIndex(where: { $0.id == watchedID }),
              let new = axFrame(watched[idx].ax) else { return }
        let old = watched[idx].lastFrame
        watched[idx].lastFrame = new   // Baseline sofort weiterschieben, unabhängig vom Ergebnis unten
        guard old != new else { return }
        // Nachbarn folgen nur, wenn ⌃ beim Resizen gehalten wurde — die
        // Baseline oben ist trotzdem aktuell, ein Resize OHNE ⌃ verzieht also
        // nie einen späteren ⌃-Resize durch eine veraltete Kante.
        guard isControlHeld else { return }

        let ds = currentDisplays()
        guard let dID = displayID(containing: CGPoint(x: new.midX, y: new.midY), in: ds) else { return }

        // Nur Fenster auf DEMSELBEN Monitor sind Kandidaten — verhindert, dass
        // zwei Fenster auf benachbarten Monitoren durch einen zufällig
        // übereinstimmenden Rand (Monitor-Grenze) fälschlich verbunden werden.
        var candidateIndices: [Int] = []
        var candidateFrames: [CGRect] = []
        for (i, w) in watched.enumerated() where i != idx {
            guard let f = axFrame(w.ax),
                  displayID(containing: CGPoint(x: f.midX, y: f.midY), in: ds) == dID else { continue }
            candidateIndices.append(i)
            candidateFrames.append(f)
        }
        guard !candidateFrames.isEmpty else { return }

        let updates = Self.computeNeighborUpdates(resizedOld: old, resizedNew: new, candidates: candidateFrames)
        guard !updates.isEmpty else { return }

        suppress(for: 0.4)
        for (candidateIdx, frame) in updates {
            let watchedIdx = candidateIndices[candidateIdx]
            axSetFrame(watched[watchedIdx].ax, frame)
            watched[watchedIdx].lastFrame = axFrame(watched[watchedIdx].ax) ?? frame
        }
    }

    // MARK: Reine Geometrie — testbar ohne AX.
    //
    // `candidates[i]` gilt als Nachbar, wenn seine Kante (mit `tolerance`)
    // genau an der ALTEN Position der Kante liegt, die sich bei `resized`
    // bewegt hat (plus/minus `gap`, dem Standard-Kachel-Abstand) — UND sich
    // mit `resized` auf der jeweils anderen Achse überlappt (sonst würden
    // zwei Fenster, die nur zufällig dieselbe X/Y-Koordinate haben, aber in
    // einer anderen Reihe/Spalte liegen, fälschlich verknüpft). Nur die
    // Kante, die wirklich anliegt, wird verschoben — die gegenüberliegende
    // Kante des Nachbarn bleibt fix. Ein Nachbar, der auf zwei Achsen
    // gleichzeitig trifft (Eck-Resize eines 2x2-Rasters), bekommt beide
    // Änderungen kombiniert statt sich gegenseitig zu überschreiben.
    static func computeNeighborUpdates(resizedOld old: CGRect, resizedNew new: CGRect,
                                       candidates: [CGRect], gap: CGFloat = Layout.gap,
                                       tolerance: CGFloat = edgeTolerance,
                                       minEdge: CGFloat = Tuning.minWindowEdge) -> [Int: CGRect] {
        // Reine Translation (Größe unverändert) ist KEIN Resize — ohne diesen
        // Guard würden bei einem verschobenen Fenster beide Achsen-Zweige
        // feuern und Ex-Nachbarn an der alten Position mitgerissen.
        guard old.size != new.size else { return [:] }
        // Prozentual (nicht fix): eine schmale Eck-Berührung (z. B. der
        // diagonale Nachbar in einem 2x2-Raster, der NUR eine Ecke, keine
        // echte Kante teilt) soll nicht als "echter Nachbar in dieser Reihe/
        // Spalte" durchgehen — nur substanzielle Überlappung zählt.
        func verticalOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
            min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0.4 * min(a.height, b.height)
        }
        func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
            min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0.4 * min(a.width, b.width)
        }

        var result: [Int: CGRect] = [:]

        // Rechte Kante bewegt -> Nachbarn rechts folgen mit ihrer linken Kante.
        if abs(new.maxX - old.maxX) > 0.5 {
            for (i, f) in candidates.enumerated()
            where verticalOverlap(new, f) && abs(f.minX - (old.maxX + gap)) < tolerance {
                let nf = result[i] ?? f
                let newMinX = new.maxX + gap
                let width = max(minEdge, nf.maxX - newMinX)
                result[i] = CGRect(x: newMinX, y: nf.minY, width: width, height: nf.height)
            }
        }
        // Linke Kante bewegt -> Nachbarn links folgen mit ihrer rechten Kante.
        if abs(new.minX - old.minX) > 0.5 {
            for (i, f) in candidates.enumerated()
            where verticalOverlap(new, f) && abs(f.maxX - (old.minX - gap)) < tolerance {
                let nf = result[i] ?? f
                let newMaxX = new.minX - gap
                let width = max(minEdge, newMaxX - nf.minX)
                result[i] = CGRect(x: nf.minX, y: nf.minY, width: width, height: nf.height)
            }
        }
        // Untere Kante bewegt (Quartz: maxY = unten) -> Nachbarn darunter folgen mit ihrer oberen Kante.
        if abs(new.maxY - old.maxY) > 0.5 {
            for (i, f) in candidates.enumerated()
            where horizontalOverlap(new, f) && abs(f.minY - (old.maxY + gap)) < tolerance {
                let nf = result[i] ?? f
                let newMinY = new.maxY + gap
                let height = max(minEdge, nf.maxY - newMinY)
                result[i] = CGRect(x: nf.minX, y: newMinY, width: nf.width, height: height)
            }
        }
        // Obere Kante bewegt -> Nachbarn darüber folgen mit ihrer unteren Kante.
        if abs(new.minY - old.minY) > 0.5 {
            for (i, f) in candidates.enumerated()
            where horizontalOverlap(new, f) && abs(f.maxY - (old.minY - gap)) < tolerance {
                let nf = result[i] ?? f
                let newMaxY = new.minY - gap
                let height = max(minEdge, newMaxY - nf.minY)
                result[i] = CGRect(x: nf.minX, y: nf.minY, width: nf.width, height: height)
            }
        }
        return result
    }
}
