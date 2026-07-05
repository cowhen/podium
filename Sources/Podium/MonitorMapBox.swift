import AppKit

enum SeamKind { case main, cross }

// Unsichtbare Griff-Zone auf einer Raster-Fuge: Resize-Cursor beim Hover,
// Ziehen meldet die Position an die Box, die daraus die nächstliegende
// Rast-Stufe (33/50/67) ermittelt. Die Instanz ist PERSISTENT (wird beim
// Box-Rebuild nur umpositioniert, nie zerstört) — sonst bricht AppKit die
// laufende Drag-Session beim ersten Einrasten ab und man müsste neu ansetzen.
final class SeamHandleView: NSView {
    let kind: SeamKind
    var horizontalDrag = true   // true = vertikale Fuge, links/rechts ziehen
    weak var box: MonitorMapBox?

    init(kind: SeamKind, box: MonitorMapBox) {
        self.kind = kind
        self.box = box
        super.init(frame: .zero)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private var cursor: NSCursor { horizontalDrag ? .resizeLeftRight : .resizeUpDown }

    // Tracking-Area mit cursorUpdate statt Cursor-Rects — letztere feuern
    // nach dem Einblenden des Overlays notorisch unzuverlässig.
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        box?.seamDragged(kind: kind, windowPoint: event.locationInWindow, horizontal: horizontalDrag)
    }

    override func mouseDragged(with event: NSEvent) {
        cursor.set()   // Cursor beim Ziehen außerhalb der Griff-Zone halten
        box?.seamDragged(kind: kind, windowPoint: event.locationInWindow, horizontal: horizontalDrag)
    }
}

// Maßstabsgetreue Miniatur eines echten Monitors (Position + Aspect Ratio wie
// im Anordnungstab der Systemeinstellungen), Teil der Karte oben im Overlay.
// Zeigt bis zu 4 zugeordnete Fenster in einem zum Fenster-Count passenden
// Raster (1 -> voll, 2 -> Split, 3 -> 1 groß + 2 gestapelt, 4 -> 2x2). Beim
// Öffnen bereits mit den erkannten Vordergrund-Fenstern vorbelegt.
final class MonitorMapBox: NSView {
    let display: Display
    let accent: NSColor
    private let badge = NSView()
    private let ratioPillBG = NSView()
    private let ratioPill = NSTextField(labelWithString: "")
    private let crossPillBG = NSView()
    private let crossPill = NSTextField(labelWithString: "")
    private lazy var mainHandle = SeamHandleView(kind: .main, box: self)
    private lazy var crossHandle = SeamHandleView(kind: .cross, box: self)
    private let emptyHint = NSTextField(labelWithString: "Fenster hierher ziehen")
    private(set) var tiles: [WindowTileView] = []
    private(set) var ghostTiles: [WindowTileView] = []   // Hintergrund-Fenster, nicht im Raster
    weak var controller: OverlayController?

    override var isFlipped: Bool { true }   // oben-links, wie überall sonst im Projekt

    init(display: Display, number: Int, accent: NSColor, frame: NSRect, controller: OverlayController) {
        self.display = display
        self.accent = accent
        self.controller = controller
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        toolTip = display.name

        badge.wantsLayer = true
        badge.layer?.backgroundColor = accent.cgColor
        badge.layer?.cornerRadius = 12
        badge.layer?.cornerCurve = .continuous
        badge.frame = NSRect(x: 8, y: 8, width: 24, height: 24)
        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        numberLabel.textColor = .white
        numberLabel.sizeToFit()
        // Echt zentrieren statt Label über den ganzen Kreis zu spannen —
        // Labels zeichnen oben-bündig, die Ziffer säße sonst schief.
        numberLabel.frame.origin = NSPoint(x: (24 - numberLabel.frame.width) / 2,
                                           y: (24 - numberLabel.frame.height) / 2)
        badge.addSubview(numberLabel)
        addSubview(badge)

        emptyHint.font = .systemFont(ofSize: 12)
        emptyHint.textColor = .tertiaryLabelColor
        emptyHint.alignment = .center
        emptyHint.sizeToFit()
        emptyHint.frame.origin = NSPoint(x: (bounds.width - emptyHint.frame.width) / 2,
                                         y: (bounds.height - emptyHint.frame.height) / 2)
        emptyHint.isHidden = bounds.height < 60
        addSubview(emptyHint)

        setupPill(bg: ratioPillBG, label: ratioPill)
        setupPill(bg: crossPillBG, label: crossPill)
    }

    private func setupPill(bg: NSView, label: NSTextField) {
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        bg.layer?.cornerRadius = 10
        bg.layer?.cornerCurve = .continuous
        bg.isHidden = true
        bg.toolTip = "Klick auf ein Fenster vergrößert es — nochmal klicken steigert bzw. setzt zurück"
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        bg.addSubview(label)
        addSubview(bg)
    }

