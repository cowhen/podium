import AppKit

// Randloses Fenster, das trotzdem Key werden kann. Tastatur geht komplett an
// den Controller: Enter schließt (behalten), Escape leert erst die Suche und
// rollt sonst alles zurück, jedes andere Zeichen filtert die Bühne.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if !OverlayController.shared.handleKey(event) { super.keyDown(with: event) }
    }
}

final class OverlayBackgroundView: FlippedVisualEffectView {
    override func mouseDown(with event: NSEvent) { OverlayController.shared.close() }
}

// "Karte + Bühne": Oben die maßstabsgetreue Monitor-Karte (eine Akzentfarbe
// pro Monitor) mit den zugeordneten Fenstern — die einzige räumliche Wahrheit.
// Unten EINE Bühne mit allen Hintergrund-Fenstern, gruppiert nach App; der
// Farbpunkt jeder Kachel zeigt, auf welchem Monitor sie gerade liegt.
// Position = Karte, Identität = App-Gruppe, Herkunft = Farbpunkt.
// Jede Aktion wirkt sofort auf die echten Fenster; Escape stellt den Zustand
// beim Öffnen wieder her.
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    private var window: OverlayWindow?
    private var mapBoxes: [CGDirectDisplayID: MonitorMapBox] = [:]
    private var stageView: StageView?
    private var searchLabel: NSTextField?
    private var assigned: [CGDirectDisplayID: [WinInfo]] = [:]    // Box-Inhalt, dicht, max 4
    private var stage: [WinInfo] = []                             // alle nicht zugeordneten Fenster
    private var displays: [Display] = []
    private var displayColors: [CGDirectDisplayID: NSColor] = [:]
    private var splitMode: [CGDirectDisplayID: Int] = [:]   // Hauptachse
    private var crossMode: [CGDirectDisplayID: Int] = [:]   // Querachse (3er-Stapel / 2x2-Reihen)
    private var allWins: [WinInfo] = []
    private var snapshot: [(ax: AXUIElement, frame: CGRect)] = [] // Zustand beim Öffnen, für Escape
    private var stageMaxWidth: CGFloat = Tuning.stageMaxWidthFloor
    private var search = ""
    private var fixedTopHeight: CGFloat = 0   // alles über der Bühne, für dynamische Fensterhöhe
    private var maxContentHeight: CGFloat = .greatestFiniteMagnitude
    private var innerWidth: CGFloat = 0       // Inhaltsbreite (ohne Padding), fix nach dem Aufbau

    // Hover-/Drag-Zustand.
    private var hoverBoxID: CGDirectDisplayID?
    private var hoverStage = false
    private weak var hoverTile: WindowTileView?
    private var hoverTimer: Timer?
    private weak var hoverSourceTile: WindowTileView?
    private var preview: PreviewPopup?
    private var dragging = false

    // Tastatur-Zustand: genau eine Auswahl (Ring), optional "gegriffen".
    private enum Dir { case left, right, up, down }
    private var selectedID: CGWindowID?
    private var grabbed = false
    private var footerLabel: NSTextField?
    private var cheatsheet: NSView?

    func toggle() { window == nil ? open() : close() }

    func open() {
        ensureScreenRecordingAccess()
        ThumbnailCache.shared.clear()
        let ds = currentDisplays().sorted { $0.full.minX < $1.full.minX }
        guard !ds.isEmpty else { return }
        displays = ds
        displayColors = Dictionary(uniqueKeysWithValues: ds.enumerated().map { ($0.element.id, monitorAccent($0.offset)) })

        let cfg = AppConfig.load()
        allWins = appWM.collectWindows(cfg: cfg)
        snapshot = allWins.map { ($0.ax, $0.bounds) }
        let rank = appWM.zOrderRank()
        let sorted = appWM.perMonitorOrder(displays: ds, wins: allWins, rank: rank)

        // Pro Monitor die kaum überlappenden Vordergrund-Fenster in die Karte,
        // der ganze Rest global (nach Z-Order) auf die Bühne.
        assigned = [:]
        splitMode = [:]
        crossMode = [:]
        search = ""
        var restAll: [WinInfo] = []
        for d in ds {
            let (front, rest) = appWM.selectForeground(sorted[d.id] ?? [])
            // Slots nach realer Bildschirmposition besetzen (links = Slot 0
            // usw.), nicht nach Z-Order — sonst zeigt die Box die Fenster
            // seitenverkehrt zur Realität.
            assigned[d.id] = slotOrderIndices(front.map { $0.bounds }, vertical: d.vertical).map { front[$0] }
            restAll.append(contentsOf: rest)
        }
        stage = restAll.sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }

        buildWindow()
    }

    // Schließen und alle Änderungen behalten; Anordnung für Wake-Restore merken.
    func close() {
        RestoreCenter.shared.bless(allWins)
        teardown()
    }

    // Escape: alle Fenster auf den Zustand beim Öffnen zurücksetzen.
    func revert() {
        for (ax, frame) in snapshot { axSetFrame(ax, frame) }
        RestoreCenter.shared.bless(allWins)
        teardown()
    }

    private func teardown() {
        clearHover()
        hidePreview()
        hoverTimer?.invalidate()
        window?.orderOut(nil)
        window = nil
        mapBoxes = [:]
        stageView = nil
        searchLabel = nil
        footerLabel = nil
        cheatsheet = nil
        splitMode = [:]
        crossMode = [:]
        dragging = false
        grabbed = false
        selectedID = nil
    }

    // MARK: Tastatur

    // Grundregel: Buchstaben gehören dem Filter, Ziffern den Monitoren,
    // Pfeile der Bewegung. Ob Pfeile navigieren oder das Fenster verschieben,
    // entscheidet allein der Greifen-Zustand (sichtbar: orangener Ring).
    func handleKey(_ event: NSEvent) -> Bool {
        if cheatsheet != nil { hideCheatsheet(); return true }
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 36, 76: enterPressed(); return true
        case 53: escPressed(); return true
        case 49: spacePressed(); return true
        case 123: arrow(.left, shift: shift); return true
        case 124: arrow(.right, shift: shift); return true
        case 125: arrow(.down, shift: shift); return true
        case 126: arrow(.up, shift: shift); return true
        case 51:
            if cmd { if let w = selectedInfo() { closeRequested(w) }; return true }
            guard !search.isEmpty else { return false }
            setSearch(String(search.dropLast()))
            return true
        default: break
        }

        guard !cmd, !event.modifierFlags.contains(.control),
              let s = event.charactersIgnoringModifiers, let ch = s.first, s.count == 1
        else { return false }
        if let d = ch.wholeNumberValue { digitPressed(d); return true }
        if ch == "=" { resetRatio(); return true }
        if ch == "?" { showCheatsheet(); return true }
        guard s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
        setSearch(search + s)
        return true
    }

    private func setSearch(_ q: String) {
        search = q
        searchLabel?.stringValue = q.isEmpty ? "Tippen filtert die Bühne" : "⌕ \(q)"
        searchLabel?.textColor = q.isEmpty ? .tertiaryLabelColor : .labelColor
        refreshStage()
        // Ring auf den ersten Treffer — Pfeile wandern dann durch Treffer.
        if !q.isEmpty, let first = stageView?.tiles.first {
            selectedID = first.info.windowID
            updateSelectionUI()
        }
    }

    // MARK: Tastatur-Aktionen

    private func selectedInfo() -> WinInfo? {
        guard let id = selectedID else { return nil }
        for arr in assigned.values { if let w = arr.first(where: { $0.windowID == id }) { return w } }
        return stage.first { $0.windowID == id }
    }

    private func orderedTiles() -> [WindowTileView] {
        var out: [WindowTileView] = []
        for d in displays { out += mapBoxes[d.id]?.tiles ?? [] }
        out += stageView?.tiles ?? []
        return out
    }

    private func enterPressed() {
        if grabbed {
            grabbed = false
            // Serien-Flow: Filter bleibt, Ring springt zum nächsten Treffer.
            if !search.isEmpty, let next = stageView?.tiles.first {
                selectedID = next.info.windowID
            }
            updateSelectionUI()
            updateFooter()
        } else if let w = selectedInfo() {
            axFocus(w.ax)
            close()
        } else {
            close()
        }
    }

    private func escPressed() {
        if grabbed { grabbed = false; updateSelectionUI(); updateFooter(); return }
        if !search.isEmpty { setSearch(""); return }
        revert()
    }

    private func spacePressed() {
        guard let w = selectedInfo(), boxOwner(of: w) != nil else { return }
        grabbed.toggle()
        updateSelectionUI()
        updateFooter()
    }

    // 1-4 = Wurf auf Monitor N (+ automatisch greifen), 0 = zurück auf die Bühne.
    private func digitPressed(_ d: Int) {
        guard let w = selectedInfo() else { return }
        if d == 0 {
            if boxOwner(of: w) != nil { demote(w) }
            grabbed = false
        } else {
            guard d >= 1, d <= displays.count else { return }
            assign(w, to: displays[d - 1].id)
            grabbed = true
        }
        selectedID = w.windowID
        updateSelectionUI()
        updateFooter()
    }

    private func arrow(_ dir: Dir, shift: Bool) {
        if shift, let w = selectedInfo(), let id = boxOwner(of: w) {
            switch dir {
            case .left: stepRatio(id, main: true, up: false)
            case .right: stepRatio(id, main: true, up: true)
            case .up: stepRatio(id, main: false, up: true)
            case .down: stepRatio(id, main: false, up: false)
            }
            return
        }
        if grabbed, let w = selectedInfo(), let id = boxOwner(of: w) {
            moveGrabbed(w, in: id, dir: dir)
            return
        }
        navigate(dir)
    }

    private func navigate(_ dir: Dir) {
        let tiles = orderedTiles()
        guard !tiles.isEmpty else { return }
        guard let cur = tiles.firstIndex(where: { $0.info.windowID == selectedID }) else {
            selectedID = tiles[0].info.windowID
            updateSelectionUI()
            return
        }
        switch dir {
        case .left: selectedID = tiles[(cur - 1 + tiles.count) % tiles.count].info.windowID
        case .right: selectedID = tiles[(cur + 1) % tiles.count].info.windowID
        case .down: if let t = stageView?.tiles.first { selectedID = t.info.windowID }
        case .up: if let t = displays.lazy.compactMap({ self.mapBoxes[$0.id]?.tiles.first }).first { selectedID = t.info.windowID }
        }
        updateSelectionUI()
    }

    // Gegriffenes Fenster verschieben: erst innerhalb der Box (Slot-Tausch in
    // Pfeilrichtung), am Rand darüber hinaus räumlich zum Nachbar-Monitor.
    private func moveGrabbed(_ w: WinInfo, in id: CGDirectDisplayID, dir: Dir) {
        guard let box = mapBoxes[id], let idx = assigned[id]?.firstIndex(where: { $0.windowID == w.windowID }) else { return }
        let cur = box.tiles[idx].frame
        var best: Int?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (i, t) in box.tiles.enumerated() where i != idx {
            let dx = t.frame.midX - cur.midX, dy = t.frame.midY - cur.midY   // Box ist geflippt: +y = runter
            let ok: Bool
            switch dir {
            case .left: ok = dx < -5 && abs(dx) >= abs(dy)
            case .right: ok = dx > 5 && abs(dx) >= abs(dy)
            case .up: ok = dy < -5 && abs(dy) > abs(dx)
            case .down: ok = dy > 5 && abs(dy) > abs(dx)
            }
            if ok, abs(dx) + abs(dy) < bestScore { bestScore = abs(dx) + abs(dy); best = i }
        }
        if let b = best {
            assigned[id]?.swapAt(idx, b)
            retile(id)
        } else if let nid = neighborDisplay(of: id, dir: dir) {
            assign(w, to: nid)
        }
        updateSelectionUI()
    }

    // Räumlicher Nachbar in Pfeilrichtung, nach echter Monitor-Anordnung.
    private func neighborDisplay(of id: CGDirectDisplayID, dir: Dir) -> CGDirectDisplayID? {
        guard let cur = displays.first(where: { $0.id == id }) else { return nil }
        let c = CGPoint(x: cur.full.midX, y: cur.full.midY)
        return displays
            .filter { d in
                guard d.id != id else { return false }
                let dx = d.full.midX - c.x, dy = d.full.midY - c.y
                switch dir {
                case .left: return dx < -10
                case .right: return dx > 10
                case .up: return dy < -10     // Quartz: +y = runter
                case .down: return dy > 10
                }
            }
            .min { hypot($0.full.midX - c.x, $0.full.midY - c.y) < hypot($1.full.midX - c.x, $1.full.midY - c.y) }?
            .id
    }

    private func stepRatio(_ id: CGDirectDisplayID, main: Bool, up: Bool) {
        // Rast-Reihenfolge entlang "erste Gruppe wächst": 33 -> 50 -> 67.
        let order = [2, 0, 1]
        let current = main ? (splitMode[id] ?? 0) : (crossMode[id] ?? 0)
        let i = order.firstIndex(of: current) ?? 1
        let next = order[max(0, min(order.count - 1, i + (up ? 1 : -1)))]
        guard next != current else { return }
        if main { splitMode[id] = next } else { crossMode[id] = next }
        retile(id)
    }

    private func resetRatio() {
        guard let w = selectedInfo(), let id = boxOwner(of: w) else { return }
        splitMode[id] = 0
        crossMode[id] = 0
        retile(id)
    }

    // Fenster per Tastatur einem Monitor zuordnen (wie externer Box-Drop).
    private func assign(_ info: WinInfo, to id: CGDirectDisplayID) {
        let sourceBox = removeEverywhere(info)
        var arr = assigned[id] ?? []
        if arr.count < Tuning.maxAssigned {
            arr.append(info)
        } else {
            stage.insert(arr[arr.count - 1], at: 0)
            arr[arr.count - 1] = info
        }
        assigned[id] = arr
        retile(id)
        if let sourceBox, sourceBox != id { retile(sourceBox) }
        refreshStage()
    }

    // MARK: Tastatur-Visualisierung

    private func updateSelectionUI() {
        for t in orderedTiles() {
            t.setKeyboardSelection(t.info.windowID == selectedID, grabbed: grabbed)
        }
        // Karte: bei aktivem Filter Nicht-Treffer abdunkeln, Treffer leuchten.
        for box in mapBoxes.values {
            for t in box.tiles { t.setDimmed(!search.isEmpty && !matchesSearch(t.info)) }
        }
        // Im Greifen-Modus glüht die Box, die das Fenster gerade hält.
        for (id, box) in mapBoxes {
            let holds = grabbed && (assigned[id]?.contains { $0.windowID == selectedID } ?? false)
            box.setDropTarget(holds)
        }
    }

    private func updateFooter() {
        footerLabel?.stringValue = grabbed
            ? "←↑↓→ Slot/Monitor   ⇧←→ Hauptachse   ⇧↑↓ Querachse   = 50/50   0 Bühne   ↵ ablegen"
            : "tippen filtert   ←→ wählen   ↑↓ Karte/Bühne   1–4 werfen   space greifen   ↵ fokussieren   ⌘⌫ schließen   ? Hilfe"
        footerLabel?.textColor = grabbed ? .systemOrange : .tertiaryLabelColor
    }

    private func showCheatsheet() {
        guard cheatsheet == nil, let root = window?.contentView else { return }
        let lines = [
            "WÄHLEN",
            "tippen  Bühne filtern (Ring springt zum Treffer)",
            "← →  durch alle Fenster   ·   ↑ ↓  Karte ↔ Bühne",
            "1–4  auf Monitor werfen (greift automatisch)",
            "↵  Fenster fokussieren + schließen   ·   ⌘⌫  Fenster schließen",
            "space  greifen/ablegen   ·   esc  Filter leeren / alles zurückrollen",
            "",
            "GREIFEN",
            "← ↑ ↓ →  Slot tauschen, am Rand zum Nachbar-Monitor",
            "⇧← ⇧→  Hauptachse 33·50·67   ·   ⇧↑ ⇧↓  Querachse",
            "=  beide Achsen 50/50   ·   0  zurück auf die Bühne   ·   ↵  ablegen",
        ]
        let panel = FlippedView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.97).cgColor
        panel.layer?.cornerRadius = 16
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        var y: CGFloat = 18
        var maxW: CGFloat = 0
        for line in lines {
            let l = NSTextField(labelWithString: line)
            let isHeader = line == "WÄHLEN" || line == "GREIFEN"
            l.font = isHeader ? .systemFont(ofSize: 12, weight: .bold) : .monospacedSystemFont(ofSize: 12, weight: .regular)
            l.textColor = isHeader ? .systemOrange : .labelColor
            l.sizeToFit()
            l.frame.origin = NSPoint(x: 20, y: y)
            panel.addSubview(l)
            y += line.isEmpty ? 8 : 20
            maxW = max(maxW, l.frame.maxX)
        }
        panel.frame = NSRect(x: (root.bounds.width - maxW - 20) / 2,
                             y: (root.bounds.height - y - 18) / 2,
                             width: maxW + 20, height: y + 18)
        let click = NSClickGestureRecognizer(target: self, action: #selector(cheatsheetClicked))
        panel.addGestureRecognizer(click)
        root.addSubview(panel)
        cheatsheet = panel
    }

    @objc private func cheatsheetClicked() { hideCheatsheet() }

    private func hideCheatsheet() {
        cheatsheet?.removeFromSuperview()
        cheatsheet = nil
    }

    // MARK: Aufbau

    private func buildWindow() {
        let padding: CGFloat = 28
        let sectionGap: CGFloat = 18
        let headerH: CGFloat = 22

        // Das Overlay erscheint zentriert auf dem Bildschirm mit dem
        // Mauszeiger. Breite: so viel wie der Inhalt braucht, höchstens 75 %
        // der Bildschirmbreite — zentriert bleiben die Ränder auf allen
        // Seiten gleich. Höhe folgt dem Inhalt (siehe resizeToFitStage),
        // gedeckelt bei 85 % der Bildschirmhöhe.
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vis = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        maxContentHeight = (vis.height * 0.85).rounded()
        let availW = (vis.width * 0.75).rounded() - padding * 2

        // Karte oben: die ganze reale Anordnung (inkl. Lücken/Versatz) in die
        // Kartenfläche einpassen — wie im Anordnungstab der Systemeinstellungen.
        let unionMinX = displays.map { $0.full.minX }.min() ?? 0
        let unionMinY = displays.map { $0.full.minY }.min() ?? 0
        let unionMaxX = displays.map { $0.full.maxX }.max() ?? 1
        let unionMaxY = displays.map { $0.full.maxY }.max() ?? 1
        let unionW = max(unionMaxX - unionMinX, 1), unionH = max(unionMaxY - unionMinY, 1)
        var scale = min(availW / unionW, maxContentHeight * 0.45 / unionH)
        let maxLongEdge = displays.map { max($0.full.width, $0.full.height) }.max() ?? 1000
        scale = max(scale, Tuning.minBoxLongEdge / maxLongEdge)   // Mindestgröße für Lesbarkeit

        var mapWidth: CGFloat = 0, mapHeight: CGFloat = 0
        for (i, d) in displays.enumerated() {
            let f = NSRect(x: (d.full.minX - unionMinX) * scale, y: (d.full.minY - unionMinY) * scale,
                           width: d.full.width * scale, height: d.full.height * scale)
            let box = MonitorMapBox(display: d, number: i + 1, accent: displayColors[d.id] ?? .controlAccentColor,
                                    frame: f, controller: self)
            box.setAssigned(assigned[d.id] ?? [], split: splitMode[d.id] ?? 0, cross: crossMode[d.id] ?? 0)
            mapBoxes[d.id] = box
            mapWidth = max(mapWidth, f.maxX)
            mapHeight = max(mapHeight, f.maxY)
        }
        // Bühne erst am 75%-Maximum layouten und messen, dann die Breite auf
        // den tatsächlichen Bedarf trimmen und ggf. enger neu umbrechen.
        let stageV = StageView(controller: self)
        stageV.setWindows(stage, filter: search, maxWidth: availW, dot: dotColor)
        innerWidth = min(availW, max(mapWidth, stageV.frame.width, 420))
        if innerWidth < availW {
            stageV.setWindows(stage, filter: search, maxWidth: innerWidth, dot: dotColor)
        }
        stageMaxWidth = innerWidth
        stageView = stageV
        let mapXOffset = ((innerWidth - mapWidth) / 2).rounded()   // Karte horizontal zentrieren

        let contentWidth = innerWidth + padding * 2
        fixedTopHeight = padding + mapHeight + sectionGap + headerH + 10
        let contentHeight = min(fixedTopHeight + stageV.frame.height + 18 + padding, maxContentHeight)
        let contentSize = NSSize(width: contentWidth, height: contentHeight)

        let origin = NSPoint(x: vis.midX - contentSize.width / 2, y: vis.midY - contentSize.height / 2)
        let rect = NSRect(origin: origin, size: contentSize)

        let win = OverlayWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        win.delegate = self

        let bg = OverlayBackgroundView(frame: NSRect(origin: .zero, size: contentSize))
        bg.material = .hudWindow
        bg.state = .active
        // Der Blur-Backdrop ignoriert layer.cornerRadius und würde als volles
        // Rechteck aus den runden Ecken ragen — Rundung muss über maskImage
        // laufen (capInsets lassen die Maske bei Resize sauber mitwachsen).
        bg.maskImage = Self.roundedMask(radius: 24)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 24
        bg.layer?.cornerCurve = .continuous
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        win.contentView = bg

        // Feiner Glanzstreifen oben — deutet Licht von oben an, wie bei den
        // durchscheinenden Systempanels.
        let sheen = NSView(frame: NSRect(x: 24, y: 1, width: contentSize.width - 48, height: 1))
        sheen.wantsLayer = true
        sheen.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        bg.addSubview(sheen)

        for box in mapBoxes.values {
            box.frame.origin.x += padding + mapXOffset
            box.frame.origin.y += padding
            bg.addSubview(box)
        }

        // Kopfzeile der Bühne: Titel links, Suche rechts, Trennlinie darüber.
        let headerY = padding + mapHeight + sectionGap
        let divider = NSBox(frame: NSRect(x: padding, y: headerY - 9, width: contentWidth - padding * 2, height: 1))
        divider.boxType = .custom
        divider.fillColor = NSColor.white.withAlphaComponent(0.1)
        divider.borderWidth = 0
        bg.addSubview(divider)

        let title = NSTextField(labelWithString: "Hintergrund · nach App")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: padding, y: headerY, width: 240, height: 17)
        bg.addSubview(title)

        let sl = NSTextField(labelWithString: "Tippen filtert die Bühne")
        sl.font = .systemFont(ofSize: 13)
        sl.textColor = .tertiaryLabelColor
        sl.alignment = .right
        sl.frame = NSRect(x: contentWidth - padding - 280, y: headerY, width: 280, height: 17)
        searchLabel = sl
        bg.addSubview(sl)

        stageV.frame.origin = NSPoint(x: padding + ((innerWidth - stageV.frame.width) / 2).rounded(),
                                      y: headerY + headerH + 10)
        bg.addSubview(stageV)

        // Kontextabhängige Tasten-Hinweise am unteren Rand; klebt per
        // Autoresizing an der Unterkante, wenn die Fensterhöhe mitwächst.
        let footer = NSTextField(labelWithString: "")
        footer.font = .systemFont(ofSize: 11)
        footer.alignment = .center
        footer.lineBreakMode = .byTruncatingTail
        footer.frame = NSRect(x: padding, y: contentSize.height - 22, width: contentWidth - padding * 2, height: 15)
        footer.autoresizingMask = [.minYMargin]
        footerLabel = footer
        bg.addSubview(footer)
        updateFooter()

        // Start-Auswahl: erstes Karten-Fenster, sonst erste Bühnen-Kachel.
        selectedID = (displays.compactMap { mapBoxes[$0.id]?.tiles.first }.first ?? stageV.tiles.first)?.info.windowID
        updateSelectionUI()

        window = win
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // 9-Patch-Maske für die Effect-View: Ecken fix, Mitte dehnbar.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    // Farbpunkt = Monitor, auf dem das Fenster aktuell liegt.
    private func dotColor(_ w: WinInfo) -> NSColor? {
        guard let id = displayID(containing: CGPoint(x: w.bounds.midX, y: w.bounds.midY), in: displays) else { return nil }
        return displayColors[id]
    }

    // MARK: Treffer-Ermittlung

    // Bei überlappenden Hit-Areas (aneinandergrenzende Boxen, ±14pt Rand)
    // entscheidet die Distanz zum Box-Mittelpunkt — nicht die zufällige
    // Dictionary-Reihenfolge.
    private func nearestBoxID(at p: NSPoint) -> CGDirectDisplayID? {
        mapBoxes
            .filter { $0.value.hitAreaInWindow.contains(p) }
            .min { distToCenter($0.value.hitAreaInWindow, p) < distToCenter($1.value.hitAreaInWindow, p) }?
            .key
    }

    private func distToCenter(_ r: NSRect, _ p: NSPoint) -> CGFloat {
        hypot(r.midX - p.x, r.midY - p.y)
    }

    private func boxOwner(of info: WinInfo) -> CGDirectDisplayID? {
        assigned.first { $0.value.contains { $0.windowID == info.windowID } }?.key
    }

    // MARK: Hover & Vorschau

    func tileHoverBegan(_ tile: WindowTileView) {
        guard !dragging else { return }
        hoverSourceTile = tile
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Tuning.hoverPreviewDelay, repeats: false) { [weak self] _ in
            self?.showPreview()
        }
    }

    func tileHoverEnded(_ tile: WindowTileView) {
        guard hoverSourceTile === tile else { return }
        hoverTimer?.invalidate()
        hoverSourceTile = nil
        hidePreview()
    }

    private func showPreview() {
        guard !dragging, let tile = hoverSourceTile, let root = window?.contentView else { return }
        hidePreview()
        let popup = PreviewPopup(info: tile.info, image: ThumbnailCache.shared.image(for: tile.info.windowID))
        let tf = tile.convert(tile.bounds, to: root)
        var x = tf.midX - popup.frame.width / 2
        x = max(8, min(x, root.bounds.width - popup.frame.width - 8))
        var y = tf.minY - popup.frame.height - 10          // bevorzugt über der Kachel
        if y < 8 { y = tf.maxY + 10 }                      // sonst darunter
        popup.frame.origin = NSPoint(x: x, y: y)
        popup.alphaValue = 0
        root.addSubview(popup)
        preview = popup
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            popup.animator().alphaValue = 1
        }
    }

    private func hidePreview() {
        preview?.removeFromSuperview()
        preview = nil
    }

    // MARK: Drag-Feedback

    func dragBegan() {
        dragging = true
        hoverTimer?.invalidate()
        hidePreview()
    }

    // Live-Feedback während des Drags: Ziel-Box/Bühne bekommt einen
    // Akzentrahmen; würde der Drop eine konkrete Kachel ersetzen/tauschen,
    // wird zusätzlich diese markiert.
    func dragHover(_ info: WinInfo, at p: NSPoint) {
        let boxID = nearestBoxID(at: p)
        let stageOn = boxID == nil && boxOwner(of: info) != nil
            && stageView?.hitAreaInWindow.contains(p) == true

        var candidate: WindowTileView?
        if let id = boxID, let box = mapBoxes[id] {
            let arr = assigned[id] ?? []
            let isInternal = arr.contains { $0.windowID == info.windowID }
            let wouldReplace = isInternal || arr.count >= Tuning.maxAssigned
            if wouldReplace, let idx = box.dropSlot(atWindowPoint: p),
               arr.indices.contains(idx), arr[idx].windowID != info.windowID {
                candidate = box.tiles[idx]
            }
        }
        setHover(box: boxID, stage: stageOn, tile: candidate)
    }

    func groupDragHover(at p: NSPoint) {
        setHover(box: nearestBoxID(at: p), stage: false, tile: nil)
    }

    private func setHover(box: CGDirectDisplayID?, stage stageOn: Bool, tile: WindowTileView?) {
        if hoverBoxID != box {
            hoverBoxID.flatMap { mapBoxes[$0] }?.setDropTarget(false)
            box.flatMap { mapBoxes[$0] }?.setDropTarget(true)
            hoverBoxID = box
        }
        if hoverStage != stageOn {
            stageView?.setDropTarget(stageOn)
            hoverStage = stageOn
        }
        if hoverTile !== tile {
            hoverTile?.setDropCandidate(false)
            tile?.setDropCandidate(true)
            hoverTile = tile
        }
    }

    private func clearHover() { setHover(box: nil, stage: false, tile: nil) }

    // MARK: Drop

    // Drop auf eine Box = zuordnen (anhängen solange Platz, sonst gezielt
    // ersetzen; innerhalb derselben Box: Plätze tauschen). Drop außerhalb der
    // Boxen = aus der Box zurück auf die Bühne. Wirkt sofort auf die echten
    // Fenster.
    func dragEnded(_ info: WinInfo, at p: NSPoint) {
        clearHover()
        dragging = false
        if let id = nearestBoxID(at: p) {
            dropOnBox(info, onto: id, at: p)
        } else if boxOwner(of: info) != nil {
            demote(info)
        }
    }

    // Gruppenkopf auf eine Box gezogen: die ersten zwei Fenster der App landen
    // dort als Split, der bisherige Box-Inhalt geht zurück auf die Bühne.
    func groupDragEnded(_ app: String, at p: NSPoint) {
        clearHover()
        dragging = false
        guard let id = nearestBoxID(at: p) else { return }
        let candidates = stage.filter { $0.app == app }
        guard !candidates.isEmpty else { return }
        let take = Array(candidates.prefix(2))
        stage.removeAll { w in take.contains { $0.windowID == w.windowID } }
        stage.insert(contentsOf: assigned[id] ?? [], at: 0)
        assigned[id] = take
        splitMode[id] = 0
        crossMode[id] = 0
        retile(id)
        refreshStage()
        take.forEach { pulseTile($0, in: id) }
    }

    private func dropOnBox(_ info: WinInfo, onto id: CGDirectDisplayID, at p: NSPoint) {
        let hitIdx = mapBoxes[id]?.dropSlot(atWindowPoint: p)
        var arr = assigned[id] ?? []

        if let from = arr.firstIndex(where: { $0.windowID == info.windowID }) {
            // Innerhalb derselben Box: Plätze tauschen.
            guard let hit = hitIdx, hit != from else { return }
            arr.swapAt(from, hit)
            assigned[id] = arr
            retile(id)
        } else {
            let sourceBox = removeEverywhere(info)
            arr = assigned[id] ?? []
            if arr.count < Tuning.maxAssigned {
                arr.append(info)   // von außen: anhängen, Raster wächst
            } else {
                let slot = hitIdx ?? arr.count - 1
                stage.insert(arr[slot], at: 0)
                arr[slot] = info   // Box voll: gezielt ersetzen, Verdrängtes auf die Bühne
            }
            assigned[id] = arr
            retile(id)
            if let sourceBox, sourceBox != id { retile(sourceBox) }
            refreshStage()
        }
        pulseTile(info, in: id)
    }

    private func demote(_ info: WinInfo) {
        guard let sourceBox = boxOwner(of: info) else { return }
        assigned[sourceBox]?.removeAll { $0.windowID == info.windowID }
        stage.append(info)
        retile(sourceBox)
        refreshStage()
        (stageView?.tiles.first { $0.info.windowID == info.windowID })?.pulse()
    }

    // Entfernt das Fenster überall und liefert die Box zurück, in der es war.
    @discardableResult
    private func removeEverywhere(_ info: WinInfo) -> CGDirectDisplayID? {
        stage.removeAll { $0.windowID == info.windowID }
        let sourceBox = boxOwner(of: info)
        if let sourceBox { assigned[sourceBox]?.removeAll { $0.windowID == info.windowID } }
        return sourceBox
    }

    // MARK: Klicks

    // Klick auf eine Bühnen-Kachel: Fenster nach vorn holen und Overlay
    // schließen (Switcher-Verhalten). Klick auf eine Box-Kachel: ein Prinzip
    // für alle Layouts — jeder Klick macht das angeklickte Fenster
    // prominenter, ist es schon maximal, setzt der Klick auf ausgewogen
    // zurück. Stufen: 1. eigene Seite groß (Hauptachse), 2. innerhalb der
    // Seite groß (Querachse, nur 3er/2x2), 3. alles zurück auf 50/50.
    func tileClicked(_ info: WinInfo) {
        selectedID = info.windowID   // Maus-Klick zieht auch den Tastatur-Ring mit
        if stage.contains(where: { $0.windowID == info.windowID }) {
            axFocus(info.ax)
            close()
            return
        }
        for (id, arr) in assigned {
            guard arr.count >= 2, let idx = arr.firstIndex(where: { $0.windowID == info.windowID }) else { continue }
            // Hauptachsen-Gruppe: 2er/3er Slot 0 vs. Rest, 2x2 linke vs.
            // rechte Spalte (zeilen-major: gerade Slots = links).
            let mainFavor = (arr.count == 4 ? idx % 2 == 0 : idx == 0) ? 1 : 2
            // Querachsen-Gruppe: 3er-Stapel Slot 1 vs. 2, 2x2 obere vs.
            // untere Reihe. Das große Fenster im 3er hat keine Querachse.
            let crossFavor: Int? = switch arr.count {
            case 3 where idx > 0: idx == 1 ? 1 : 2
            case 4: idx < 2 ? 1 : 2
            default: nil
            }

            if (splitMode[id] ?? 0) != mainFavor {
                splitMode[id] = mainFavor
            } else if let crossFavor, (crossMode[id] ?? 0) != crossFavor {
                crossMode[id] = crossFavor
            } else {
                splitMode[id] = 0
                crossMode[id] = 0
            }
            retile(id)
            return
        }
    }

    // Fugen-Drag in einer Box: eingerastete Stufe (33/50/67) für Haupt- bzw.
    // Querachse übernehmen; kachelt beim Stufenwechsel live die echten Fenster.
    func seamChanged(_ id: CGDirectDisplayID, kind: SeamKind, mode: Int) {
        switch kind {
        case .main:
            guard (splitMode[id] ?? 0) != mode else { return }
            splitMode[id] = mode
        case .cross:
            guard (crossMode[id] ?? 0) != mode else { return }
            crossMode[id] = mode
        }
        retile(id)
    }

    // X-Knopf einer Kachel: echtes Fenster schließen (drückt dessen roten
    // Schließen-Knopf — die App darf also noch "Sichern?" fragen) und aus
    // Karte/Bühne entfernen; verbleibende Box-Fenster ordnen sich neu.
    func closeRequested(_ info: WinInfo) {
        hidePreview()
        axClose(info.ax)
        allWins.removeAll { $0.windowID == info.windowID }
        let sourceBox = removeEverywhere(info)
        if let sourceBox { retile(sourceBox) }
        refreshStage()
        // Das Schließen läuft asynchron, und manche Apps ordnen danach ihre
        // übrigen Fenster selbst um — der sofortige Bounds-Readback oben ist
        // dann schon wieder veraltet. Nach kurzer Frist nochmal kacheln und
        // den echten Zustand in die Vorschau lesen.
        guard let sourceBox else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.window != nil else { return }
            self.retile(sourceBox)
        }
    }

    // MARK: Anwenden

    // Wendet den aktuellen Box-Inhalt eines Monitors sofort auf die echten
    // Fenster an und liest die tatsächlichen Bounds zurück.
    private func retile(_ id: CGDirectDisplayID) {
        guard let d = displays.first(where: { $0.id == id }) else { return }
        let wins = assigned[id] ?? []
        if !wins.isEmpty {
            appWM.tileGroup(wins.map { $0.ax }, on: d, split: splitMode[id] ?? 0, cross: crossMode[id] ?? 0)
            let fresh = wins.map { w in axFrame(w.ax).map { w.with(bounds: $0) } ?? w }
            // Thumbnails umgroßter Fenster sofort verwerfen — schnelle Apps
            // haben ihre neuen Bounds schon jetzt, und syncBounds würde die
            // Invalidierung dann nicht mehr auslösen.
            for (f, w) in zip(fresh, wins) where f.bounds.size != w.bounds.size {
                ThumbnailCache.shared.remove(f.windowID)
            }
            assigned[id] = fresh
        }
        mapBoxes[id]?.setAssigned(assigned[id] ?? [], split: splitMode[id] ?? 0, cross: crossMode[id] ?? 0)
        updateSelectionUI()
        // Manche Apps (v.a. Electron wie Teams) wenden das Setzen verzögert
        // an — der sofortige Readback zeigt dann noch alte Bounds. Später den
        // echten Zustand nachlesen (nur lesen, nicht erneut setzen) und die
        // Vorschau korrigieren; zweiter Durchgang für ganz träge Kandidaten.
        for delay in [0.4, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.window != nil else { return }
                self.syncBounds(id)
            }
        }
    }

    // Bounds der zugeordneten Fenster aus der Realität nachlesen und die
    // Box-Vorschau aktualisieren — ohne Frames neu zu setzen.
    private func syncBounds(_ id: CGDirectDisplayID) {
        let wins = assigned[id] ?? []
        guard !wins.isEmpty else { return }
        let fresh = wins.map { w in axFrame(w.ax).map { w.with(bounds: $0) } ?? w }
        let changed = zip(fresh, wins).filter { $0.bounds != $1.bounds }.map { $0.0.windowID }
        guard !changed.isEmpty else { return }
        // Alte Thumbnails der umgroßten Fenster verwerfen — sonst zeigt die
        // neue Kachel den Abzug von VOR dem Kacheln (falsche Größe/Proportion).
        changed.forEach { ThumbnailCache.shared.remove($0) }
        assigned[id] = fresh
        mapBoxes[id]?.setAssigned(fresh, split: splitMode[id] ?? 0, cross: crossMode[id] ?? 0)
        updateSelectionUI()
    }

    private func matchesSearch(_ w: WinInfo) -> Bool {
        search.isEmpty || w.app.localizedCaseInsensitiveContains(search)
            || w.title.localizedCaseInsensitiveContains(search)
    }

    private func refreshStage() {
        guard let stageV = stageView else { return }
        // Bei aktivem Filter wird die Bühne zur Treffer-Liste über ALLES:
        // passende, bereits zugeordnete Fenster erscheinen zusätzlich als
        // Duplikat (gleiche WinInfo — Ziffer/Drag/✕ wirken identisch), der
        // Farbpunkt zeigt ihren Monitor.
        var list = stage
        if !search.isEmpty {
            list += displays.flatMap { assigned[$0.id] ?? [] }.filter(matchesSearch)
        }
        stageV.setWindows(list, filter: search, maxWidth: stageMaxWidth, dot: dotColor)
        stageV.frame.origin.x = 28 + ((innerWidth - stageV.frame.width) / 2).rounded()
        resizeToFitStage()
        updateSelectionUI()
    }

    // Fensterhöhe folgt dem Bühnen-Inhalt (Oberkante bleibt fix) — kein toter
    // Leerraum unter der Bühne, kein Abschneiden nach Demotes.
    private func resizeToFitStage() {
        guard let win = window, let stageV = stageView else { return }
        let newH = min(fixedTopHeight + stageV.frame.height + 18 + 28, maxContentHeight)
        guard abs(win.frame.height - newH) > 1 else { return }
        var f = win.frame
        let topY = f.maxY
        f.size.height = newH
        f.origin.y = topY - newH
        win.setFrame(f, display: true)
        win.invalidateShadow()
    }

    private func pulseTile(_ info: WinInfo, in id: CGDirectDisplayID) {
        (mapBoxes[id]?.tiles.first { $0.info.windowID == info.windowID })?.pulse()
        (stageView?.tiles.first { $0.info.windowID == info.windowID })?.pulse()
    }
}
