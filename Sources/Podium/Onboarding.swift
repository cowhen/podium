import AppKit

// Einmaliges Willkommens-Fenster beim ersten Start: erklärt die zwei nötigen
// Berechtigungen und die Grundbedienung — ohne das passiert nach dem ersten
// Start scheinbar "nichts" (nur zwei kontextlose System-Prompts und ein
// stummes Menüleisten-Icon).
enum Onboarding {
    private static var window: NSWindow?

    static func showIfNeeded() {
        let key = "didShowOnboarding"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }

    static func show() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Willkommen bei PODIUM"
        win.isReleasedWhenClosed = false

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        func para(_ title: String, _ body: String) {
            let t = NSTextField(labelWithString: title)
            t.font = .systemFont(ofSize: 13, weight: .semibold)
            content.addArrangedSubview(t)
            let b = NSTextField(wrappingLabelWithString: body)
            b.font = .systemFont(ofSize: 12)
            b.textColor = .secondaryLabelColor
            b.preferredMaxLayoutWidth = 410
            content.addArrangedSubview(b)
        }

        para("⌥⇥ öffnet das Overlay",
             "Oben die Karte deiner Monitore mit den Vordergrund-Fenstern, unten die Bühne mit allem anderen. Ziehen ordnet zu, Tippen filtert, Ziffern werfen aufs Ziel — jede Aktion wirkt sofort, Escape rollt alles zurück.")
        para("Zwei Berechtigungen nötig",
             "Bedienungshilfen (Fenster bewegen) und Bildschirmaufnahme (Vorschaubilder). Beide unter Systemeinstellungen → Datenschutz & Sicherheit freigeben — PODIUM fragt beim ersten Start automatisch.")
        para("Direkt-Hotkeys ohne Overlay",
             "⌃⌥← / ⌃⌥→ halbieren, ⌃⌥↑ maximiert, ⌃⌥↓ zentriert, ⌃⌥1–4 wirft das aktive Fenster auf Monitor N.")
        para("Hilfe",
             "Im Overlay zeigt ? alle Tastenkürzel; die Fußzeile blendet immer die gerade passenden ein.")

        let button = NSButton(title: "Los geht's", target: win, action: #selector(NSWindow.performClose(_:)))
        button.keyEquivalent = "\r"
        content.addArrangedSubview(button)

        win.contentView = content
        win.setContentSize(content.fittingSize)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}
