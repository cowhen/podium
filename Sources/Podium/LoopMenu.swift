import AppKit

// Der Loop-Modus: ein Ring mit 8 Sektoren (Rand + Ecke, wie BentoZone), der
// GENAU EIN Fenster positioniert. Maus UND Tastatur füttern denselben
// `current`-Zustand — exakt wie bei Loop selbst. Anders als eine normale
// NSView-Maussteuerung tippt die Maus hier NICHT lokal auf diesen View: der
// Ring hängt am Bildschirm-Mittelpunkt des Monitors unter dem Mauszeiger,
// die Position kann irgendwo im passenden Quadranten liegen (kein Kreis-
// Zwang) — Overlay.swift liest die globale Mausposition (NSEvent-Globalmonitor,
// wie DragSnap) und drückt das Ergebnis rein über mouseUpdate(zone:variant:).
// So kann der Ring auch dem Mauszeiger auf einen anderen Monitor folgen.
// Zeichenstil (CAShapeLayer-Bögen) ursprünglich von RadialMenu.swift übernommen
// (eigener Code, seither deutlich erweitert), bevor diese Datei entfernt wurde.
final class LoopMenuView: NSView {
    struct Context {
        let target: WinInfo
        var display: Display
        var others: [WinInfo]   // andere Fenster auf `display` — für die Live-Vorschau bei fillMode != .solo
        let displays: [Display]
    }

    var onPreview: (([CGRect]) -> Void)?
    var onCommit: ((LoopAction, LoopFillMode) -> Void)?
    var onCancel: (() -> Void)?
    // Feuert, wenn die Tastatur (Zifferntaste/⇥) den Anker-Monitor wechselt —
    // Overlay.swift muss seinen eigenen loopAnchorDisplay + die Ring-Position
    // synchron mithalten, sonst rechnet applyLoopAction() beim Anwenden auf
    // dem FALSCHEN (ursprünglichen) Monitor statt dem gerade gewählten. Liefert
    // auch die frisch für den neuen Monitor berechneten "anderen" Fenster
    // zurück (updateDisplay braucht die für die Mehrfach-Vorschau).
    var onAnchorChange: ((Display) -> Void)?

    private(set) var current: LoopAction?
    private(set) var fillMode: LoopFillMode = .solo
    private var context: Context?
    private var extrasIndex = 0

    private static let radius: CGFloat = 90
    private static let innerRadius: CGFloat = 28
    static let viewSize = NSSize(width: radius * 2 + 40, height: radius * 2 + 40)

    // Sektoren im Uhrzeigersinn ab Osten — feste Reihenfolge, mit der
    // Overlay.swift die aus der globalen Mausposition berechnete Zone indiziert.
    static let zones: [BentoZone] = [
        .right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft, .top, .topRight,
    ]

