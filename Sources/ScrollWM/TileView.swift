import AppKit

// Eine Fenster-Kachel im Overlay: Thumbnail + zweizeiliges Label, ziehbar per
// Maus. In der Karte mit Monitor-Akzentfarbe umrandet, auf der Bühne mit
// farbigem Punkt (= Monitor, auf dem das Fenster gerade liegt). Hover startet
// den Vorschau-Zoom über den Controller.
final class WindowTileView: NSView {
    let info: WinInfo
    var isVisible: Bool
    let accent: NSColor
    weak var controller: OverlayController?

    private let imageView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var dragStart: NSPoint?
    private var ghost: NSImageView?

    init(info: WinInfo, isVisible: Bool, controller: OverlayController, frame: NSRect,
         accent: NSColor = .controlAccentColor, dot: NSColor? = nil, floating: Bool = false) {
        self.info = info
        self.isVisible = isVisible
        self.accent = accent
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        let labelHeight: CGFloat = bounds.height > 60 ? 36 : 0
        imageView.frame = NSRect(x: 3, y: labelHeight, width: bounds.width - 6, height: bounds.height - labelHeight - 3)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        addSubview(imageView)

        if labelHeight > 0 {
            appLabel.frame = NSRect(x: 7, y: 17, width: bounds.width - 14, height: 16)
            appLabel.font = .systemFont(ofSize: 13, weight: .medium)
            appLabel.textColor = .labelColor
            appLabel.lineBreakMode = .byTruncatingTail
            appLabel.stringValue = info.app
            addSubview(appLabel)

            titleLabel.frame = NSRect(x: 7, y: 2, width: bounds.width - 14, height: 14)
            titleLabel.font = .systemFont(ofSize: 11)
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.stringValue = info.title
            addSubview(titleLabel)
        }

        if let dot {
            // NSView ist unten-links orientiert -> oben LINKS platzieren
            // (oben rechts sitzt der Schließen-Knopf).
            let d = NSView(frame: NSRect(x: 7, y: bounds.height - 15, width: 8, height: 8))
            d.wantsLayer = true
            d.layer?.backgroundColor = dot.cgColor
            d.layer?.cornerRadius = 4
            addSubview(d)
        }

        if floating {
            // Floatende Apps verhalten sich fundamental anders (kein Kacheln,
            // kein Greifen) — das muss man der Kachel ansehen.
            let pin = NSImageView(frame: NSRect(x: bounds.width - 42, y: bounds.height - 21, width: 15, height: 15))
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Floatend")?
                .withSymbolConfiguration(cfg)
            pin.contentTintColor = NSColor.white.withAlphaComponent(0.55)
            pin.toolTip = "Floatend — wird beim Ablegen nur zentriert, nie gekachelt"
            addSubview(pin)
        }

        // Schließen-Knopf oben rechts — schließt das ECHTE Fenster.
        let close = NSButton(frame: NSRect(x: bounds.width - 22, y: bounds.height - 22, width: 18, height: 18))
        close.isBordered = false
        close.imagePosition = .imageOnly
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Fenster schließen")?
            .withSymbolConfiguration(cfg)
        close.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        close.target = self
        close.action = #selector(closeTapped)
        close.toolTip = "Fenster schließen"
        addSubview(close)

        applyHighlight()
        loadThumbnail()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeTapped() { controller?.closeRequested(info) }

    private var kbSelected = false
    private var kbGrabbed = false
    private var dimmed = false

    // Tastatur-Auswahl: weißer Ring; im Greifen-Modus orange.
    func setKeyboardSelection(_ on: Bool, grabbed: Bool) {
        kbSelected = on
        kbGrabbed = grabbed
        applyHighlight()
    }

    // Abdunkeln, wenn die Kachel nicht zum aktiven Suchfilter passt.
    func setDimmed(_ on: Bool) {
        guard dimmed != on else { return }
        dimmed = on
        applyHighlight()
    }

    private func applyHighlight() {
        layer?.backgroundColor = (isVisible
            ? accent.withAlphaComponent(0.14)
            : NSColor.white.withAlphaComponent(0.05)).cgColor
        layer?.borderWidth = isVisible ? 2 : 1
        layer?.borderColor = (isVisible ? accent : NSColor.white.withAlphaComponent(0.12)).cgColor
        alphaValue = isVisible ? 1.0 : 0.75
        if kbSelected {
            layer?.borderWidth = 3
            layer?.borderColor = (kbGrabbed ? NSColor.systemOrange : NSColor.white).cgColor
            alphaValue = 1.0
        }
        if dimmed && !kbSelected { alphaValue = 0.3 }
    }

    // Markiert die Kachel während eines Drags als Ersetzungs-/Tausch-Ziel.
    func setDropCandidate(_ on: Bool) {
        if on {
            layer?.borderWidth = 2.5
            layer?.borderColor = NSColor.systemYellow.cgColor
            alphaValue = 1.0
        } else {
            applyHighlight()
        }
    }

    private func loadThumbnail() {
        let wid = info.windowID
        if let cached = ThumbnailCache.shared.image(for: wid) {
            imageView.image = cached   // synchron, kein Flackern beim Rebuild
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = windowThumbnail(wid, maxSize: NSSize(width: 400, height: 300)) ?? appIcon(for: self.info.pid)
            if let img { ThumbnailCache.shared.store(img, for: wid) }
            DispatchQueue.main.async { self.imageView.image = img }
        }
    }

    // Kurzer Bestätigungs-Puls nach erfolgreichem Drop.
    func pulse() {
        guard let layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [1.0, 1.06, 1.0]
        anim.keyTimes = [0, 0.5, 1]
        anim.duration = 0.22
        anim.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        layer.add(anim, forKey: "pulse")
    }

    // MARK: Hover (Vorschau-Zoom)

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { controller?.tileHoverBegan(self) }
    override func mouseExited(with event: NSEvent) { controller?.tileHoverEnded(self) }

    // MARK: Drag

    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let win = window, let root = win.contentView else { return }
        let p = event.locationInWindow
        if ghost == nil, hypot(p.x - start.x, p.y - start.y) > 4 {
            controller?.dragBegan()
            let g = NSImageView(frame: NSRect(origin: .zero, size: NSSize(width: bounds.width * 1.05, height: bounds.height * 1.05)))
            g.image = imageView.image
            g.alphaValue = 0.9
            g.wantsLayer = true
            g.layer?.cornerRadius = 8
            g.layer?.cornerCurve = .continuous
            g.layer?.shadowOpacity = 0.4
            g.layer?.shadowRadius = 12
            g.layer?.shadowOffset = CGSize(width: 0, height: -6)
            root.addSubview(g)
            ghost = g
        }
        // root ist oben-links geflippt; locationInWindow ist immer unten-links -> umrechnen.
        let local = root.convert(p, from: nil)
        ghost?.frame.origin = NSPoint(x: local.x - (ghost?.frame.width ?? 0) / 2, y: local.y - (ghost?.frame.height ?? 0) / 2)
        controller?.dragHover(info, at: p)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; ghost?.removeFromSuperview(); ghost = nil }
        guard ghost != nil else { controller?.tileClicked(info); return }   // reiner Klick, kein Drag
        controller?.dragEnded(info, at: event.locationInWindow)
    }
}
