import AppKit
import Carbon.HIToolbox

// Radial-Menü im Loop-Stil (⌃⌥Space): erscheint am Mauszeiger, 8 Sektoren für
// Ränder/Ecken. Hover wählt, Klick wendet auf das zuvor fokussierte Fenster
// an, Escape/Klick ins Zentrum bricht ab. Nutzt BentoLayout — dasselbe
// Vokabular wie Drag-to-Edge und die Box-Vorschau im Overlay: Ränder = sauberer
// 2er-Split, Ecken = wachsendes Bento-Raster (bis zu 4 Fenster), "andere"
// Fenster werden für ein sauberes Layout automatisch mit umgesetzt.
// Abschaltbar in den Einstellungen.
final class RadialMenu: NSObject {
    static let shared = RadialMenu()

    private var window: NSWindow?
    private var target: AXUIElement?
    private var highlighted: Int = -1
    private var sectorLayers: [CAShapeLayer] = []

    private static let radius: CGFloat = 110
    private static let innerRadius: CGFloat = 34

    // Sektoren im Uhrzeigersinn ab Osten, direkt auf BentoZone gemappt —
    // dieselben 8 Zonen wie Drag-to-Edge (siehe BentoLayout.swift).
    private static let zones: [BentoZone] = [
        .right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft, .top, .topRight,
    ]

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

    func toggle() {
        window == nil ? show() : hide()
    }

    private func show() {
        // Ziel VOR dem Anzeigen merken — unser Panel stiehlt gleich den Fokus.
        guard let t = Self.pickTarget() else { return }
        target = t

        let size = Self.radius * 2 + 20
        let mouse = NSEvent.mouseLocation
        let rect = NSRect(x: mouse.x - size / 2, y: mouse.y - size / 2, width: size, height: size)
        let win = KeyPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .popUpMenu
        win.hasShadow = true

        let view = RadialView(frame: NSRect(origin: .zero, size: NSSize(width: size, height: size)), menu: self)
        buildLayers(in: view)
        win.contentView = view
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Fokussiertes Fenster der vordersten App; ist Podium selbst vorn (Aufruf
    // übers Menü), stattdessen das oberste normale Fenster laut CGWindowList.
    private static func pickTarget() -> AXUIElement? {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            if let t = axCopy(axApp, kAXFocusedWindowAttribute as String) { return (t as! AXUIElement) }
            if let first = axWindows(of: app.processIdentifier).first { return first }
        }
        let cgList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        for e in cgList {
            guard (e[kCGWindowLayer as String] as? Int) == 0,
                  let pid = e[kCGWindowOwnerPID as String] as? pid_t,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != Bundle.main.bundleIdentifier
            else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            if let t = axCopy(axApp, kAXFocusedWindowAttribute as String) { return (t as! AXUIElement) }
            if let first = axWindows(of: pid).first { return first }
        }
        return nil
    }

    fileprivate func hide() {
        window?.orderOut(nil)
        window = nil
        sectorLayers = []
        highlighted = -1
        target = nil
    }

    private func buildLayers(in view: NSView) {
        view.wantsLayer = true
        let c = CGPoint(x: view.bounds.midX, y: view.bounds.midY)

        let bg = CAShapeLayer()
        bg.path = CGPath(ellipseIn: CGRect(x: c.x - Self.radius, y: c.y - Self.radius,
                                           width: Self.radius * 2, height: Self.radius * 2), transform: nil)
        bg.fillColor = NSColor(calibratedWhite: 0.1, alpha: 0.92).cgColor
        view.layer?.addSublayer(bg)

        sectorLayers = []
        for i in 0..<8 {
            let layer = CAShapeLayer()
            layer.path = sectorPath(center: c, index: i)
            layer.fillColor = NSColor.clear.cgColor
            view.layer?.addSublayer(layer)
            sectorLayers.append(layer)

            // Symbol in Sektor-Mitte.
            let angle = CGFloat(i) * .pi / 4
            let r = (Self.radius + Self.innerRadius) / 2
            let pos = CGPoint(x: c.x + cos(angle) * r, y: c.y - sin(angle) * r)
            let img = NSImage(systemSymbolName: Self.symbol(for: Self.zones[i]), accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .medium))
            let imgLayer = CALayer()
            imgLayer.contents = img?.tinted(.white)
            imgLayer.frame = CGRect(x: pos.x - 12, y: pos.y - 12, width: 24, height: 24)
            imgLayer.contentsGravity = .resizeAspect
            view.layer?.addSublayer(imgLayer)
        }

        let hole = CAShapeLayer()
        hole.path = CGPath(ellipseIn: CGRect(x: c.x - Self.innerRadius, y: c.y - Self.innerRadius,
                                             width: Self.innerRadius * 2, height: Self.innerRadius * 2), transform: nil)
        hole.fillColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        view.layer?.addSublayer(hole)
    }