    private var bgLayer: CAShapeLayer!
    private var holeLayer: CAShapeLayer!
    private var sectorLayers: [CAShapeLayer] = []
    private var iconLayers: [CALayer] = []
    private var baseIcons: [NSImage?] = []
    private var highlighted = -1
    // Welche Pfeiltasten gerade physisch gedrückt gehalten werden — zwei
    // gleichzeitig (z. B. ← + ↑) fahren die entsprechende Ecke an, statt
    // die einzelne Randrichtung zu cyclen.
    private var heldArrows: Set<UInt16> = []

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.viewSize))
        wantsLayer = true
        buildLayers()
        updateAppearanceColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ ctx: Context) {
        context = ctx
        current = nil
        // Start-Modus kommt aus den Einstellungen (Default: solo) — F/
        // Rechtsklick cycled ab da innerhalb der Sitzung weiter zu 3 größte,
        // dann alle Nachbarn (der Modus, in dem sich Fenster bei zu wenig
        // Restfläche überdecken können).
        fillMode = SettingsStore.shared.defaultFillMode
        extrasIndex = 0
        highlighted = -1
        sectorLayers.forEach { $0.fillColor = NSColor.clear.cgColor }
    }

    // Der Anker (Monitor unter der Maus) hat sich geändert — Overlay.swift
    // liefert die für den NEUEN Monitor frisch berechneten "anderen" Fenster
    // gleich mit, damit die Mehrfach-Vorschau nicht mit denen des alten
    // Monitors weiterrechnet. Setzt current NICHT zurück.
    func updateDisplay(_ d: Display, others: [WinInfo]) {
        guard var ctx = context else { return }
        ctx.display = d
        ctx.others = others
        context = ctx
        if let action = current { onPreview?(previewFrames(for: action)) }
    }

    // Von Overlay.swift bei jeder globalen Mausbewegung aufgerufen — ersetzt
    // eine eigene lokale mouseMoved-Behandlung, da der Ring meist gar nicht
    // unter dem Zeiger liegt (der ist ja irgendwo im Quadranten, nicht im Ring).
    func mouseUpdate(zone: BentoZone, variant: EdgeVariant) {
        let action = LoopAction.zone(zone, variant: variant)
        guard action != current else { return }   // vermeidet unnötige previewFrames()-Neuberechnung bei stabilem Hover
        setCurrent(action)
    }

    // MARK: Zeichnen (hell/dunkel-adaptiv)

    private func buildLayers() {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let bg = CAShapeLayer()
        bg.path = CGPath(ellipseIn: CGRect(x: c.x - Self.radius, y: c.y - Self.radius,
                                           width: Self.radius * 2, height: Self.radius * 2), transform: nil)
        layer?.addSublayer(bg)
        bgLayer = bg

        for i in 0..<8 {
            let seg = CAShapeLayer()
            seg.path = sectorPath(center: c, index: i)
            seg.fillColor = NSColor.clear.cgColor
            layer?.addSublayer(seg)
            sectorLayers.append(seg)

            let angle = CGFloat(i) * .pi / 4
            let r = (Self.radius + Self.innerRadius) / 2
            let pos = CGPoint(x: c.x + cos(angle) * r, y: c.y - sin(angle) * r)
            let img = NSImage(systemSymbolName: Self.symbol(for: Self.zones[i]), accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
            baseIcons.append(img)
            let imgLayer = CALayer()
            imgLayer.frame = CGRect(x: pos.x - 10, y: pos.y - 10, width: 20, height: 20)
            imgLayer.contentsGravity = .resizeAspect
            layer?.addSublayer(imgLayer)
            iconLayers.append(imgLayer)
        }

        let hole = CAShapeLayer()
        hole.path = CGPath(ellipseIn: CGRect(x: c.x - Self.innerRadius, y: c.y - Self.innerRadius,
                                             width: Self.innerRadius * 2, height: Self.innerRadius * 2), transform: nil)
        layer?.addSublayer(hole)
        holeLayer = hole
    }

    // CALayer-Farben sind statische CGColor-Snapshots — bei Hell/Dunkel-
    // Wechsel muss neu gezeichnet werden, dafür gibt's keinen Auto-Update.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        bgLayer.fillColor = (dark ? NSColor(calibratedWhite: 0.1, alpha: 0.92)
                                  : NSColor(calibratedWhite: 0.97, alpha: 0.92)).cgColor
        holeLayer.fillColor = (dark ? NSColor(calibratedWhite: 0.18, alpha: 1)
                                    : NSColor(calibratedWhite: 0.88, alpha: 1)).cgColor
        let tint: NSColor = dark ? .white.withAlphaComponent(0.8) : .black.withAlphaComponent(0.75)
        for (i, layer) in iconLayers.enumerated() {
            layer.contents = baseIcons[i]?.tinted(tint)
        }
    }

    private func sectorPath(center c: CGPoint, index: Int) -> CGPath {
        let mid = CGFloat(index) * .pi / 4
        let a0 = -(mid - .pi / 8), a1 = -(mid + .pi / 8)
        let p = CGMutablePath()
        p.addArc(center: c, radius: Self.innerRadius, startAngle: a0, endAngle: a1, clockwise: true)
        p.addArc(center: c, radius: Self.radius, startAngle: a1, endAngle: a0, clockwise: false)
        p.closeSubpath()
        return p
    }

    private static func symbol(for zone: BentoZone) -> String {
        switch zone {
        case .right: return "rectangle.righthalf.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .left: return "rectangle.lefthalf.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .top: return "rectangle.tophalf.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        }
    }

    // MARK: Tastatur — dieselbe `current`-Zustandsänderung wie die Maus;
    // Committen (↵) und Abbrechen (Esc) laufen getrennt, siehe unten.

    func handleKey(_ event: NSEvent) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 36, 76: commit(); return true
        case 53: onCancel?(); return true
        case 48:
            // ⇥/⇧⇥ = Throw auf den geometrischen Nachbarn — als explizites
            // throwToDisplay, damit apply/preview ein festes Ziel haben und
            // nicht relativ zum (schon verschobenen) Anker rechnen müssen.
            if let ctx = context,
               let n = LoopEngine.neighborDisplay(of: ctx.display, direction: shift ? .left : .right, among: ctx.displays),
               let idx = ctx.displays.firstIndex(where: { $0.id == n.id }) {
                jumpAnchor(to: n)
                setCurrent(.throwToDisplay(idx))
            }
            return true
        case 123, 124, 125, 126: handleArrow(event.keyCode); return true
        default: break
        }

        guard let s = event.charactersIgnoringModifiers, let ch = s.first, s.count == 1 else { return false }
        if let d = ch.wholeNumberValue, d >= 1 {
            if let ctx = context, ctx.displays.indices.contains(d - 1) {
                jumpAnchor(to: ctx.displays[d - 1])
            }
            setCurrent(.throwToDisplay(d - 1))
            return true
        }
        if cmd, ch.lowercased() == "z" { setCurrent(.undo); return true }
        switch ch.lowercased() {
        case "u": cycleCorner(.topLeft); return true
        case "i": cycleCorner(.topRight); return true
        case "j": cycleCorner(.bottomLeft); return true
        case "k": cycleCorner(.bottomRight); return true
        case "e": cycleExtras(forward: !shift); return true
        case "m": setCurrent(.general(.maximize)); return true
        case "a": setCurrent(.general(.almostMaximize)); return true
        case "h": setCurrent(.general(.maximizeHeight)); return true
        case "w": setCurrent(.general(.maximizeWidth)); return true
        case "c": setCurrent(.general(.center)); return true
        case "z": setCurrent(shift ? .minimizeOthers : .minimize); return true
        case "x": setCurrent(.hide); return true
        case "s": setCurrent(shift ? .unstash : .stash); return true
        case "f": cycleFillMode(); return true
        default: return false
        }
    }

    // F cycled live durch Solo → bis zu 3 größte → alle — wirkt auf die
    // aktuell gewählte Aktion sofort in der Vorschau (kommt nur bei rand-
    // verankerten Aktionen überhaupt zum Tragen, siehe previewFrames unten).
    // Nicht mehr private: auch per Rechtsklick von außen aufgerufen (siehe
    // LoopRingPanel.onRightClick in Overlay.swift).
    func cycleFillMode() {
        fillMode = fillMode.next
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        // setCurrent mit unveränderter Aktion: kein zweites Haptik (nur bei
        // action != current), aber Label + Vorschau rechnen mit dem neuen Modus neu.
        if let action = current { setCurrent(action) }
    }

    // Overlay.swift meldet hier jedes Loslassen — nötig, um "gerade gehalten"
    // von "gerade gedrückt" zu unterscheiden (nur Auto-Repeat-Events derselben
    // Taste, kein echtes zweites gehaltenes Signal, würden sonst reichen).
    func handleKeyUp(_ event: NSEvent) {
        heldArrows.remove(event.keyCode)
    }

    // 123=←, 124=→, 125=↓, 126=↑. Sind zwei Pfeiltasten gleichzeitig
    // gehalten, fährt das direkt die entsprechende Ecke an; sonst wie bisher
    // die Randrichtung (wiederholtes Drücken cycled die Variante).
    private func handleArrow(_ code: UInt16) {
        heldArrows.insert(code)
        let left = heldArrows.contains(123), right = heldArrows.contains(124)
        let down = heldArrows.contains(125), up = heldArrows.contains(126)
        switch (code, left, right, up, down) {
        case (123, _, _, true, _), (126, true, _, _, _): cycleCorner(.topLeft)
        case (123, _, _, _, true), (125, true, _, _, _): cycleCorner(.bottomLeft)
        case (124, _, _, true, _), (126, _, true, _, _): cycleCorner(.topRight)
        case (124, _, _, _, true), (125, _, true, _, _): cycleCorner(.bottomRight)
        case (123, _, _, _, _): cycleEdge(.left)
        case (124, _, _, _, _): cycleEdge(.right)
        case (125, _, _, _, _): cycleEdge(.bottom)
        case (126, _, _, _, _): cycleEdge(.top)
        default: break
        }
    }

    // Anker per Tastatur wechseln (Zifferntaste/⇥): NUR Overlay.swift
    // benachrichtigen, das dort die frischen "anderen" Fenster für den neuen
    // Monitor berechnet und per updateDisplay(_:others:) zurückspielt — so
    // gibt es nie ein Zwischenstadium mit falschem Anker UND alten Nachbarn.
    private func jumpAnchor(to d: Display) {
        onAnchorChange?(d)
    }

    private func cycleEdge(_ zone: BentoZone) {
        if case .edge(let z, let v) = current, z == zone {
            setCurrent(.edge(zone, LoopEngine.nextVariant(v)))
        } else {
            setCurrent(.edge(zone, .half))
        }
    }

    // Wiederholtes U/I/J/K cyclet die Eckgröße ½ → ⅓ → ⅔ (beide Kanten).
    private func cycleCorner(_ zone: BentoZone) {
        if case .corner(let z, let v) = current, z == zone {
            setCurrent(.corner(zone, LoopEngine.nextVariant(v)))
        } else {
            setCurrent(.corner(zone, .half))
        }
    }

    private func cycleExtras(forward: Bool) {
        let all = ExtraZone.allCases
        extrasIndex = ((extrasIndex + (forward ? 1 : -1)) % all.count + all.count) % all.count
        setCurrent(.extra(all[extrasIndex]))
    }

    private func commit() {
        guard let action = current else { return }
        onCommit?(action, fillMode)
    }

    // MARK: Gemeinsamer Zustand -> Vorschau + Ring-Highlight

    private func setCurrent(_ action: LoopAction) {
        if action != current {
            // Haptik beim Zonen-/Aktionswechsel (Trackpad) — wie bei Loop.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        current = action
        syncHighlight()
        onPreview?(previewFrames(for: action))
    }

    // Sektor-Index für eine Aktion, falls sie einem Rand/einer Ecke
    // entspricht (sonst nil — .general/.extra/.hide/… haben keinen Ring-Sektor).
    private func zoneIndex(for action: LoopAction?) -> Int? {
        switch action {
        case .edge(let z, _), .corner(let z, _): return Self.zones.firstIndex(of: z)
        default: return nil
        }
    }

    // Einziger Ort, der sectorLayers[...].fillColor/highlighted mutiert —
    // läuft für Maus- UND Tastatur-Pfad über setCurrent() hierher (vorher
    // aktualisierte nur der 60Hz-Mausposition-Poll den Ring, Tastatur-
    // Auswahl blieb optisch stehen). Der Gleichheits-Guard verhindert
    // redundante CALayer-Writes, u. a. wenn cycleFillMode() bewusst erneut
    // setCurrent() mit unveränderter Aktion aufruft.
    private func syncHighlight() {
        let idx = zoneIndex(for: current) ?? -1
        guard idx != highlighted else { return }
        if highlighted >= 0 { sectorLayers[highlighted].fillColor = NSColor.clear.cgColor }
        if idx >= 0 { sectorLayers[idx].fillColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor }
        highlighted = idx
    }

    // Liefert ALLE Rechtecke, die beim Commit tatsächlich gesetzt würden —
    // das gezogene Fenster UND (bei rand-verankerten Aktionen + fillMode
    // != .solo) die Nachbarn, die die Restfläche füllen. Dieselbe Geometrie
    // wie Overlay.applyLoopAction, damit Vorschau und Ergebnis nie auseinanderlaufen.
    private func previewFrames(for action: LoopAction) -> [CGRect] {
        guard let ctx = context else { return [] }
        switch action {
        case .edge(let zone, let variant):
            let dragged = LoopEngine.frame(zone: zone, variant: variant, in: ctx.display.visible)
            return [dragged] + fillFrames(zone: zone, dragged: dragged, ctx: ctx)
        case .corner(let zone, let variant):
            let dragged = LoopEngine.frame(zone: zone, variant: variant, in: ctx.display.visible)
            guard variant == .half, fillMode != .solo, !ctx.others.isEmpty else { return [dragged] }
            let toPlace = Self.sortedBySize(ctx.others, mode: fillMode)
            let plan = BentoLayout.plan(zone: zone, othersAvailable: toPlace.count)
            let vertical = plan.vertical ?? ctx.display.vertical
            return Layout.frames(visible: ctx.display.visible, vertical: vertical, count: plan.tokens.count, split: 0)
        case .general(let a):
            return [LoopEngine.generalFrame(a, in: ctx.display.visible, current: ctx.target.bounds)]
        case .extra(let z):
            let dragged = LoopEngine.extraFrame(z, in: ctx.display.visible)
            guard let edge = z.edgeAnchor else { return [dragged] }
            return [dragged] + fillFrames(zone: edge, dragged: dragged, ctx: ctx)
        case .undo:
            guard let f = WindowHistory.shared.undoFrame(ctx.target.windowID) else { return [] }
            return [f]
        case .throwToDisplay(let idx):
            guard ctx.displays.indices.contains(idx) else { return [] }
            // Quelle = Monitor, auf dem das Fenster WIRKLICH liegt — nicht der
            // Ring-Anker, der per jumpAnchor schon aufs Ziel gesprungen sein kann
            // (from==to ergäbe eine an den Rand geklemmte Fehlposition).
            return [LoopEngine.proportionalFrame(ctx.target.bounds,
                                                 from: Self.sourceDisplay(for: ctx), to: ctx.displays[idx])]
        case .hide, .minimize, .minimizeOthers, .stash, .unstash:
            return []
        }
    }

    // Nachbar-Rechtecke für eine rand-verankerte Aktion, je nach fillMode.
    private func fillFrames(zone: BentoZone, dragged: CGRect, ctx: Context) -> [CGRect] {
        guard fillMode != .solo, !ctx.others.isEmpty else { return [] }
        let toPlace = Self.sortedBySize(ctx.others, mode: fillMode)
        let rest = LoopEngine.remainder(of: dragged, in: ctx.display.visible, edge: zone)
        switch fillMode {
        case .solo: return []
        case .topThree:
            return Layout.frames(visible: rest, vertical: rest.height > rest.width, count: toPlace.count, split: 0)
        case .all:
            return LoopEngine.autoGrid(count: toPlace.count, in: rest)
        }
    }

    // topThree: die 3 flächengrößten. all: alle, größte zuerst (bekommen bei
    // knappem Platz im Auto-Raster Vorrang, siehe LoopEngine.autoGrid).
    private static func sortedBySize(_ wins: [WinInfo], mode: LoopFillMode) -> [WinInfo] {
        let sorted = wins.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        switch mode {
        case .solo: return []
        case .topThree: return Array(sorted.prefix(3))
        case .all: return sorted
        }
    }

    // Monitor unter dem Fenster-Mittelpunkt, Fallback aktueller Anker.
    private static func sourceDisplay(for ctx: Context) -> Display {
        let mid = CGPoint(x: ctx.target.bounds.midX, y: ctx.target.bounds.midY)
        guard let id = displayID(containing: mid, in: ctx.displays),
              let d = ctx.displays.first(where: { $0.id == id }) else { return ctx.display }
        return d
    }

}

