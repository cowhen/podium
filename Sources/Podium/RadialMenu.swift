import AppKit
import Carbon.HIToolbox

// Radial-Menü im Loop-Stil (⌃⌥Space): erscheint am Mauszeiger, 8 Sektoren
// für Hälften/Viertel plus Zentrum-Aktionen. Hover wählt, Klick wendet auf
// das zuvor fokussierte Fenster an, Escape/Klick ins Zentrum bricht ab.
// Abschaltbar in den Einstellungen.
final class RadialMenu: NSObject {
    static let shared = RadialMenu()

    private var window: NSWindow?
    private var target: AXUIElement?
    private var highlighted: Int = -1
    private var sectorLayers: [CAShapeLayer] = []

    private static let radius: CGFloat = 110
    private static let innerRadius: CGFloat = 34

    // Sektoren im Uhrzeigersinn ab Osten: E, SE, S, SW, W, NW, N, NE.
    // (Bildschirm-y wächst nach unten -> Winkel gespiegelt behandeln.)
    private struct Action {
        let symbol: String
        let apply: (AXUIElement, Display) -> Void
    }

    private static func half(_ w: AXUIElement, _ d: Display, right: Bool) {
        let f = Layout.frames(visible: d.visible, vertical: false, count: 2, split: 0)
        axSetFrame(w, right ? f[1] : f[0])
    }

    private static func vhalf(_ w: AXUIElement, _ d: Display, bottom: Bool) {
        let f = Layout.frames(visible: d.visible, vertical: true, count: 2, split: 0)
        axSetFrame(w, bottom ? f[1] : f[0])
    }

    private static func quarter(_ w: AXUIElement, _ d: Display, right: Bool, bottom: Bool) {
        let f = Layout.frames(visible: d.visible, vertical: false, count: 4, split: 0)
        // Slots zeilen-major: 0=oben-links 1=oben-rechts 2=unten-links 3=unten-rechts
        let idx = (bottom ? 2 : 0) + (right ? 1 : 0)
        axSetFrame(w, f[idx])
    }

    private let actions: [Action] = [
        Action(symbol: "rectangle.righthalf.filled") { half($0, $1, right: true) },
        Action(symbol: "rectangle.inset.bottomright.filled") { quarter($0, $1, right: true, bottom: true) },
        Action(symbol: "rectangle.bottomhalf.filled") { vhalf($0, $1, bottom: true) },
        Action(symbol: "rectangle.inset.bottomleft.filled") { quarter($0, $1, right: false, bottom: true) },
        Action(symbol: "rectangle.lefthalf.filled") { half($0, $1, right: false) },
        Action(symbol: "rectangle.inset.topleft.filled") { quarter($0, $1, right: false, bottom: false) },
        Action(symbol: "rectangle.fill") { w, d in axSetFrame(w, d.visible.insetBy(dx: Layout.gap, dy: Layout.gap)) },
        Action(symbol: "rectangle.inset.topright.filled") { quarter($0, $1, right: true, bottom: false) },
    ]

    func toggle() {
        window == nil ? show() : hide()
    }

    private func show() {
        // Ziel VOR dem Anzeigen merken — unser Panel stiehlt gleich den Fokus.
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let t = axCopy(axApp, kAXFocusedWindowAttribute as String) else { return }
        target = (t as! AXUIElement)

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
            let img = NSImage(systemSymbolName: actions[i].symbol, accessibilityDescription: nil)?
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

    fileprivate func commit() {
        defer { hide() }
        guard highlighted >= 0, let t = target else { return }
        guard let f = axFrame(t),
              let d = currentDisplays().first(where: {
                  $0.id == displayID(containing: CGPoint(x: f.midX, y: f.midY), in: currentDisplays())
              }) else { return }
        actions[highlighted].apply(t, d)
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
