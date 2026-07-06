import AppKit

// Tab-Leisten für gestapelte Slots: eine schmale, immer sichtbare Leiste am
// oberen Rand des Slot-Bereichs, ein Knopf pro Fenster im Stapel, Klick holt
// das Fenster nach vorn. Eigene Podium-UI (NSPanel, öffentliche API) — echte
// app-übergreifende Tabs kennt macOS nicht. Die Leisten überleben das
// Schließen des Overlays; das ist der Sinn des Modus.
final class TabBars {
    static let shared = TabBars()
    static let barHeight: CGFloat = 30

    private var panels: [CGDirectDisplayID: NSPanel] = [:]

    // Leiste für einen Stapel (neu) aufbauen. slotQuartzRect = Bereich des
    // Slots in Quartz-Koordinaten (oben-links), wins = Stapel-Fenster in
    // Reihenfolge, active = aktuell vorderstes.
    func update(displayID id: CGDirectDisplayID, slotQuartzRect: CGRect,
                wins: [WinInfo], active: CGWindowID?) {
        remove(id)
        guard wins.count >= 2 else { return }

        // Quartz (oben-links) -> AppKit (unten-links, globale Koordinaten).
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: slotQuartzRect.minX,
                          y: primaryH - slotQuartzRect.minY - Self.barHeight,
                          width: slotQuartzRect.width, height: Self.barHeight)

        let panel = NSPanel(contentRect: rect,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // Keine feste Appearance setzen -> folgt automatisch dem System
        // (Hell/Dunkel), damit Hintergrund und Text (labelColor) zusammenpassen.

        let content = TabBarView(frame: NSRect(origin: .zero, size: rect.size), wins: wins, active: active)
        panel.contentView = content
        panel.orderFrontRegardless()
        panels[id] = panel
    }

    func remove(_ id: CGDirectDisplayID) {
        panels.removeValue(forKey: id)?.orderOut(nil)
    }

    func removeAll() {
        panels.keys.forEach { panels[$0]?.orderOut(nil) }
        panels = [:]
    }
}

// Die eigentliche Leiste: dunkler Streifen mit App-Icon+Titel-Knöpfen.
private final class TabBarView: NSView {
    private let wins: [WinInfo]

    init(frame: NSRect, wins: [WinInfo], active: CGWindowID?) {
        self.wins = wins
        super.init(frame: frame)
        wantsLayer = true
        // Systemfarbe statt hartkodiertem Dunkel — sonst rendert der Text
        // (labelColor, folgt dem System-Modus) im Hellmodus schwarz auf
        // schwarzem Grund. windowBackgroundColor passt sich automatisch an.
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]   // nur oben rund
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let maxTabs = min(wins.count, 8)
        let tabW = min(220, (bounds.width - 8) / CGFloat(maxTabs))
        for (i, w) in wins.prefix(maxTabs).enumerated() {
            let btn = NSButton(frame: NSRect(x: 4 + CGFloat(i) * tabW, y: 3,
                                             width: tabW - 4, height: bounds.height - 6))
            btn.bezelStyle = .accessoryBarAction
            btn.attributedTitle = Self.title(for: w, active: w.windowID == active)
            btn.lineBreakMode = .byTruncatingTail
            if let icon = NSRunningApplication(processIdentifier: w.pid)?.icon {
                icon.size = NSSize(width: 14, height: 14)
                btn.image = icon
            }
            btn.imagePosition = .imageLeading
            btn.tag = i
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            if w.windowID == active {
                btn.wantsLayer = true
                btn.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                btn.layer?.cornerRadius = 6
            }
            addSubview(btn)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // labelColor/secondaryLabelColor sind System-adaptiv (schwarz im Hell-,
    // weiß im Dunkelmodus) — garantiert Kontrast statt sich auf die
    // Standard-Bezel-Textfarbe zu verlassen, die für unseren eigenen
    // Hintergrund nicht immer passt.
    private static func title(for w: WinInfo, active: Bool) -> NSAttributedString {
        let text = w.app + (w.title.isEmpty ? "" : " — \(w.title)")
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .regular),
            .foregroundColor: active ? NSColor.controlAccentColor : NSColor.labelColor,
        ])
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard sender.tag < wins.count else { return }
        let w = wins[sender.tag]
        // Fenster nach vorn holen und Aktiv-Markierung umsetzen.
        axFocus(w.ax)
        for (i, view) in subviews.enumerated() {
            guard let b = view as? NSButton else { continue }
            let isActive = i == sender.tag
            b.attributedTitle = Self.title(for: wins[i], active: isActive)
            b.layer?.backgroundColor = isActive
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
        }
    }
}
