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
        let displays: [Display]
    }

    var onPreview: ((CGRect?) -> Void)?
    var onCommit: ((LoopAction) -> Void)?
    var onCancel: (() -> Void)?
    // Feuert, wenn die Tastatur (Zifferntaste/⇥) den Anker-Monitor wechselt —
    // Overlay.swift muss seinen eigenen loopAnchorDisplay + die Ring-Position
    // synchron mithalten, sonst rechnet applyLoopAction() beim Anwenden auf
    // dem FALSCHEN (ursprünglichen) Monitor statt dem gerade gewählten.
    var onAnchorChange: ((Display) -> Void)?

    private(set) var current: LoopAction?
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
    private var centerLabel: NSTextField!
    private var highlighted = -1

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.viewSize))
        wantsLayer = true
        buildLayers()
        centerLabel = NSTextField(labelWithString: "")
        centerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        centerLabel.alignment = .center
        centerLabel.textColor = .labelColor
        centerLabel.lineBreakMode = .byWordWrapping
        centerLabel.frame = NSRect(x: bounds.midX - Self.innerRadius, y: bounds.midY - 14,
                                   width: Self.innerRadius * 2, height: 28)
        addSubview(centerLabel)
        updateAppearanceColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ ctx: Context) {
        context = ctx
        current = nil
        extrasIndex = 0
        highlighted = -1
        sectorLayers.forEach { $0.fillColor = NSColor.clear.cgColor }
        centerLabel.stringValue = "Maus bewegen oder\nTaste drücken"
    }

    // Der Anker (Monitor unter der Maus) hat sich geändert — Vorschau-Fläche
    // aktualisieren, ohne die laufende Auswahl (current) zurückzusetzen.
    func updateDisplay(_ d: Display) {
        guard var ctx = context else { return }
        ctx.display = d
        context = ctx
        if let action = current { onPreview?(previewFrame(for: action)) }
    }

    // Von Overlay.swift bei jeder globalen Mausbewegung aufgerufen — ersetzt
    // eine eigene lokale mouseMoved-Behandlung, da der Ring meist gar nicht
    // unter dem Zeiger liegt (der ist ja irgendwo im Quadranten, nicht im Ring).
    func mouseUpdate(zone: BentoZone, variant: EdgeVariant) {
        let action = LoopAction.zone(zone, variant: variant)
        if let idx = Self.zones.firstIndex(of: zone), idx != highlighted {
            if highlighted >= 0 { sectorLayers[highlighted].fillColor = NSColor.clear.cgColor }
            sectorLayers[idx].fillColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
            highlighted = idx
        }
        guard action != current else { return }
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
        case 123: cycleEdge(.left); return true
        case 124: cycleEdge(.right); return true
        case 125: cycleEdge(.bottom); return true
        case 126: cycleEdge(.top); return true
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
        default: return false
        }
    }

    // Anker per Tastatur wechseln (Zifferntaste/⇥): eigenen Kontext UND
    // Overlay.swift synchron mitziehen, damit spätere Rand-/Eck-Aktionen auf
    // dem NEUEN Monitor rechnen statt auf dem, wo der Ring geöffnet wurde.
    private func jumpAnchor(to d: Display) {
        updateDisplay(d)
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
        onCommit?(action)
    }

    // MARK: Gemeinsamer Zustand -> Vorschau + Mitte-Label

    private func setCurrent(_ action: LoopAction) {
        if action != current {
            // Haptik beim Zonen-/Aktionswechsel (Trackpad) — wie bei Loop.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        current = action
        centerLabel.stringValue = Self.label(for: action)
        onPreview?(previewFrame(for: action))
    }

    private func previewFrame(for action: LoopAction) -> CGRect? {
        guard let ctx = context else { return nil }
        switch action {
        case .edge(let zone, let variant), .corner(let zone, let variant):
            return LoopEngine.frame(zone: zone, variant: variant, in: ctx.display.visible)
        case .general(let a):
            return LoopEngine.generalFrame(a, in: ctx.display.visible, current: ctx.target.bounds)
        case .extra(let z):
            return LoopEngine.extraFrame(z, in: ctx.display.visible)
        case .undo:
            return WindowHistory.shared.undoFrame(ctx.target.windowID)
        case .throwToDisplay(let idx):
            guard ctx.displays.indices.contains(idx) else { return nil }
            // Quelle = Monitor, auf dem das Fenster WIRKLICH liegt — nicht der
            // Ring-Anker, der per jumpAnchor schon aufs Ziel gesprungen sein kann
            // (from==to ergäbe eine an den Rand geklemmte Fehlposition).
            return LoopEngine.proportionalFrame(ctx.target.bounds,
                                                from: Self.sourceDisplay(for: ctx), to: ctx.displays[idx])
        case .hide, .minimize, .minimizeOthers, .stash, .unstash:
            return nil
        }
    }

    // Monitor unter dem Fenster-Mittelpunkt, Fallback aktueller Anker.
    private static func sourceDisplay(for ctx: Context) -> Display {
        let mid = CGPoint(x: ctx.target.bounds.midX, y: ctx.target.bounds.midY)
        guard let id = displayID(containing: mid, in: ctx.displays),
              let d = ctx.displays.first(where: { $0.id == id }) else { return ctx.display }
        return d
    }

    private static func label(for action: LoopAction) -> String {
        switch action {
        case .edge(let z, let v), .corner(let z, let v):
            return v == .half ? "\(zoneName(z))" : "\(zoneName(z)) · \(variantName(v))"
        case .general(.maximize): return "Maximieren"
        case .general(.almostMaximize): return "Fast maximieren"
        case .general(.maximizeHeight): return "Volle Höhe"
        case .general(.maximizeWidth): return "Volle Breite"
        case .general(.center): return "Zentrieren"
        case .extra: return "Extra"
        case .hide: return "Ausblenden"
        case .minimize: return "Minimieren"
        case .minimizeOthers: return "Andere minimieren"
        case .stash: return "Wegschieben"
        case .unstash: return "Zurückholen"
        case .undo: return "Rückgängig"
        case .throwToDisplay(let i): return "Monitor \(i + 1)"
        }
    }

    private static func zoneName(_ z: BentoZone) -> String {
        switch z {
        case .left: return "Links"
        case .right: return "Rechts"
        case .top: return "Oben"
        case .bottom: return "Unten"
        case .topLeft: return "Oben-Links"
        case .topRight: return "Oben-Rechts"
        case .bottomLeft: return "Unten-Links"
        case .bottomRight: return "Unten-Rechts"
        }
    }

    private static func variantName(_ v: EdgeVariant) -> String {
        switch v {
        case .half: return "Hälfte"
        case .third: return "Drittel"
        case .twoThirds: return "Zwei Drittel"
        }
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
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Der schwebende Träger für LoopMenuView: deckt den GESAMTEN Anker-Monitor ab
// (Klick-Fang, siehe LoopCatcherView), der Ring sitzt zentriert darin.
// Borderless-Fenster werden nie key — die Tastatur bleibt beim Overlay-Fenster.
final class LoopRingPanel {
    var onClick: (() -> Void)?
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
// Fenstern, darf aber nie die Bühne selbst verdecken (die während der reinen
// Auswahl auf der Bühne ja weiter sichtbar bleibt, anders als im Loop-Modus).
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
