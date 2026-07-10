import AppKit

// Eine Fenster-Kachel im Overlay: Thumbnail + zweizeiliges Label, ziehbar per
// Maus. In der Karte mit Monitor-Akzentfarbe umrandet, auf dem Podium mit
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
    private var checkButton: NSButton?
    private var isChecked = false

    private let isGhost: Bool

    init(info: WinInfo, isVisible: Bool, controller: OverlayController, frame: NSRect,
         accent: NSColor = .controlAccentColor, dot: NSColor? = nil, floating: Bool = false,
         isGhost: Bool = false, checked: Bool = false) {
        self.info = info
        self.isVisible = isVisible
        self.accent = accent
        self.isGhost = isGhost
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

        // Auto-Arrange-Häkchen oben links (Leertaste toggelt dasselbe für die
        // Tastatur-Auswahl) — der Monitor-Punkt rutscht dafür ein Stück nach rechts.
        let check = NSButton(frame: NSRect(x: 3, y: bounds.height - 22, width: 18, height: 18))
        check.isBordered = false
        check.imagePosition = .imageOnly
        check.target = self
        check.action = #selector(checkTapped)
        check.toolTip = "Für Auto-Arrange auswählen (Leertaste)"
        addSubview(check)
        checkButton = check
        isChecked = checked
        applyCheckState()

        if let dot {
            // NSView ist unten-links orientiert -> oben LINKS platzieren
            // (oben rechts sitzt der Schließen-Knopf).
            let d = NSView(frame: NSRect(x: 29, y: bounds.height - 15, width: 8, height: 8))
            d.wantsLayer = true
            d.layer?.backgroundColor = dot.cgColor
            d.layer?.cornerRadius = 4
            addSubview(d)
        }

        if info.minimized {
            // Minimiert-Kennzeichen: Fenster liegt im Dock, Klick holt es zurück.
            let m = NSImageView(frame: NSRect(x: bounds.width - 42, y: bounds.height - 21, width: 15, height: 15))
            let mcfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            m.image = NSImage(systemSymbolName: "arrow.down.app.fill", accessibilityDescription: "Minimiert")?
                .withSymbolConfiguration(mcfg)
            m.contentTintColor = NSColor.systemYellow.withAlphaComponent(0.8)
            m.toolTip = "Minimiert — Klick oder Ablegen holt das Fenster zurück"
            addSubview(m)
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
    @objc private func checkTapped() { controller?.tileCheckToggled(info) }

    // Nur die Anzeige — die Wahrheit liegt beim Controller (`checked`-Liste),
    // der bei jedem Rebuild den aktuellen Stand über `checked:` reinreicht.
    private func applyCheckState() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let name = isChecked ? "checkmark.circle.fill" : "circle"
        checkButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Für Auto-Arrange auswählen")?
            .withSymbolConfiguration(cfg)
        checkButton?.contentTintColor = isChecked
            ? NSColor.systemGreen
            : NSColor.white.withAlphaComponent(0.35)
    }

    private var kbSelected = false
    private var dimmed = false

    // Tastatur-Auswahl: weißer Ring.
    func setKeyboardSelection(_ on: Bool) {
        kbSelected = on
        applyHighlight()
    }

    // Auto-Arrange-Häkchen von außen (Leertaste) nachziehen, ohne die ganze
    // Kachel neu aufzubauen.
    func setChecked(_ on: Bool) {
        guard isChecked != on else { return }
        isChecked = on
        applyCheckState()
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
        // Geister-Kacheln: Hintergrund-Fenster in der Karte an ihrer echten
        // Position — deutlich abgesetzt, damit klar ist, was NICHT zum
        // Kachel-Raster gehört.
        alphaValue = isGhost ? 0.45 : (isVisible ? 1.0 : 0.75)
        if kbSelected {
            layer?.borderWidth = 3
            layer?.borderColor = NSColor.white.cgColor
            alphaValue = 1.0
        }
        if dimmed && !kbSelected { alphaValue = 0.3 }
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

    // Rechtsklick: Aktionsmenü (fokussieren/minimieren/ausblenden/schließen/
    // App beenden) — direkt hier statt über die Responder-Chain, da Kacheln
    // den Rechtsklick zuerst abbekommen.
    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.tileMenu(for: info)
    }

    // MARK: Klick

    // Einzelklick verzögert ausführen: ein Doppelklick liefert ERST ein
    // clickCount==1-Event — würde das sofort feuern, wäre der Doppelklick-
    // Pfad unerreichbar (und der zweite Klick träfe schon den Loop-Catcher).
    private var pendingClick: DispatchWorkItem?

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            pendingClick?.cancel()
            pendingClick = nil
            controller?.tileDoubleClicked(info)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingClick = nil
            self.controller?.tileClicked(self.info)
        }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }
}
