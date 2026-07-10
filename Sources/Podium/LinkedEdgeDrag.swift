import AppKit
import ApplicationServices

// Speed-Gated Linked Edges: ersetzt den reinen ⌃-Modifier-Zwang als
// alleiniges Gate (siehe LinkedEdges.swift) durch die Zuggeschwindigkeit der
// echten Fensterkante — langsames, bedächtiges Ziehen verbindet Nachbarn,
// schnelles Ziehen/Flick lässt sie unberührt, ganz ohne gehaltene Taste. ⌃
// bleibt als Force-Override (LinkedEdges.isForceLinked). Architektur bewusst
// an DragSnapManager angelehnt (globale NSEvent-Monitore statt AXObserver-
// Notifications, die für eine flüssige Geschwindigkeitsmessung zu grob/
// app-abhängig getaktet sind) — eigene, isolierte Datei statt Umbau von
// DragSnap.swift (Projekt-Präzedenz: Isolation statt Kopplung zwischen
// einzelnen Drag-Features, siehe Kommentar zu LoopPreviewPanel in LoopMenu.swift).

// MARK: Pure Zustandsmaschine (testbar, kein AppKit/AX)

// Hysterese statt einer einzelnen Schwelle: zwischen den beiden Werten
// bleibt der bisherige Zustand unverändert — verhindert Flackern, wenn die
// Handgeschwindigkeit genau um einen einzigen Wert oszilliert (dasselbe
// Prinzip wie Apples eigener 3D-Touch-"hysteresis intensity threshold").
enum LinkedEdgeVelocity {
    static func nextLinked(current: Bool, velocity: CGFloat,
                           engage: CGFloat = Tuning.linkedEdgeEngageVelocity,
                           disengage: CGFloat = Tuning.linkedEdgeDisengageVelocity) -> Bool {
        if velocity <= engage { return true }
        if velocity >= disengage { return false }
        return current
    }

    // Exponentiell gleitender Mittelwert — dämpft Ausreißer aus einzelnen,
    // ungleichmäßig getakteten Maus-Samples. `previous == nil` (erstes
    // Sample) übernimmt den Rohwert unverändert, kein Sprung von 0.
    static func smoothed(previous: CGFloat?, sample: CGFloat,
                         alpha: CGFloat = Tuning.linkedEdgeVelocitySmoothing) -> CGFloat {
        guard let previous else { return sample }
        return alpha * sample + (1 - alpha) * previous
    }

    // Kontinuierliches Feedback statt hartem Ein/Aus: innerhalb der
    // Hysterese-Bande blendet die Vorschau graduell aus, je näher die
    // Geschwindigkeit an die Trenn-Schwelle rückt ("die Verbindung lockert
    // sich"), statt hart bei disengage auf 0 zu springen.
    static func previewAlpha(velocity: CGFloat,
                             engage: CGFloat = Tuning.linkedEdgeEngageVelocity,
                             disengage: CGFloat = Tuning.linkedEdgeDisengageVelocity) -> CGFloat {
        guard velocity > engage else { return 1 }
        guard velocity < disengage else { return 0 }
        return 1 - (velocity - engage) / (disengage - engage)
    }
}

// MARK: AX/AppKit-Orchestrierung

final class LinkedEdgeDrag {
    static let shared = LinkedEdgeDrag()

    private var downMonitor: Any?
    private var draggedMonitor: Any?
    private var upMonitor: Any?

    private var mouseIsDown = false
    private var candidate: AXUIElement?
    private var dragStartFrame: CGRect?
    private var isResizing = false

    private var lastSampleFrame: CGRect?
    private var lastSampleTime: TimeInterval?
    private var smoothedVelocity: CGFloat?

    // Jede neue Geste startet "nicht verbunden" — kein Grund, vom Ende der
    // letzten Geste zu erben.
    private var linked = false

    // Momentaufnahme des zuletzt gezeigten Vorschau-Standes — beim
    // Loslassen real angewendet, falls zu diesem Zeitpunkt verbunden.
    private var lastCandidates: [(ax: AXUIElement, frame: CGRect)] = []
    private var lastUpdates: [Int: CGRect] = [:]

    private let neighborPreviews = GhostPreviewSet()
    private let draggedIndicator = GhostPanel(style: .border)

