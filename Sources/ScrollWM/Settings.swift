import AppKit
import Carbon.HIToolbox

// Nutzer-Einstellungen (UserDefaults-basiert): Overlay-Kurzbefehl und die
// Akzentfarben der Monitore. Änderungen werden sofort persistiert und per
// Notification an interessierte Stellen (Hotkey-Registrierung) gemeldet.
final class SettingsStore {
    static let shared = SettingsStore()
    static let changed = Notification.Name("PodiumSettingsChanged")

    // Natur-/Erdfarben-Palette: Terrakotta, Salbei, Schieferblau, Ocker,
    // Tanne, Rosenholz — die ersten drei (typische Monitor-Anzahl) maximal
    // unterscheidbar (warm-rot / grün / blau), alle hell genug fürs dunkle
    // Glas-Panel.
    static let defaultColors: [NSColor] = [
        NSColor(srgbRed: 0.796, green: 0.408, blue: 0.263, alpha: 1),   // Terrakotta  #CB6843
        NSColor(srgbRed: 0.561, green: 0.659, blue: 0.463, alpha: 1),   // Salbei      #8FA876
        NSColor(srgbRed: 0.431, green: 0.549, blue: 0.627, alpha: 1),   // Schiefer    #6E8CA0
        NSColor(srgbRed: 0.851, green: 0.659, blue: 0.306, alpha: 1),   // Ocker       #D9A84E
        NSColor(srgbRed: 0.247, green: 0.494, blue: 0.455, alpha: 1),   // Tanne       #3F7E74
        NSColor(srgbRed: 0.725, green: 0.518, blue: 0.455, alpha: 1),   // Rosenholz   #B98474
    ]
    private let d = UserDefaults.standard

    // MARK: Kurzbefehl (Carbon-KeyCode + -Modifier, Default ⌥⇥)

    var hotkeyKeyCode: UInt32 {
        d.object(forKey: "hotkeyKeyCode").flatMap { ($0 as? Int).map(UInt32.init) } ?? UInt32(kVK_Tab)
    }
    var hotkeyMods: UInt32 {
        d.object(forKey: "hotkeyMods").flatMap { ($0 as? Int).map(UInt32.init) } ?? UInt32(optionKey)
    }
    var hotkeyLabel: String {
        d.string(forKey: "hotkeyLabel") ?? "⌥⇥"
    }

    func setHotkey(keyCode: UInt32, mods: UInt32, label: String) {
        d.set(Int(keyCode), forKey: "hotkeyKeyCode")
        d.set(Int(mods), forKey: "hotkeyMods")
        d.set(label, forKey: "hotkeyLabel")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // MARK: Monitor-Farben

    var monitorColors: [NSColor] {
        let stored = (d.array(forKey: "monitorColors") as? [String] ?? []).compactMap(Self.color(fromHex:))
        return stored.isEmpty ? Self.defaultColors
            : (0..<Self.defaultColors.count).map { $0 < stored.count ? stored[$0] : Self.defaultColors[$0] }
    }

    func setMonitorColor(_ color: NSColor, at index: Int) {
        var hex = monitorColors.map(Self.hex(from:))
        while hex.count <= index { hex.append(Self.hex(from: Self.defaultColors[hex.count])) }
        hex[index] = Self.hex(from: color)
        d.set(hex, forKey: "monitorColors")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    func resetColors() {
        d.removeObject(forKey: "monitorColors")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private static func hex(from c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "#%02X%02X%02X", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }

    private static func color(fromHex h: String) -> NSColor? {
        var v: UInt64 = 0
        guard h.hasPrefix("#"), Scanner(string: String(h.dropFirst())).scanHexInt64(&v) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// Button, der beim Klick die nächste Tastenkombination aufnimmt.
// Escape bricht ab; mindestens ein Modifier (⌘/⌥/⌃) ist Pflicht, damit keine
// blanken Buchstaben global verschluckt werden.
final class ShortcutRecorderButton: NSButton {
    private var monitor: Any?

    convenience init() {
        self.init(title: SettingsStore.shared.hotkeyLabel, target: nil, action: nil)
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @objc private func beginRecording() {
        guard monitor == nil else { return }
        title = "Tasten drücken…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil   // Event verschlucken
        }
    }

    private func endRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        title = SettingsStore.shared.hotkeyLabel
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { endRecording(); return }   // Escape = abbrechen
        var mods: UInt32 = 0
        var symbols = ""
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey); symbols += "⌃" }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey); symbols += "⌥" }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey); symbols += "⇧" }
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey); symbols += "⌘" }
        guard mods & ~UInt32(shiftKey) != 0 else { title = "⌘/⌥/⌃ nötig…"; return }
        let label = symbols + Self.keyName(event)
        SettingsStore.shared.setHotkey(keyCode: UInt32(event.keyCode), mods: mods, label: label)
        endRecording()
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}

// Kleines Einstellungsfenster: Kurzbefehl + Monitor-Farben.
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "PODIUM Einstellungen"
        win.isReleasedWhenClosed = false
        self.init(window: win)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        // Kurzbefehl
        let hotkeyRow = NSStackView(views: [label("Overlay ein-/ausblenden:"), ShortcutRecorderButton()])
        hotkeyRow.spacing = 10
        content.addArrangedSubview(hotkeyRow)

        content.addArrangedSubview(separator())

        let header = label("Monitor-Farben")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        content.addArrangedSubview(header)

        let hint = label("Farbe für Badge, Rahmen und Bühnen-Punkt je Monitor (von links nach rechts).")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = 340
        content.addArrangedSubview(hint)

        let colors = SettingsStore.shared.monitorColors
        for i in 0..<4 {
            let well = NSColorWell()
            well.color = colors[i]
            well.tag = i
            well.target = self
            well.action = #selector(colorChanged(_:))
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 52).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let row = NSStackView(views: [label("Monitor \(i + 1):"), well])
            row.spacing = 10
            content.addArrangedSubview(row)
        }

        let reset = NSButton(title: "Standardfarben", target: self, action: #selector(resetColors(_:)))
        content.addArrangedSubview(reset)

        win.contentView = content
        win.setContentSize(content.fittingSize)
        win.center()
    }

    @objc private func colorChanged(_ well: NSColorWell) {
        SettingsStore.shared.setMonitorColor(well.color, at: well.tag)
    }

    @objc private func resetColors(_ sender: NSButton) {
        SettingsStore.shared.resetColors()
        let colors = SettingsStore.shared.monitorColors
        func walk(_ v: NSView) {
            for sub in v.subviews {
                if let well = sub as? NSColorWell, well.tag < colors.count { well.color = colors[well.tag] }
                walk(sub)
            }
        }
        if let cv = window?.contentView { walk(cv) }
    }
}

private func label(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: 13)
    return l
}

private func separator() -> NSBox {
    let b = NSBox()
    b.boxType = .separator
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 352).isActive = true
    return b
}
