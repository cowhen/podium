import AppKit

// Zeigt oben links auf jedem Monitor dessen Nummer (1..N, dieselbe
// Reihenfolge wie bei den Zifferntasten/Werfen) — reine Orientierungshilfe,
// solange die Bühne ODER der Loop-Modus offen ist. Rein visuell
// (ignoresMouseEvents), ein Fenster pro Monitor.
final class MonitorBadgeSet {
    private var windows: [NSWindow] = []
    private static let diameter: CGFloat = 42
    private static let margin: CGFloat = 16

    func show(displays: [Display]) {
        hide()
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        for (i, d) in displays.enumerated() {
            let size = NSSize(width: Self.diameter, height: Self.diameter)
            // Oben-links auf dem Monitor, in Quartz-Koordinaten (minX/minY = oben-links).
            let quartzOrigin = CGPoint(x: d.visible.minX + Self.margin, y: d.visible.minY + Self.margin)
            let origin = NSPoint(x: quartzOrigin.x, y: primaryH - quartzOrigin.y - size.height)
            let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            // Knapp UNTER dem Overlay-Fenster (.floating) — sichtbar über
            // normalen Fenstern, verdeckt aber nie die Bühne (wie LoopPreviewPanel).
            win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            win.hasShadow = true
            win.ignoresMouseEvents = true
            win.isReleasedWhenClosed = false
            win.contentView = BadgeView(number: i + 1, diameter: Self.diameter)
            win.orderFrontRegardless()
            windows.append(win)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

// Echtes Liquid Glass (NSGlassEffectView, öffentliches AppKit-API seit
// macOS 26) statt einer eingefärbten Box — keine Monitor-Akzentfarbe mehr,
// nur die Zahl auf echtem, systemeigenem Glasmaterial. Auf älteren Systemen
// Fallback auf eine geblurrte, kreisrund gemaskte NSVisualEffectView.
// Zentrierung läuft über Auto-Layout-Constraints, nicht über Frame-Raten —
// bei einem einzelnen NSTextField mit fester Frame war die Ziffer optisch
// nicht exakt in der Kreismitte.
private final class BadgeView: NSView {
    init(number: Int, diameter: CGFloat) {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: diameter, height: diameter)))

        let label = NSTextField(labelWithString: "\(number)")
        label.font = NSFont.systemFont(ofSize: 18, weight: .semibold).roundedIfAvailable()
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: bounds)
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.cornerRadius = diameter / 2
            glass.style = .regular
            glass.contentView = content
            addSubview(glass)
        } else {
            let blur = NSVisualEffectView(frame: bounds)
            blur.material = .hudWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = diameter / 2
            blur.layer?.masksToBounds = true
            blur.addSubview(content)
            addSubview(blur)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private extension NSFont {
    func roundedIfAvailable() -> NSFont {
        guard let desc = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: desc, size: pointSize) ?? self
    }
}