    func start() {
        guard downMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleDown()
        }
        draggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDragged(event)
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleUp()
        }
    }

    private func handleDown() {
        mouseIsDown = true
        candidate = nil
        dragStartFrame = nil
        isResizing = false
        resetVelocity()
        linked = false
    }

    private func resolveCandidate() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let w = axCopy(axApp, kAXFocusedWindowAttribute as String) else { return }
        let win = (w as! AXUIElement)
        // Nur Fenster, die LinkedEdges schon "gesehen" hat — unverändertes
        // Scope ggü. dem alten ⌃-Gate (kein Desktop-weites Abo).
        guard LinkedEdges.shared.isWatching(win) else { return }
        candidate = win
        dragStartFrame = axFrame(win)
    }

    private func handleDragged(_ event: NSEvent) {
        guard SettingsStore.shared.linkedEdges, mouseIsDown else { return }
        if candidate == nil {
            resolveCandidate()
            guard candidate != nil else { mouseIsDown = false; return }   // kein Ziel — Rest des Drags ignorieren
        }
        guard let c = candidate, let start = dragStartFrame, let cur = axFrame(c) else { return }
        if !isResizing {
            // Erst als Resize werten, wenn sich die GRÖSSE geändert hat —
            // das genaue Gegenteil von DragSnapManager's Move-Erkennung
            // (dort: Größe gleich + Position bewegt = Move, hier umgekehrt).
            guard cur.size != start.size else { return }
            isResizing = true
        }
        sampleVelocity(frame: cur, timestamp: event.timestamp)
        updateLinkState()
        updatePreview(dragged: c, start: start, current: cur)
    }

    private func handleUp() {
        defer {
            mouseIsDown = false; candidate = nil; dragStartFrame = nil; isResizing = false
            resetVelocity()
            hideAll()
        }
        guard isResizing, linked, !lastUpdates.isEmpty else { return }
        LinkedEdges.shared.applyNeighborUpdates(lastUpdates, to: lastCandidates)
        if let c = candidate, let cur = axFrame(c) { LinkedEdges.shared.refreshBaseline(c, frame: cur) }
    }

    // MARK: Geschwindigkeit

    private func resetVelocity() {
        lastSampleFrame = nil
        lastSampleTime = nil
        smoothedVelocity = nil
    }

    private func sampleVelocity(frame: CGRect, timestamp: TimeInterval) {
        defer { lastSampleFrame = frame; lastSampleTime = timestamp }
        guard let prevFrame = lastSampleFrame, let prevTime = lastSampleTime else { return }
        let dt = timestamp - prevTime
        guard dt > 0.001 else { return }   // Duplikat-Events ignorieren, keine Division durch ~0
        let dx = max(abs(frame.minX - prevFrame.minX), abs(frame.maxX - prevFrame.maxX))
        let dy = max(abs(frame.minY - prevFrame.minY), abs(frame.maxY - prevFrame.maxY))
        let distance = max(dx, dy)   // die schnellste bewegte Kante entscheidet
        let instant = CGFloat(distance / dt)
        smoothedVelocity = LinkedEdgeVelocity.smoothed(previous: smoothedVelocity, sample: instant)
    }

    private func updateLinkState() {
        guard let v = smoothedVelocity else { return }   // erstes Sample: noch kein Urteil möglich
        linked = LinkedEdges.shared.isForceLinked || LinkedEdgeVelocity.nextLinked(current: linked, velocity: v)
    }

    // MARK: Live-Vorschau

    private func updatePreview(dragged: AXUIElement, start: CGRect, current: CGRect) {
        guard linked else { hideAll(); return }
        let candidates = LinkedEdges.shared.neighborCandidates(excluding: dragged, near: CGPoint(x: current.midX, y: current.midY))
        lastCandidates = candidates
        guard !candidates.isEmpty else { lastUpdates = [:]; hideAll(); return }
        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: start, resizedNew: current,
                                                         candidates: candidates.map { $0.frame })
        lastUpdates = updates
        guard !updates.isEmpty else { hideAll(); return }

        let alpha = LinkedEdges.shared.isForceLinked ? 1
            : LinkedEdgeVelocity.previewAlpha(velocity: smoothedVelocity ?? 0)
        // Stabile Reihenfolge (sortierte Kandidaten-Indizes statt Dictionary-
        // Iterationsreihenfolge) — sonst könnten Panels zwischen Ticks die
        // Nachbarn tauschen, statt an Ort und Stelle weiterzuanimieren.
        let rects = updates.keys.sorted().map { updates[$0]! }
        neighborPreviews.show(rects, alpha: alpha)
        draggedIndicator.show(quartzRect: current, alpha: alpha)
    }

    private func hideAll() {
        neighborPreviews.hideAll()
        draggedIndicator.hide()
        lastUpdates = [:]
        lastCandidates = []
    }
}
