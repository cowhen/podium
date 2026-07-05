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

// Mehrzeiliger Text-Editor (App-Namen, eine Zeile pro App) mit fester Höhe.
// Meldet Änderungen per onChange, statt sich selbst um Persistenz zu kümmern.
final class AppListEditor: NSScrollView, NSTextViewDelegate {
    let textView = NSTextView()
    var onChange: (([String]) -> Void)?

    init(lines: [String], height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: height))
        borderType = .bezelBorder
        hasVerticalScroller = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        widthAnchor.constraint(equalToConstant: 372).isActive = true

        textView.string = lines.joined(separator: "\n")
        textView.font = .systemFont(ofSize: 12)
        textView.isRichText = false
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        documentView = textView
    }

    required init?(coder: NSCoder) { fatalError() }

    func textDidChange(_ notification: Notification) {
        let names = textView.string.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        onChange?(names)
    }
}

// Einstellungsfenster: Kurzbefehl, Monitor-Farben, App-Listen, Tastatur-Referenz.
final class SettingsWindowController: NSWindowController {
    private var cfg = AppConfig.load()

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
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

        let header = sectionHeader("Monitor-Farben")
        content.addArrangedSubview(header)

        let hint = hintLabel("Farbe für Badge, Rahmen und Bühnen-Punkt je Monitor (von links nach rechts).")
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

        content.addArrangedSubview(separator())

        // App-Listen: ignorierte Apps tauchen im Overlay gar nicht auf,
        // floatende bleiben sichtbar, nehmen aber nie am Kacheln teil.
        content.addArrangedSubview(sectionHeader("Ausgeschlossene Apps"))
        content.addArrangedSubview(hintLabel("Ignoriert — erscheinen gar nicht im Overlay (ein App-Name pro Zeile)."))
        let ignoreEditor = AppListEditor(lines: cfg.ignoreNames, height: 60)
        ignoreEditor.onChange = { [weak self] names in
            self?.cfg.ignoreNames = names
            self?.cfg.save()
        }
        content.addArrangedSubview(ignoreEditor)

        content.addArrangedSubview(hintLabel("Floatend — bleiben sichtbar, werden nie gekachelt (z. B. Finder).") )
        let floatEditor = AppListEditor(lines: cfg.floatingNames, height: 60)
        floatEditor.onChange = { [weak self] names in
            self?.cfg.floatingNames = names
            self?.cfg.save()
        }
        content.addArrangedSubview(floatEditor)
        let floatHint = hintLabel("Finder und Systemeinstellungen sind zusätzlich fest per Bundle-ID hinterlegt.")
        content.addArrangedSubview(floatHint)

        content.addArrangedSubview(separator())

        // Tastatur-Referenz: dieselbe Quelle wie das "?"-Cheatsheet im Overlay.
        content.addArrangedSubview(sectionHeader("Tastatur-Kürzel im Overlay"))
        for line in KeyboardHelp.lines + KeyboardHelp.globalLines where !line.text.isEmpty {
            let l = NSTextField(labelWithString: line.text)
            l.font = line.isHeader ? .systemFont(ofSize: 12, weight: .bold)
                                   : .monospacedSystemFont(ofSize: 11, weight: .regular)
            l.textColor = line.isHeader ? .secondaryLabelColor : .labelColor
            l.lineBreakMode = .byWordWrapping
            l.preferredMaxLayoutWidth = 360
            content.addArrangedSubview(l)
        }

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

private func sectionHeader(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: 13, weight: .semibold)
    return l
}

private func hintLabel(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = .systemFont(ofSize: 11)
    l.textColor = .secondaryLabelColor
    l.lineBreakMode = .byWordWrapping
    l.preferredMaxLayoutWidth = 360
    return l
}

private func separator() -> NSBox {
    let b = NSBox()
    b.boxType = .separator
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 372).isActive = true
    return b
}