    // Pill an einer Fuge platzieren und mit "a : b" beschriften.
    private func placePill(bg: NSView, label: NSTextField, ratio r: CGFloat, at seam: NSPoint) {
        label.stringValue = "\(Int((r * 100).rounded())) : \(Int(((1 - r) * 100).rounded()))"
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 16, height: 20)
        label.frame.origin = NSPoint(x: (size.width - label.frame.width) / 2,
                                     y: (size.height - label.frame.height) / 2)
        bg.frame = NSRect(x: seam.x - size.width / 2, y: seam.y - size.height / 2,
                          width: size.width, height: size.height)
        bg.isHidden = false
        addSubview(bg, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func scaledRect(_ w: WinInfo) -> NSRect {
        let full = display.full
        return NSRect(x: (w.bounds.minX - full.minX) / full.width * bounds.width,
                      y: (w.bounds.minY - full.minY) / full.height * bounds.height,
                      width: w.bounds.width / full.width * bounds.width,
                      height: w.bounds.height / full.height * bounds.height)
    }

    // wins: dichte Liste (max 4), Index = Raster-Slot laut Layout.frames.
    // Gezeichnet werden die ECHTEN, auf die Box skalierten Fenster-Bounds —
    // wer ein Fenster auf dem Desktop umgroßt, sieht hier den Ist-Zustand,
    // nicht das idealisierte Raster. ghosts sind die übrigen (Bühnen-)Fenster
    // dieses Monitors: abgedunkelt an echter Position, damit die Karte den
    // vollständigen Ist-Zustand zeigt — ein halb verdecktes Fenster ist
    // sonst "unsichtbar", obwohl es real auf dem Schirm steht. Kacheln
    // gleicher Fenster gleiten animiert an ihre neue Position.
    func setAssigned(_ wins: [WinInfo], split: Int, cross: Int, ghosts: [WinInfo] = []) {
        var oldFrames: [CGWindowID: NSRect] = [:]
        for t in tiles { oldFrames[t.info.windowID] = t.frame }
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
        ghostTiles.forEach { $0.removeFromSuperview() }
        ghostTiles = []
        emptyHint.isHidden = !(wins.isEmpty && ghosts.isEmpty) || bounds.height < 60
        ratioPillBG.isHidden = true
        crossPillBG.isHidden = true
        mainHandle.isHidden = true
        crossHandle.isHidden = true

        // Geister zuerst einfügen (landen visuell hinter den Raster-Kacheln);
        // voll interaktiv — Klick fokussiert, Drag ordnet zu.
        for w in ghosts {
            let t = WindowTileView(info: w, isVisible: false, controller: controller!,
                                   frame: scaledRect(w), isGhost: true)
            addSubview(t, positioned: .below, relativeTo: badge)
            ghostTiles.append(t)
        }

        guard !wins.isEmpty else { return }

        let rects: [NSRect] = wins.map(scaledRect)

        // Rückwärts einfügen, damit Slot 0 (typischerweise das Hauptfenster)
        // bei Überlappungen visuell obenauf liegt.
        var built: [WindowTileView] = []
        for (i, w) in wins.enumerated().reversed() {
            let t = WindowTileView(info: w, isVisible: true, controller: controller!, frame: rects[i], accent: accent)
            addSubview(t, positioned: .below, relativeTo: badge)
            if let old = oldFrames[w.windowID], old.size == rects[i].size, old.origin != rects[i].origin {
                t.frame = old
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    t.animator().frame = rects[i]
                }
            }
            built.append(t)
        }
        tiles = built.reversed()

        // Ratio-PILLS nur, wenn die echten Fenster dem Raster (annähernd)
        // entsprechen — sonst wären die Zahlen gelogen. Die Fugen-GRIFFE
        // dagegen immer: ihre Position kommt aus den echten Kachel-Kanten,
        // denn App-Mindestgrößen (v.a. auf dem Hochkant-Monitor) lassen die
        // Realität leicht vom Raster abweichen und dürfen das Ziehen nicht
        // deaktivieren.
        let grid = Layout.frames(visible: bounds, vertical: display.vertical, count: wins.count, split: split, cross: cross)
        let tolX = bounds.width * 0.08, tolY = bounds.height * 0.08
        let matchesGrid = zip(rects, grid).allSatisfy { r, g in
            abs(r.minX - g.minX) < tolX && abs(r.minY - g.minY) < tolY &&
            abs(r.width - g.width) < tolX && abs(r.height - g.height) < tolY
        }

        func clampX(_ v: CGFloat) -> CGFloat { max(6, min(bounds.width - 6, v)) }
        func clampY(_ v: CGFloat) -> CGFloat { max(6, min(bounds.height - 6, v)) }

        if wins.count >= 2 {
            let verticalSeam = display.vertical && wins.count <= 3
            if verticalSeam {
                let below = wins.count == 2 ? rects[1].minY : min(rects[1].minY, rects[2].minY)
                let y = clampY((rects[0].maxY + below) / 2)
                if matchesGrid {
                    placePill(bg: ratioPillBG, label: ratioPill, ratio: Layout.ratio(split),
                              at: NSPoint(x: bounds.midX, y: y))
                }
                showSeamHandle(mainHandle, horizontalDrag: false,
                               frame: NSRect(x: 0, y: y - 5, width: bounds.width, height: 10))
            } else {
                let left = wins.count == 4 ? max(rects[0].maxX, rects[2].maxX) : rects[0].maxX
                let right: CGFloat
                switch wins.count {
                case 2: right = rects[1].minX
                case 3: right = min(rects[1].minX, rects[2].minX)
                default: right = min(rects[1].minX, rects[3].minX)
                }
                let x = clampX((left + right) / 2)
                if matchesGrid {
                    placePill(bg: ratioPillBG, label: ratioPill, ratio: Layout.ratio(split),
                              at: NSPoint(x: x, y: bounds.midY))
                }
                showSeamHandle(mainHandle, horizontalDrag: true,
                               frame: NSRect(x: x - 5, y: 0, width: 10, height: bounds.height))
            }
        }
        if wins.count >= 3 {
            let crossVertical = display.vertical && wins.count == 3   // Fuge verläuft vertikal
            if crossVertical {
                let x = clampX((rects[1].maxX + rects[2].minX) / 2)
                let y0 = min(rects[1].minY, rects[2].minY), y1 = max(rects[1].maxY, rects[2].maxY)
                if matchesGrid {
                    placePill(bg: crossPillBG, label: crossPill, ratio: Layout.ratio(cross),
                              at: NSPoint(x: x, y: (y0 + y1) / 2))
                }
                showSeamHandle(crossHandle, horizontalDrag: true,
                               frame: NSRect(x: x - 5, y: y0, width: 10, height: max(10, y1 - y0)))
            } else if wins.count == 3 {
                let y = clampY((rects[1].maxY + rects[2].minY) / 2)
                let x0 = min(rects[1].minX, rects[2].minX), x1 = max(rects[1].maxX, rects[2].maxX)
                if matchesGrid {
                    placePill(bg: crossPillBG, label: crossPill, ratio: Layout.ratio(cross),
                              at: NSPoint(x: (x0 + x1) / 2, y: y))
                }
                showSeamHandle(crossHandle, horizontalDrag: false,
                               frame: NSRect(x: x0, y: y - 5, width: max(10, x1 - x0), height: 10))
            } else {
                let y = clampY((max(rects[0].maxY, rects[1].maxY) + min(rects[2].minY, rects[3].minY)) / 2)
                if matchesGrid {
                    placePill(bg: crossPillBG, label: crossPill, ratio: Layout.ratio(cross),
                              at: NSPoint(x: rects[1].midX, y: y))
                }
                showSeamHandle(crossHandle, horizontalDrag: false,
                               frame: NSRect(x: 0, y: y - 5, width: bounds.width, height: 10))
            }
        }
    }

