import AppKit

// Randloses Fenster, das trotzdem Key werden kann. Tastatur geht komplett an
// den Controller: Enter/Klick positioniert (Loop-Modus), Escape rollt zurück
// bzw. verlässt den Loop-Modus, jedes andere Zeichen filtert das Podium.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if !OverlayController.shared.handleKey(event) { super.keyDown(with: event) }
    }
    // Nötig, damit der Loop-Modus erkennt, wenn zwei Pfeiltasten gleichzeitig
    // gehalten werden (z. B. ← + ↑ fährt die Ecke oben-links an).
    override func keyUp(with event: NSEvent) {
        OverlayController.shared.handleKeyUp(event)
        super.keyUp(with: event)
    }
}

final class OverlayBackgroundView: FlippedVisualEffectView {
    override func mouseDown(with event: NSEvent) { OverlayController.shared.close() }
}

// Content-View der Klick-Fang-Fenster aus setupStageClickCatchers() — reine
// Weiterleitung, kein eigener Zustand (siehe dortiger Kommentar fürs Warum).
private final class StageClickCatcherView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Podium: alle verwalteten Fenster an einer Stelle, gruppiert nach App.
// Auswahl per Tastatur/Suche/Klick, Enter oder Klick öffnet für das gewählte
// Fenster den Loop-Modus (Ring-Menü) zur Positionierung — GENAU EIN Fenster
// pro Aktion, keine Karte/Box-Anordnung mehr. Jede Aktion wirkt sofort auf die
// echten Fenster; Escape auf dem Podium stellt den Zustand beim Öffnen wieder her.
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    private var window: OverlayWindow?
    private var stageView: StageView?
    private var searchLabel: NSTextField?
    // Z-Order aller Fenster beim Öffnen — sortiert das Podium stabil.
    private var zRank: [CGWindowID: Int] = [:]
    private var displays: [Display] = []
    private var displayColors: [CGDirectDisplayID: NSColor] = [:]
    private var allWins: [WinInfo] = []
    private var cfg = AppConfig()
    private var snapshot: [(ax: AXUIElement, frame: CGRect, minimized: Bool)] = [] // Zustand beim Öffnen, für Escape
    // Apps, die diese Sitzung per Loop-Aktion ausgeblendet wurden — Escape
    // muss sie wieder einblenden (Frames allein reichen nicht für "Zustand
    // beim Öffnen wiederherstellen").
    private var hiddenPids: Set<pid_t> = []
    // Zuletzt per Loop-Aktion positioniertes Fenster — bekommt beim
    // bewussten Schließen der Sitzung den Fokus (wer platziert, will benutzen).
    private var lastCommitted: WinInfo?
    private var stageMaxWidth: CGFloat = Tuning.stageMaxWidthFloor
    private var search = ""
    private var fixedTopHeight: CGFloat = 0   // alles über dem Podium, für dynamische Fensterhöhe
    private var maxContentHeight: CGFloat = .greatestFiniteMagnitude
    private var innerWidth: CGFloat = 0       // Inhaltsbreite (ohne Padding), fix nach dem Aufbau

    // Hover-Zustand für die Thumbnail-Großvorschau (unabhängig vom Loop-Modus).
    private weak var hoverSourceTile: WindowTileView?
    private var hoverTimer: Timer?
    private var preview: PreviewPopup?

    // Dritter Auswahlweg (neben Pfeiltasten/Suche): Fenster unter dem
    // Mauszeiger auf den echten Monitoren, siehe stageMouseMoved().
    private var stageMouseTimer: Timer?
    private var lastPolledStageMouseLocation: NSPoint?
    // Ein Klick-Fang-Fenster pro Monitor, siehe setupStageClickCatchers().
    private var stageClickCatchers: [NSWindow] = []

    // Tastatur-Zustand: genau eine Auswahl auf dem Podium.
    private enum Dir { case left, right, up, down }
    private var selectedID: CGWindowID?
    private var footerLabel: NSTextField?
    private var cheatsheet: NSView?

    // Echte Markierung des gewählten Fensters auf seinem Monitor + kurzes
    // Vorziehen, solange es gewählt ist (rutscht beim Abwählen wieder auf
    // seinen ursprünglichen Platz zurück — siehe unraiseIfNeeded).
    private var selectionHighlight: LoopPreviewPanel?
    private var raisedForSelection: CGWindowID?

    // Loop-Modus: Ring-Menü (eigenes schwebendes Panel, folgt der Maus über
    // alle Monitore) + nicht-destruktive Vorschau fürs jeweils ausgewählte
    // Fenster. Die Mausposition wird global beobachtet (wie DragSnap) statt
    // lokal auf dem Ring, weil der Zeiger die meiste Zeit gar nicht über dem
    // Ring liegt — er darf irgendwo im passenden Quadranten sein.
    // Fenster, die diese Sitzung tatsächlich per Loop-Aktion angefasst
    // wurden — steuert autoMinimize beim Schließen.
    private var loopMenuView: LoopMenuView?
    private var loopRingPanel: LoopRingPanel?
    // Ein Panel pro Rechteck der aktuellen Vorschau (gezogenes Fenster PLUS
    // ggf. Nachbarn bei fillMode != .solo) — wächst/schrumpft mit der Anzahl.
    private var previewPanels: [LoopPreviewPanel] = []
    // Plain .mouseMoved-Events werden vom System nur erzeugt, wenn ein
    // Fenster darunter das explizit anfordert — ein globaler NSEvent-Monitor
    // dafür feuert deshalb oft gar nicht, sobald der Zeiger über einem
    // fremden Fenster/Monitor steht. Ein Poll-Timer auf NSEvent.mouseLocation
    // ist dagegen immer zuverlässig (öffentliche API, kein Event-Empfang nötig).
    private var loopMouseTimer: Timer?
    // Nur reagieren, wenn sich die Maus seit dem letzten Tick TATSÄCHLICH
    // bewegt hat — sonst überschreibt der 60Hz-Poll ständig jede Tastatur-
    // Auswahl (M/U/Z/…) im nächsten Tick wieder mit der (unveränderten)
    // Maus-Zone, noch bevor man das Ergebnis überhaupt sieht.
    private var lastPolledMouseLocation: NSPoint?
    private var loopTarget: WinInfo?
    private var loopAnchorDisplay: Display?   // Monitor, auf dem der Ring aktuell "sitzt"
    private var touchedIDs: Set<CGWindowID> = []
    // Häkchen fürs Auto-Arrange (Leertaste/Klick) — geordnet nach Ankreuz-
    // Reihenfolge, damit autoArrange() beim Verteilen eine stabile,
    // nachvollziehbare Reihenfolge über die Monitore hinweg hat.
    private var checked: [CGWindowID] = []
    private var stashed: [CGWindowID: (frame: CGRect, edge: BentoZone)] = [:]
    private let monitorBadges = MonitorBadgeSet()

    func toggle() { window == nil ? open() : close() }

    // Fokussieren + Overlay schließen — der klassische Switcher-Pfad. Kein
    // autoMinimize: ein Fokuswechsel ist kein "Sitzung fertig, aufräumen".
    private func focusAndClose(_ info: WinInfo) {
        revive(info)
        axFocus(info.ax)
        close(applyAutoMinimize: false)
    }

    func open() {
        ensureScreenRecordingAccess()
        ThumbnailCache.shared.clear()
        let ds = currentDisplays().sorted { $0.full.minX < $1.full.minX }
        guard !ds.isEmpty else { return }
        displays = ds
        displayColors = Dictionary(uniqueKeysWithValues: ds.enumerated().map { ($0.element.id, monitorAccent($0.offset)) })
        monitorBadges.show(displays: ds)

        cfg = AppConfig.load()
        allWins = appWM.collectWindows(cfg: cfg)
        snapshot = allWins.map { ($0.ax, $0.bounds, $0.minimized) }
        zRank = appWM.zOrderRank()
        search = ""
        touchedIDs = []
        hiddenPids = []
        checked = []

        // Verbundene Ränder auch für Fenster anmelden, die von Hand (nicht
        // über Podium) nebeneinandergeschoben wurden — sobald das Podium
        // einmal offen war, kennt LinkedEdges sie und kann bei künftigem
        // Resize live erkennen, ob sie wirklich angrenzen.
        let tileable = allWins.filter { !isFloatingWin($0) && !$0.minimized }
        LinkedEdges.shared.track(tileable.map { $0.ax })

        buildWindow()
    }

    // Schließen und alle Änderungen behalten; Anordnung für Wake-Restore merken.
    // applyAutoMinimize=false für unfreiwillige Schließungen (Fokusverlust an
    // Spotlight/System-Dialog/Fremd-Klick) — sonst minimiert jeder kurze
    // Fokusverlust bei aktivem autoMinimize den halben Desktop.
    func close(applyAutoMinimize: Bool = true) {
        // Option: alle Fenster minimieren, die diese Sitzung NICHT per
        // Loop-Aktion angefasst wurden — floatende ausgenommen.
        if applyAutoMinimize, SettingsStore.shared.autoMinimize {
            for w in allWins where !touchedIDs.contains(w.windowID) && !isFloatingWin(w) && !w.minimized {
                axSetMinimized(w.ax, true)
            }
        }
        // Nur beim BEWUSSTEN Schließen (nicht bei Fokusverlust — da hat der
        // Nutzer den Fokus gerade selbst woandershin gelegt): das zuletzt
        // positionierte Fenster bekommt den Fokus.
        if applyAutoMinimize, let w = lastCommitted { axFocus(w.ax) }
        RestoreCenter.shared.bless(allWins)
        teardown()
    }

    // Escape auf dem Podium: alle Fenster auf den Zustand beim Öffnen
    // zurücksetzen — Frames UND Sichtbarkeit (per Loop ausgeblendete Apps
    // wieder einblenden, unfreiwillig Minimiertes zurückholen).
    func revert() {
        for pid in hiddenPids { NSRunningApplication(processIdentifier: pid)?.unhide() }
        for (ax, frame, wasMinimized) in snapshot {
            if !wasMinimized, axBool(ax, kAXMinimizedAttribute as String) {
                axSetMinimized(ax, false)
            }
            axSetFrame(ax, frame)
        }
        RestoreCenter.shared.bless(allWins)
        teardown()
    }

    private func teardown() {
        hoverTimer?.invalidate()
        stageMouseTimer?.invalidate()
        stageMouseTimer = nil
        lastPolledStageMouseLocation = nil
        stageClickCatchers.forEach { $0.orderOut(nil) }
        stageClickCatchers = []
        hidePreview()
        selectionHighlight?.hide()
        selectionHighlight = nil
        monitorBadges.hide()
        unraiseIfNeeded()
        stopLoopTracking()
        loopMenuView = nil
        window?.orderOut(nil)
        window = nil
        stageView = nil
        searchLabel = nil
        footerLabel = nil
        cheatsheet = nil
        selectedID = nil
        touchedIDs = []
        hiddenPids = []
        checked = []
        lastCommitted = nil
        // `stashed` bewusst NICHT leeren: gestashte Fenster hängen sonst nach
        // Overlay-Schließen für immer offscreen (⇧S fände nichts mehr) —
        // App-Lebenszeit-Gedächtnis wie WindowHistory.
    }

    // MARK: Tastatur

    // Grundregel: Buchstaben gehören dem Filter, Pfeile der Bewegung. Ist der
    // Loop-Modus offen, geht die Tastatur zuerst an ihn (eigene Legende).
    func handleKey(_ event: NSEvent) -> Bool {
        if cheatsheet != nil { hideCheatsheet(); return true }
        if let menu = loopMenuView { return menu.handleKey(event) }
        let cmd = event.modifierFlags.contains(.command)
        return dispatchKeyDown(event, cmd: cmd)
    }

    // Nur im Loop-Modus relevant (zwei Pfeiltasten gleichzeitig = Ecke).
    func handleKeyUp(_ event: NSEvent) {
        loopMenuView?.handleKeyUp(event)
    }

    private func dispatchKeyDown(_ event: NSEvent, cmd: Bool) -> Bool {
        switch event.keyCode {
        case 36, 76: enterPressed(cmd: cmd); return true
        case 53: escPressed(); return true
        case 49: spacePressed(); return true
        case 123: navigate(.left); return true
        case 124: navigate(.right); return true
        case 125: navigate(.down); return true
        case 126: navigate(.up); return true
        case 51:
            if cmd { if let w = selectedInfo() { closeRequested(w) }; return true }   // ⌘⌫ = Fenster schließen
            guard !search.isEmpty else { return false }
            setSearch(String(search.dropLast()))
            return true
        default: break
        }

        // Fenster-Aktionen direkt auf dem Podium (ohne Loop-Modus-Umweg).
        if cmd, let s = event.charactersIgnoringModifiers?.lowercased() {
            switch s {
            case "m": if let w = selectedInfo() { minimizeFromStage(w) }; return true
            case "h": if let w = selectedInfo() { hideFromStage(w) }; return true
            default: break
            }
        }

        guard !cmd, !event.modifierFlags.contains(.control),
              let s = event.charactersIgnoringModifiers, let ch = s.first, s.count == 1
        else { return false }
        if ch == "?" { showCheatsheet(); return true }
        guard s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
        setSearch(search + s)
        return true
    }

    private func setSearch(_ q: String) {
        search = q
        searchLabel?.stringValue = q.isEmpty ? "Tippen filtert das Podium" : "⌕ \(q)"
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
        return allWins.first { $0.windowID == id }
    }

    // Sind ≥2 Fenster angekreuzt, gewinnt Auto-Arrange über das normale
    // Enter-Verhalten — ein einzelnes Häkchen (oder gar keins) ändert nichts
    // am bestehenden Interaktionsmodell.
    //
    // Interaktionsmodell per Einstellung (stageEnterSwitches):
    // Aus (Default): Enter/Klick = Loop-Modus, ⌘↵/Doppelklick = nur wechseln.
    // An: Enter/Klick = nur wechseln (klassischer Switcher), Leertaste/⌘↵ = Loop-Modus.
    private func enterPressed(cmd: Bool) {
        if checked.count >= 2 {
            autoArrange(checked.compactMap { id in allWins.first { $0.windowID == id } })
            return
        }
        guard let w = selectedInfo() else { return }
        let switchFirst = SettingsStore.shared.stageEnterSwitches
        let wantsSwitch = switchFirst ? !cmd : cmd
        if wantsSwitch {
            focusAndClose(w)
        } else {
            openLoopMode(for: w)
        }
    }

    // Leertaste toggelt das Auto-Arrange-Häkchen des tastatur-markierten
    // Fensters — ersetzt das bisherige Doppel-Verhalten (Loop-Modus-Zugang
    // im Switcher-Modus / Leerzeichen im Filter) vollständig.
    private func spacePressed() {
        guard let w = selectedInfo() else { return }
        tileCheckToggled(w)
    }

    // Auch per Mausklick auf die Checkbox einer Kachel erreichbar.
    func tileCheckToggled(_ info: WinInfo) {
        if let idx = checked.firstIndex(of: info.windowID) {
            checked.remove(at: idx)
        } else {
            checked.append(info.windowID)
        }
        updateSelectionUI()
    }

    // Verteilt die angekreuzten Fenster proportional zur Monitorfläche auf
    // alle aktuellen Displays (größere Monitore bekommen mehr Fenster), pro
    // Monitor dann als möglichst quadratisches Auto-Raster (LoopEngine.autoGrid).
    // Fenster, deren App in einer Settings-Gruppe (cfg.groups) liegt, werden
    // dafür zu EINEM Bucket zusammengefasst und landen garantiert auf
    // demselben Monitor — LoopEngine.assignBucketsToDisplays sorgt dafür,
    // dass kein Bucket aufgeteilt wird, auch wenn er dafür ein Display
    // relativ zu dessen Flächenanteil überbucht. Reicht der Platz auf einem
    // Monitor nicht für alle ihm zugeteilten Fenster in Mindestgröße, lässt
    // autoGrid die überzähligen bewusst unangetastet — bei Gruppen ist ein
    // solches Überbuchen wahrscheinlicher als bei reiner Flächen-Verteilung,
    // das ist der bewusste Kompromiss dafür, dass Gruppen nie aufgesplittet werden.
    private func autoArrange(_ infos: [WinInfo]) {
        guard !infos.isEmpty else { return }
        LinkedEdges.shared.suppress()

        // Buckets: Gruppen-Fenster kollabieren in EINEN Bucket am
        // Erstauftreten in der Ankreuz-Reihenfolge (infos ist bereits in
        // checked-Reihenfolge); ungruppierte Fenster bleiben Singleton-
        // Buckets. cfg.groups selbst wird nur für die Name->Gruppenname-
        // Rückwärtssuche durchlaufen (Namenskollision zwischen Gruppen:
        // letzter Dictionary-Eintrag gewinnt) — niemals für Bucket-Reihenfolge.
        var groupNameForApp: [String: String] = [:]
        for (gname, apps) in cfg.groups { for app in apps { groupNameForApp[app] = gname } }
        var buckets: [[WinInfo]] = []
        var bucketIndexForGroup: [String: Int] = [:]
        for info in infos {
            if let gname = groupNameForApp[info.app] {
                if let idx = bucketIndexForGroup[gname] {
                    buckets[idx].append(info)
                } else {
                    bucketIndexForGroup[gname] = buckets.count
                    buckets.append([info])
                }
            } else {
                buckets.append([info])
            }
        }

        let sortedDisplays = displays.sorted { $0.visible.width * $0.visible.height > $1.visible.width * $1.visible.height }
        let weights = sortedDisplays.map { $0.visible.width * $0.visible.height }
        let targetCounts = LoopEngine.allocateByWeight(total: infos.count, weights: weights)
        let bucketDisplayIdx = LoopEngine.assignBucketsToDisplays(bucketSizes: buckets.map { $0.count }, targetCounts: targetCounts)

        var perDisplay: [[WinInfo]] = Array(repeating: [], count: sortedDisplays.count)
        for (bucket, dIdx) in zip(buckets, bucketDisplayIdx) { perDisplay[dIdx].append(contentsOf: bucket) }

        for (display, group) in zip(sortedDisplays, perDisplay) {
            guard !group.isEmpty else { continue }
            let frames = LoopEngine.autoGrid(count: group.count, in: display.visible)
            for (info, frame) in zip(group, frames) {
                if let cur = axFrame(info.ax) { WindowHistory.shared.recordIfNeeded(info.windowID, currentFrame: cur) }
                axSetFrame(info.ax, frame)
                axRaise(info.ax)
                touchedIDs.insert(info.windowID)
            }
        }
        checked = []
        zRank = appWM.zOrderRank()
        close()
    }

    private func escPressed() {
        if !search.isEmpty { setSearch(""); return }
        revert()
    }

    private func navigate(_ dir: Dir) {
        let tiles = stageView?.tiles ?? []
        guard !tiles.isEmpty else { return }
        guard let cur = tiles.firstIndex(where: { $0.info.windowID == selectedID }) else {
            selectedID = tiles[0].info.windowID
            updateSelectionUI()
            return
        }
        switch dir {
        case .left: selectedID = tiles[(cur - 1 + tiles.count) % tiles.count].info.windowID
        case .right: selectedID = tiles[(cur + 1) % tiles.count].info.windowID
        case .up, .down:
            let curFrame = tiles[cur].frame
            let candidates = tiles.enumerated().filter { _, t in
                dir == .up ? t.frame.minY < curFrame.minY - 4 : t.frame.minY > curFrame.minY + 4
            }
            if let best = candidates.min(by: { a, b in
                let da = abs(a.element.frame.midX - curFrame.midX) + abs(a.element.frame.minY - curFrame.minY)
                let db = abs(b.element.frame.midX - curFrame.midX) + abs(b.element.frame.minY - curFrame.minY)
                return da < db
            }) {
                selectedID = best.element.info.windowID
            }
        }
        updateSelectionUI()
    }

    // MARK: Tastatur-Visualisierung

    private func updateSelectionUI() {
        for t in stageView?.tiles ?? [] {
            t.setKeyboardSelection(t.info.windowID == selectedID)
            t.setChecked(checked.contains(t.info.windowID))
        }
        updateRealHighlight()
    }

    // Zeigt einen Rahmen um das ECHTE gewählte Fenster an seiner realen
    // Bildschirmposition und holt es kurz nach vorn, solange es gewählt ist.
    private func updateRealHighlight() {
        guard let id = selectedID, let info = allWins.first(where: { $0.windowID == id }) else {
            selectionHighlight?.hide()
            unraiseIfNeeded()
            return
        }
        if raisedForSelection != id {
            unraiseIfNeeded()
            axRaise(info.ax)
            raisedForSelection = id
        }
        if selectionHighlight == nil { selectionHighlight = LoopPreviewPanel() }
        selectionHighlight?.show(quartzRect: info.bounds)
    }

    // Setzt das zuvor vorgezogene Fenster wieder auf seinen ursprünglichen
    // Platz zurück: alle Fenster, die beim Öffnen des Podiums davor lagen,
    // in ihrer ursprünglichen Reihenfolge erneut anheben (von hinten nach
    // vorn) — das zurückgesetzte Fenster selbst bleibt unangetastet und
    // rutscht so wieder hinter sie. axRaise ändert nur die Fenster-Server-
    // Reihenfolge, nicht den App-Fokus — stört also nie die Tastatur des Overlays.
    private func unraiseIfNeeded() {
        guard let id = raisedForSelection else { return }
        raisedForSelection = nil
        guard let originalRank = zRank[id] else { return }
        let inFrontOriginally = allWins
            .filter { (zRank[$0.windowID] ?? .max) < originalRank }
            .sorted { (zRank[$0.windowID] ?? .max) > (zRank[$1.windowID] ?? .max) }
        for w in inFrontOriginally { axRaise(w.ax) }
    }

    private func updateFooter() {
        footerLabel?.stringValue = loopMenuView != nil
            ? "←→↑↓ Rand   U I J K Ecken   E/⇧E Extras   F/Rechtsklick Füllen   M A H W C Allgemein   Z/⇧Z Minimieren   X Ausblenden   S/⇧S Stash   ⌘Z Rückgängig   1–9 Monitor   ⇥/⇧⇥ Wechseln   ↵ anwenden   Esc zurück"
            : "tippen filtert   ←→↑↓ wählen   ↵ / Klick positionieren   Leertaste Auto-Arrange-Häkchen   langsam ziehen verbindet Ränder   ? Hilfe"
        footerLabel?.textColor = loopMenuView != nil ? .systemOrange : .tertiaryLabelColor
    }

    private func showCheatsheet() {
        guard cheatsheet == nil, let root = window?.contentView else { return }
        let panel = FlippedView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.97).cgColor
        panel.layer?.cornerRadius = 16
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        var y: CGFloat = 18
        var maxW: CGFloat = 0
        for line in KeyboardHelp.lines {
            let l = NSTextField(labelWithString: line.text)
            l.font = line.isHeader ? .systemFont(ofSize: 12, weight: .bold) : .monospacedSystemFont(ofSize: 12, weight: .regular)
            l.textColor = line.isHeader ? .systemOrange : .labelColor
            l.sizeToFit()
            l.frame.origin = NSPoint(x: 20, y: y)
            panel.addSubview(l)
            y += line.text.isEmpty ? 8 : 20
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
        let headerH: CGFloat = 22

        // Das Overlay erscheint zentriert auf dem Bildschirm mit dem
        // Mauszeiger. Breite: so viel wie der Inhalt braucht, höchstens 75 %
        // der Bildschirmbreite. Höhe folgt dem Inhalt (siehe resizeToFitStage),
        // gedeckelt bei 85 % der Bildschirmhöhe.
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vis = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        maxContentHeight = (vis.height * 0.85).rounded()
        let availW = (vis.width * 0.75).rounded() - padding * 2

        // Podium erst am 75%-Maximum layouten und messen, dann die Breite auf
        // den tatsächlichen Bedarf trimmen und ggf. enger neu umbrechen.
        let stageV = StageView(controller: self)
        stageV.setWindows(stageList(), filter: search, maxWidth: availW, dot: dotColor, floating: isFloatingWin, checked: { self.checked.contains($0.windowID) })
        innerWidth = min(availW, max(stageV.frame.width, 420))
        if innerWidth < availW {
            stageV.setWindows(stageList(), filter: search, maxWidth: innerWidth, dot: dotColor, floating: isFloatingWin, checked: { self.checked.contains($0.windowID) })
        }
        stageMaxWidth = innerWidth
        stageView = stageV

        let contentWidth = innerWidth + padding * 2
        fixedTopHeight = padding + headerH + 10
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

        // Kopfzeile des Podiums: Titel links, Suche rechts.
        let headerY = padding
        let title = NSTextField(labelWithString: "Podium · nach App")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: padding, y: headerY, width: 240, height: 17)
        bg.addSubview(title)

        let sl = NSTextField(labelWithString: "Tippen filtert das Podium")
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

        // Start-Auswahl: das aktuell aktive Fenster, sonst die erste Kachel.
        selectedID = appWM.activeWindow(among: allWins)?.windowID ?? stageV.tiles.first?.info.windowID
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

        // Dritter Auswahlweg neben Pfeiltasten/Suche: das Fenster unter dem
        // Mauszeiger auf den echten Monitoren wählen — .common-Mode wie beim
        // Loop-Modus-Tracking, damit es auch in Tracking-Loops (Menüs) läuft.
        let mTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stageMouseMoved()
        }
        RunLoop.main.add(mTimer, forMode: .common)
        stageMouseTimer = mTimer

        setupStageClickCatchers()
    }

    // Ein Klick-Fang-Fenster pro Monitor (wie LoopRingPanel für den
    // Loop-Modus, siehe dort): ein Klick auf das per Maus-Hover ausgewählte
    // echte Fenster bestätigt genau wie ↵ — ohne eigenes Fenster würde der
    // Klick zuerst die fremde App treffen (Button drücken, Link öffnen, …),
    // bevor Podium überhaupt reagieren könnte. Direkt UNTER das Podiums-
    // Fenster einsortiert, damit Klicks auf das Podium selbst (Kacheln,
    // Hintergrund) unverändert bei ihr ankommen.
    private func setupStageClickCatchers() {
        guard let mainWin = window else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        for d in displays {
            let full = d.full
            let frame = NSRect(x: full.minX, y: primaryH - full.maxY, width: full.width, height: full.height)
            let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.isReleasedWhenClosed = false
            let view = StageClickCatcherView(frame: NSRect(origin: .zero, size: frame.size))
            view.onClick = { [weak self] in self?.stageClickConfirm() }
            win.contentView = view
            win.orderFrontRegardless()
            win.order(.below, relativeTo: mainWin.windowNumber)
            stageClickCatchers.append(win)
        }
    }

    // Solange der Loop-Modus offen ist, entscheidet dessen eigener Catcher
    // (LoopRingPanel) — dieselbe Aktion wie ↵ ohne ⌘ (positionieren bzw.
    // wechseln, je nach Einstellung; bei ≥2 Häkchen Auto-Arrange).
    private func stageClickConfirm() {
        guard loopMenuView == nil else { return }
        enterPressed(cmd: false)
    }

    // Nur reagieren, wenn die Maus sich seit dem letzten Tick bewegt hat
    // (sonst überschreibt der 60Hz-Poll ständig jede Pfeiltasten-Auswahl im
    // nächsten Tick wieder) und solange der Loop-Modus nicht offen ist (der
    // hat sein eigenes Tracking, siehe loopMouseMoved). Kein Treffer (leerer
    // Schreibtisch oder Zeiger über dem Podium selbst) lässt die bestehende
    // Auswahl unverändert stehen.
    private func stageMouseMoved() {
        guard loopMenuView == nil else { return }
        let mouse = NSEvent.mouseLocation
        if let last = lastPolledStageMouseLocation, hypot(mouse.x - last.x, mouse.y - last.y) < 1 { return }
        lastPolledStageMouseLocation = mouse
        if let w = window, w.frame.contains(mouse) { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: mouse.x, y: primaryH - mouse.y)
        let candidates = allWins.filter { !$0.minimized && $0.bounds.contains(q) }
        guard let hit = candidates.min(by: { (zRank[$0.windowID] ?? .max) < (zRank[$1.windowID] ?? .max) }),
              hit.windowID != selectedID else { return }
        selectedID = hit.windowID
        updateSelectionUI()
    }

    // Unfreiwilliger Fokusverlust (Spotlight, System-Dialog, Fremd-Klick):
    // schließen, aber NICHT aufräumen (kein autoMinimize) — der Nutzer hat
    // die Sitzung nicht bewusst beendet.
    func windowDidResignKey(_ notification: Notification) { close(applyAutoMinimize: false) }

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

    private func isFloatingWin(_ w: WinInfo) -> Bool {
        cfg.isFloating(pid: w.pid, name: w.app)
    }

    // Der Monitor, auf dem ein Fenster aktuell (mehrheitlich) liegt.
    private func display(for w: WinInfo) -> Display? {
        guard let id = displayID(containing: CGPoint(x: w.bounds.midX, y: w.bounds.midY), in: displays) else { return displays.first }
        return displays.first { $0.id == id }
    }

    // Minimierte Fenster vor jeder Aktion zurückholen.
    private func revive(_ info: WinInfo) {
        guard info.minimized else { return }
        axSetMinimized(info.ax, false)
    }

    // MARK: Hover & Vorschau (Thumbnail-Großvorschau, unabhängig vom Loop-Modus)

    // Maus-Hover zählt genauso als Auswahl wie Pfeiltasten — sofort (ohne
    // Verzögerung), damit sich das Durchschalten mit der Maus genauso
    // reaktionsschnell anfühlt. Der (separat verzögerte) Thumbnail-Zoom
    // darunter ist ein eigenes, unabhängiges Feature.
    func tileHoverBegan(_ tile: WindowTileView) {
        selectedID = tile.info.windowID
        updateSelectionUI()
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
        guard let tile = hoverSourceTile, let root = window?.contentView else { return }
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

    // MARK: Klick

    // Klick auf eine Kachel verhält sich wie Enter (je nach Interaktionsmodell
    // Loop-Modus oder Wechseln); Doppelklick nimmt immer den jeweils anderen Pfad.
    func tileClicked(_ info: WinInfo) {
        selectedID = info.windowID
        if SettingsStore.shared.stageEnterSwitches {
            focusAndClose(info)
        } else {
            openLoopMode(for: info)
        }
    }

    func tileDoubleClicked(_ info: WinInfo) {
        selectedID = info.windowID
        if SettingsStore.shared.stageEnterSwitches {
            openLoopMode(for: info)
        } else {
            focusAndClose(info)
        }
    }

    // MARK: Fenster-Aktionen auf dem Podium (⌘M/⌘H/⌘⌫ + Kontextmenü)

    private func minimizeFromStage(_ info: WinInfo) {
        axSetMinimized(info.ax, true)
        touchedIDs.insert(info.windowID)
        if let i = allWins.firstIndex(where: { $0.windowID == info.windowID }) {
            allWins[i].minimized = true
        }
        refreshStage()
    }

    private func hideFromStage(_ info: WinInfo) {
        hiddenPids.insert(info.pid)
        NSRunningApplication(processIdentifier: info.pid)?.hide()
        touchedIDs.insert(info.windowID)
        refreshStage()
    }

    // Rechtsklick auf eine Kachel: die wichtigsten Aktionen ohne Loop-Umweg.
    func tileMenu(for info: WinInfo) -> NSMenu {
        selectedID = info.windowID
        updateSelectionUI()
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.target = self
            it.representedObject = NSNumber(value: info.windowID)
            return it
        }
        menu.addItem(item("Fokussieren", #selector(menuFocus(_:))))
        menu.addItem(item("Positionieren (Loop-Modus)", #selector(menuLoop(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Minimieren", #selector(menuMinimize(_:))))
        menu.addItem(item("App ausblenden", #selector(menuHide(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Fenster schließen", #selector(menuClose(_:))))
        menu.addItem(item("App beenden", #selector(menuQuit(_:))))
        return menu
    }

    private func menuTarget(_ sender: NSMenuItem) -> WinInfo? {
        guard let n = sender.representedObject as? NSNumber else { return nil }
        return allWins.first { $0.windowID == CGWindowID(n.uint32Value) }
    }

    @objc private func menuFocus(_ sender: NSMenuItem) { if let w = menuTarget(sender) { focusAndClose(w) } }
    @objc private func menuLoop(_ sender: NSMenuItem) { if let w = menuTarget(sender) { openLoopMode(for: w) } }
    @objc private func menuMinimize(_ sender: NSMenuItem) { if let w = menuTarget(sender) { minimizeFromStage(w) } }
    @objc private func menuHide(_ sender: NSMenuItem) { if let w = menuTarget(sender) { hideFromStage(w) } }
    @objc private func menuClose(_ sender: NSMenuItem) { if let w = menuTarget(sender) { closeRequested(w) } }
    @objc private func menuQuit(_ sender: NSMenuItem) {
        guard let w = menuTarget(sender) else { return }
        NSRunningApplication(processIdentifier: w.pid)?.terminate()
        allWins.removeAll { $0.pid == w.pid }
        if let sel = selectedID, !allWins.contains(where: { $0.windowID == sel }) { selectedID = nil }
        refreshStage()
    }

    // X-Knopf einer Kachel: echtes Fenster schließen (drückt dessen roten
    // Schließen-Knopf — die App darf also noch "Sichern?" fragen) und von der
    // Podium entfernen.
    func closeRequested(_ info: WinInfo) {
        hidePreview()
        axClose(info.ax)
        allWins.removeAll { $0.windowID == info.windowID }
        WindowHistory.shared.forget(info.windowID)
        touchedIDs.remove(info.windowID)
        stashed.removeValue(forKey: info.windowID)
        checked.removeAll { $0 == info.windowID }
        if selectedID == info.windowID { selectedID = nil }
        refreshStage()
    }

    // MARK: Loop-Modus

    // Öffnet den Ring fürs gegebene Fenster: das ganze Podium (das komplette
    // Overlay-Fenster) verschwindet, sichtbar bleibt NUR der Ring (eigenes
    // schwebendes Panel) + die Live-Vorschau. Das Overlay-Fenster selbst
    // bleibt aber Key-Fenster (nur unsichtbar) — sonst würde die Tastatur
    // (↵/Esc/Legende) nicht mehr ankommen. Ein globaler Mausmonitor (wie
    // DragSnap, öffentliche API, nur Lesezugriff) treibt Ring + Vorschau an,
    // weil der Zeiger die meiste Zeit nicht über dem kleinen Ring liegt.
    private func openLoopMode(for info: WinInfo?) {
        guard loopMenuView == nil else { return }   // nie doppelt (Timer/Panel würden überschrieben, ohne die alten aufzuräumen)
        guard let info, let d = display(for: info) else { return }
        revive(info)
        selectionHighlight?.hide()   // die Loop-Vorschau übernimmt die Anzeige
        loopTarget = info
        loopAnchorDisplay = d
        window?.contentView?.isHidden = true

        let others = appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: cfg)
        let menu = LoopMenuView()
        menu.configure(.init(target: info, display: d, others: others, displays: displays))
        menu.onPreview = { [weak self] rects in self?.showPreviews(rects) }
        menu.onCommit = { [weak self] action, fillMode in self?.applyLoopAction(action, fillMode: fillMode, to: info) }
        menu.onCancel = { [weak self] in self?.closeLoopMode() }
        menu.onAnchorChange = { [weak self] d in
            guard let self else { return }
            self.loopAnchorDisplay = d
            let others = appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: self.cfg)
            self.loopMenuView?.updateDisplay(d, others: others)
            self.repositionRingPanel(on: d)
        }
        loopMenuView = menu

        let panel = LoopRingPanel()
        // Klick irgendwo auf dem Anker-Monitor = Commit (Fang übers eigene
        // Catcher-Fenster; ein Global-Monitor würde eigene App-Events nie sehen).
        panel.onClick = { [weak self] in self?.loopMouseCommit() }
        panel.onRightClick = { [weak self] in self?.loopMenuView?.cycleFillMode() }
        loopRingPanel = panel
        repositionRingPanel(on: d)

        // .common-Mode: der Default-Mode pausiert während Tracking-Loops
        // (Menüs, Drags) — der Ring soll auch dann weiter der Maus folgen.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.loopMouseMoved()
        }
        RunLoop.main.add(timer, forMode: .common)
        loopMouseTimer = timer
        loopMouseMoved()   // sofort mit der aktuellen Mausposition befüllen, nicht erst beim ersten Timer-Tick
    }

    private func closeLoopMode() {
        stopLoopTracking()
        loopMenuView = nil
        window?.contentView?.isHidden = false
        updateFooter()
        updateSelectionUI()   // Markierung ums (weiterhin gewählte) Fenster wieder einblenden
    }

    private func stopLoopTracking() {
        loopMouseTimer?.invalidate()
        loopMouseTimer = nil
        lastPolledMouseLocation = nil
        loopRingPanel?.hide()
        loopRingPanel = nil
        previewPanels.forEach { $0.hide() }
        previewPanels = []
        loopTarget = nil
        loopAnchorDisplay = nil
    }

    // Klick irgendwo (nicht nur auf den Ring) bestätigt die aktuell gewählte
    // Position — genau wie ↵, nur mit der Maus statt der Tastatur.
    private func loopMouseCommit() {
        guard let info = loopTarget, let action = loopMenuView?.current else { return }
        applyLoopAction(action, fillMode: loopMenuView?.fillMode ?? .solo, to: info)
    }

    private func repositionRingPanel(on d: Display) {
        guard let menu = loopMenuView else { return }
        loopRingPanel?.show(menu, on: d)
    }

    // Ein Panel pro Rechteck: bestehende Panels wiederverwenden, überzählige
    // ausblenden — so flackert es nicht, wenn die Anzahl gleich bleibt (der
    // Normalfall bei jeder Mausbewegung/Zonenwechsel).
    private func showPreviews(_ rects: [CGRect]) {
        while previewPanels.count < rects.count { previewPanels.append(LoopPreviewPanel()) }
        while previewPanels.count > rects.count {
            previewPanels.removeLast().hide()
        }
        for (panel, rect) in zip(previewPanels, rects) { panel.show(quartzRect: rect) }
    }

    // Globale Mausposition -> Zone/Variante, ohne Kreis-Zwang: es reicht,
    // irgendwo im passenden Quadranten um den Monitor-Mittelpunkt zu sein
    // (wie bei Loop). Liegt der Zeiger auf einem ANDEREN Monitor als dem
    // aktuellen Anker, "folgt" der Ring dorthin — so wechselt man per Maus
    // den Zielmonitor fürs Fenster.
    private func loopMouseMoved() {
        guard let d0 = loopAnchorDisplay else { return }
        let mouse = NSEvent.mouseLocation
        if let last = lastPolledMouseLocation, hypot(mouse.x - last.x, mouse.y - last.y) < 1 { return }
        lastPolledMouseLocation = mouse
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: mouse.x, y: primaryH - mouse.y)   // AppKit unten-links -> Quartz oben-links
        if let hitID = displayID(containing: q, in: displays), hitID != d0.id,
           let d = displays.first(where: { $0.id == hitID }) {
            loopAnchorDisplay = d
            if let info = loopTarget {
                let others = appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: cfg)
                loopMenuView?.updateDisplay(d, others: others)
            }
            repositionRingPanel(on: d)
        }
        guard let anchor = loopAnchorDisplay else { return }
        let center = CGPoint(x: anchor.visible.midX, y: anchor.visible.midY)
        let dx = q.x - center.x, dy = q.y - center.y
        let dist = hypot(dx, dy)
        guard dist > 4 else { return }   // Totzone exakt im Zentrum
        var angle = atan2(-dy, dx)        // Quartz: +y runter -> für Standard-Winkel invertieren
        if angle < 0 { angle += 2 * .pi }
        var idx = Int(((angle + .pi / 8) / (.pi / 4)).rounded(.down)) % 8
        idx = (8 - idx) % 8
        let zone = LoopMenuView.zones[idx]
        let variant: EdgeVariant
        switch zone {
        case .left, .right, .top, .bottom:
            let refDist = min(anchor.visible.width, anchor.visible.height) / 2
            let t = min(dist / max(refDist, 1), 1)
            variant = t < 0.33 ? .third : (t < 0.66 ? .half : .twoThirds)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            variant = .half
        }
        loopMenuView?.mouseUpdate(zone: zone, variant: variant)
    }

    // Die eine Anwendungsroutine für den Loop-Modus: setzt EIN Fenster real
    // um (solo — außer der Nutzer hat "mit Nachbarn kacheln" für Hälften/
    // Viertel eingeschaltet, dann via BentoApply wie Drag-to-Edge/Radial).
    private func applyLoopAction(_ action: LoopAction, fillMode: LoopFillMode, to info: WinInfo) {
        // Nach dem Anwenden zurück aufs volle Board: closeLoopMode() blendet
        // das Podium wieder ein, setSearch("") löscht den Filter UND ruft
        // dabei refreshStage() bereits mit auf — kein separater Aufruf nötig.
        // zRank frisch lesen: Commits heben Fenster an, sonst arbeiten
        // Podiums-Sortierung und unraiseIfNeeded mit der Ordnung von vorher.
        defer {
            closeLoopMode()
            refreshAllBounds()
            zRank = appWM.zOrderRank()
            setSearch("")
        }
        guard let d = loopAnchorDisplay, let currentFrame = axFrame(info.ax) else { return }
        WindowHistory.shared.recordIfNeeded(info.windowID, currentFrame: currentFrame)
        touchedIDs.insert(info.windowID)
        LinkedEdges.shared.suppress()
        var finalDisplay = d   // .throwToDisplay/.switchDisplay ändern das Ziel unten

        // Rand-verankerte Aktion solo setzen und — falls "mit Nachbarn
        // kacheln" an ist — die Restfläche (Bildschirm minus dieses Fenster)
        // mit bis zu 3 anderen Fenstern füllen (insgesamt max. 4, wie
        // BentoLayout). Nur für Zonen sinnvoll, deren Rest ein einzelnes
        // Rechteck ist (siehe LoopEngine.remainder) — zentrierte Aktionen
        // rufen das gar nicht erst auf, siehe .extra unten.
        func fillEdge(_ zone: BentoZone, frame: CGRect) {
            axSetFrame(info.ax, frame)
            axRaise(info.ax)
            guard fillMode != .solo else { return }
            let others = appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: cfg)
                .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
            guard !others.isEmpty else { return }
            let rest = LoopEngine.remainder(of: frame, in: d.visible, edge: zone)
            switch fillMode {
            case .solo:
                break
            case .topThree:
                let toPlace = Array(others.prefix(3))
                let vertical = rest.height > rest.width
                let frames = Layout.frames(visible: rest, vertical: vertical, count: toPlace.count, split: 0)
                for (w, f) in zip(toPlace, frames) { axSetFrame(w.ax, f) }
            case .all:
                let frames = LoopEngine.autoGrid(count: others.count, in: rest)
                for (w, f) in zip(others, frames) { axSetFrame(w.ax, f) }
            }
        }

        switch action {
        case .edge(let zone, let variant):
            fillEdge(zone, frame: LoopEngine.frame(zone: zone, variant: variant, in: d.visible))
        case .corner(let zone, let variant):
            // Bento-Nachbar-Kacheln nur bei der 50/50-Ecke (BentoLayout kennt
            // keine ⅓/⅔-Ecken) — gecyclte Varianten immer solo.
            if fillMode != .solo, variant == .half {
                let others = appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: cfg)
                    .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
                BentoApply.apply(zone: zone, dragged: info.ax, others: others.map { $0.ax }, display: d)
            } else {
                axSetFrame(info.ax, LoopEngine.frame(zone: zone, variant: variant, in: d.visible))
                axRaise(info.ax)
            }
        case .general(let a):
            axSetFrame(info.ax, LoopEngine.generalFrame(a, in: d.visible, current: currentFrame))
            axRaise(info.ax)
        case .extra(let z):
            let frame = LoopEngine.extraFrame(z, in: d.visible)
            if let edge = z.edgeAnchor {
                fillEdge(edge, frame: frame)
            } else {
                axSetFrame(info.ax, frame)
                axRaise(info.ax)
            }
        case .hide:
            hiddenPids.insert(info.pid)   // für vollständigen Escape-Revert
            NSRunningApplication(processIdentifier: info.pid)?.hide()
        case .minimize:
            axSetMinimized(info.ax, true)
        case .minimizeOthers:
            for other in appWM.otherWindows(on: d, excludingAX: info.ax, pid: info.pid, cfg: cfg) {
                axSetMinimized(other.ax, true)
            }
        case .stash:
            let edge = LoopEngine.nearestEdge(of: currentFrame, in: d.visible)
            stashed[info.windowID] = (frame: currentFrame, edge: edge)
            axSetFrame(info.ax, LoopEngine.stashFrame(currentFrame, edge: edge, in: d.visible))
        case .unstash:
            if let saved = stashed.removeValue(forKey: info.windowID) {
                revive(info)   // falls zwischenzeitlich minimiert
                axSetFrame(info.ax, saved.frame)
                axRaise(info.ax)
            }
        case .undo:
            if let f = WindowHistory.shared.undoFrame(info.windowID) {
                axSetFrame(info.ax, f)
                axRaise(info.ax)
            }
        case .throwToDisplay(let idx):
            guard displays.indices.contains(idx) else { break }
            // Quelle = Monitor unterm ECHTEN aktuellen Frame — nicht der Anker,
            // der per Ziffer/⇥ schon aufs Ziel gesprungen ist (from==to ergäbe
            // eine an den Rand geklemmte Fehlposition statt proportionalem Übertrag).
            let sourceID = displayID(containing: CGPoint(x: currentFrame.midX, y: currentFrame.midY), in: displays)
            let source = displays.first(where: { $0.id == sourceID }) ?? d
            axSetFrame(info.ax, LoopEngine.proportionalFrame(currentFrame, from: source, to: displays[idx]))
            axRaise(info.ax)
            finalDisplay = displays[idx]
        }

        // Verbundene Ränder auch für den Loop-Solo-Pfad anmelden (nicht nur
        // BentoApply): welche Fenster GENAU JETZT wirklich danebenliegen,
        // bestimmt LinkedEdges bei jedem Resize ohnehin live neu — ein
        // Fenster zu beobachten, das gar nicht angrenzt, hat keinen Nachteil.
        // Fokus NICHT sofort setzen (axFocus aktiviert die App → Overlay
        // verliert Key → Session-Abriss statt "zurück auf das Podium") —
        // stattdessen fürs Session-Ende vormerken, siehe close().
        switch action {
        case .hide, .minimize, .minimizeOthers, .stash:
            break
        default:
            lastCommitted = info
            let others = appWM.otherWindows(on: finalDisplay, excludingAX: info.ax, pid: info.pid, cfg: cfg)
            LinkedEdges.shared.track([info.ax] + others.map { $0.ax })
        }
    }

    // MARK: Podium

    // Alle verwalteten Fenster, Z-sortiert für stabile App-Gruppierung.
    private func stageList() -> [WinInfo] {
        allWins.sorted { (zRank[$0.windowID] ?? .max) < (zRank[$1.windowID] ?? .max) }
    }

    // Bounds aller Fenster aus der Realität nachlesen — nach jeder Loop-Aktion,
    // damit das Podium (Thumbnails, Farbpunkt) den echten Zustand zeigt.
    private func refreshAllBounds() {
        allWins = allWins.map { w in axFrame(w.ax).map { w.with(bounds: $0) } ?? w }
    }

    private func refreshStage() {
        guard let stageV = stageView else { return }
        stageV.setWindows(stageList(), filter: search, maxWidth: stageMaxWidth, dot: dotColor, floating: isFloatingWin, checked: { self.checked.contains($0.windowID) })
        stageV.frame.origin.x = 28 + ((innerWidth - stageV.frame.width) / 2).rounded()
        resizeToFitStage()
        updateSelectionUI()
    }

    // Fensterhöhe folgt dem Podiums-Inhalt (Oberkante bleibt fix) — kein toter
    // Leerraum unter dem Podium, kein Abschneiden nach dem Schließen von Fenstern.
    private func resizeToFitStage() {
        guard let win = window, let stageV = stageView else { return }
        let newH = min(fixedTopHeight + stageV.frame.height + 18 + 28, maxContentHeight)
        guard abs(win.frame.height - newH) > 1 else { return }
        var f = win.frame
        let topY = f.maxY
        f.size.height = newH
        f.origin.y = topY - newH
        win.setFrame(f, display: true, animate: true)
        win.invalidateShadow()
    }
}