    private func sectorPath(center c: CGPoint, index: Int) -> CGPath {
        // AppKit-Layer: y wächst nach oben; Sektor i deckt 45° um i*45° ab.
        let mid = CGFloat(index) * .pi / 4
        let a0 = -(mid - .pi / 8), a1 = -(mid + .pi / 8)
        let p = CGMutablePath()
        p.addArc(center: c, radius: Self.innerRadius, startAngle: a0, endAngle: a1, clockwise: true)
        p.addArc(center: c, radius: Self.radius, startAngle: a1, endAngle: a0, clockwise: false)
        p.closeSubpath()
        return p
    }

    fileprivate func hover(at local: CGPoint, in view: NSView) {
        let c = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let dx = local.x - c.x, dy = local.y - c.y
        let dist = hypot(dx, dy)
        var idx = -1
        if dist >= Self.innerRadius, dist <= Self.radius {
            var angle = atan2(dy, dx)                       // Layer-Koordinaten, y hoch
            if angle < 0 { angle += 2 * .pi }
            idx = Int(((angle + .pi / 8) / (.pi / 4)).rounded(.down)) % 8
            // Auf Bildschirm-Sektoren mappen (unsere Reihenfolge startet bei E
            // und läuft im UZS über SE/S/… — Layer-Winkel laufen gegen den UZS).
            idx = (8 - idx) % 8
        }
        guard idx != highlighted else { return }
        if highlighted >= 0 { sectorLayers[highlighted].fillColor = NSColor.clear.cgColor }
        if idx >= 0 { sectorLayers[idx].fillColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor }
        highlighted = idx
    }

    // Wendet die Zone konsistent zu Drag-to-Edge/Box an: "andere" Fenster auf
    // demselben Monitor (Front-zuerst, ohne floatende Apps) füllen den Rest
    // des Bento-Rasters mit, statt nur das Zielfenster isoliert zu setzen.
    fileprivate func commit() {
        defer { hide() }
        guard highlighted >= 0, let t = target, let f = axFrame(t) else { return }
        let ds = currentDisplays()
        guard let d = ds.first(where: { $0.id == displayID(containing: CGPoint(x: f.midX, y: f.midY), in: ds) })
        else { return }
        let zone = Self.zones[highlighted]
        let others = appWM.otherWindows(on: d, excludingAX: t, pid: axPid(t), cfg: AppConfig.load())
        let plan = BentoLayout.plan(zone: zone, othersAvailable: others.count)
        let frames = Layout.frames(visible: d.visible, vertical: plan.vertical ?? d.vertical, count: plan.tokens.count, split: 0)
        for (i, token) in plan.tokens.enumerated() {
            switch token {
            case .dragged: axSetFrame(t, frames[i])
            case .other(let n) where n < others.count: axSetFrame(others[n].ax, frames[i])
            default: break
            }
        }
        axRaise(t)
    }
}

// Borderless Panel, das Key werden darf (für Escape + Maus-Tracking).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RadialView: NSView {
    weak var radial: RadialMenu?
    init(frame: NSRect, menu: RadialMenu) {
        self.radial = menu
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        radial?.hover(at: convert(event.locationInWindow, from: nil), in: self)
    }
    override func mouseDown(with event: NSEvent) { radial?.commit() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { radial?.hide() } else { radial?.commit() }
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