    private func showSeamHandle(_ h: SeamHandleView, horizontalDrag: Bool, frame: NSRect) {
        h.horizontalDrag = horizontalDrag
        h.frame = frame
        h.isHidden = false
        if h.superview == nil { addSubview(h, positioned: .above, relativeTo: nil) }
        h.updateTrackingAreas()
    }

    // Drag auf einer Fuge: Position entlang der Achse in die nächstliegende
    // Rast-Stufe (33/50/67) übersetzen und nur bei Wechsel anwenden — das
    // Einrasten kachelt live die echten Fenster mit.
    func seamDragged(kind: SeamKind, windowPoint p: NSPoint, horizontal: Bool) {
        let local = convert(p, from: nil)
        let frac = horizontal
            ? (local.x - Layout.gap) / max(1, bounds.width - 2 * Layout.gap)
            : (local.y - Layout.gap) / max(1, bounds.height - 2 * Layout.gap)
        let mode = frac < 0.415 ? 2 : (frac > 0.585 ? 1 : 0)
        controller?.seamChanged(display.id, kind: kind, mode: mode)
    }

    // Kachel unter dem Drop-Punkt (Index in tiles) oder nil bei freier Fläche.
    func dropSlot(atWindowPoint p: NSPoint) -> Int? {
        let local = convert(p, from: nil)
        return tiles.firstIndex { $0.frame.contains(local) }
    }

    var hitAreaInWindow: NSRect { convert(bounds.insetBy(dx: -14, dy: -14), to: nil) }

    // Hebt die Box während eines Drags als aktuelles Drop-Ziel hervor.
    func setDropTarget(_ on: Bool) {
        layer?.borderWidth = on ? 2 : 1
        layer?.borderColor = (on ? accent : accent.withAlphaComponent(0.55)).cgColor
        layer?.backgroundColor = (on ? accent.withAlphaComponent(0.10)
                                     : NSColor.white.withAlphaComponent(0.05)).cgColor
    }

    // Verhindert, dass Klicks auf freie Fläche zum Hintergrund hochbubbeln
    // und das Overlay schließen.
    override func mouseDown(with event: NSEvent) {}
}