// Fängt während des Loop-Modus JEDEN Klick auf dem Anker-Monitor ab und
// meldet ihn als Commit — als eigenes Fenster der eigenen App (lokales
// mouseDown), NICHT als NSEvent-Globalmonitor: Global-Monitore feuern nie
// für Events der eigenen App (das Overlay-Fenster liegt unsichtbar darunter),
// und Klicks über fremden Fenstern würden dort durchklicken UND die fremde
// App aktivieren (Overlay verliert Key → Session-Abriss).
private final class LoopCatcherView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

// Der schwebende Träger für LoopMenuView: deckt den GESAMTEN Anker-Monitor ab
// (Klick-Fang, siehe LoopCatcherView), der Ring sitzt zentriert darin.
// Borderless-Fenster werden nie key — die Tastatur bleibt beim Overlay-Fenster.
final class LoopRingPanel {
    var onClick: (() -> Void)?
    // Rechtsklick irgendwo auf dem Anker-Monitor = Füll-Modus cyclen — spiegelt
    // die F-Taste für Maus-Nutzer, ohne die Auswahl zu verwerfen (kein Commit).
    var onRightClick: (() -> Void)?
    private var window: NSWindow?
    private weak var ring: LoopMenuView?

    func show(_ view: LoopMenuView, on display: Display) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let full = display.full
        let frame = NSRect(x: full.minX, y: primaryH - full.maxY, width: full.width, height: full.height)
        if window == nil {
            let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .screenSaver
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.isReleasedWhenClosed = false
            let catcher = LoopCatcherView(frame: NSRect(origin: .zero, size: frame.size))
            catcher.onClick = { [weak self] in self?.onClick?() }
            catcher.onRightClick = { [weak self] in self?.onRightClick?() }
            win.contentView = catcher
            window = win
        } else {
            window?.setFrame(frame, display: true)
        }
        if ring !== view {
            ring?.removeFromSuperview()
            window?.contentView?.addSubview(view)
            ring = view
        }
        // Ring-Zentrum = Mitte der NUTZBAREN Fläche (visible), in Fenster-
        // lokalen Koordinaten (unten-links, Fenster deckt display.full ab).
        let localCenter = NSPoint(x: display.visible.midX - full.minX,
                                  y: full.maxY - display.visible.midY)
        view.frame.origin = NSPoint(x: localCenter.x - view.frame.width / 2,
                                    y: localCenter.y - view.frame.height / 2)
        window?.orderFrontRegardless()
    }

    func hide() {
        ring?.removeFromSuperview()
        ring = nil
        window?.orderOut(nil)
        window = nil
    }
}

// Nicht-destruktive Live-Vorschau auf dem echten Bildschirm — dieselbe
// Fenster-Bauweise wie DragSnapManager.showPreview/hidePreview (DragSnap.swift
// bleibt unangetastet, deshalb hier bewusst dupliziert statt geteilt).
// Level knapp UNTER dem Overlay-Fenster (.floating): sichtbar über normalen
// Fenstern, darf aber nie das Podium selbst verdecken (die während der reinen
// Auswahl auf dem Podium ja weiter sichtbar bleibt, anders als im Loop-Modus).
final class LoopPreviewPanel {
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    private var window: NSWindow?

    func show(quartzRect: CGRect) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: quartzRect.minX, y: primaryH - quartzRect.maxY,
                          width: quartzRect.width, height: quartzRect.height)
        if window == nil {
            let win = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = Self.level
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            view.layer?.borderWidth = 2
            view.layer?.borderColor = NSColor.controlAccentColor.cgColor
            view.layer?.cornerRadius = 12
            view.layer?.cornerCurve = .continuous
            win.contentView = view
            window = win
        }
        window?.setFrame(rect, display: true)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private extension NSImage {
    // Eingefärbte Kopie (für CALayer.contents, das kein Template versteht).
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            self.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        return img
    }
}
