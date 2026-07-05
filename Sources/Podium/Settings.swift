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

    // MARK: Feature-Schalter

    // Bool-Optionen mit explizitem Default (UserDefaults.bool wäre immer false).
    private func flag(_ key: String, default def: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? def
    }

    private func setFlag(_ key: String, _ v: Bool) {
        d.set(v, forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // Hintergrund-Fenster beim Schließen des Overlays minimieren.
    var autoMinimize: Bool {
        get { flag("autoMinimize", default: false) }
        set { setFlag("autoMinimize", newValue) }
    }
    // Radial-Menü (⌃⌥Space) für Schnell-Snapping.
    var radialMenu: Bool {
        get { flag("radialMenu", default: true) }
        set { setFlag("radialMenu", newValue) }
    }
    // Verbundene Ränder: echtes Fenster-Resize zieht die Raster-Nachbarn mit.
    var linkedEdges: Bool {
        get { flag("linkedEdges", default: true) }
        set { setFlag("linkedEdges", newValue) }
    }
    // Gespeichertes Layout beim Erkennen des Monitor-Setups automatisch anwenden.
    var autoApplyLayouts: Bool {
        get { flag("autoApplyLayouts", default: false) }
        set { setFlag("autoApplyLayouts", newValue) }
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

// Einstellungsfenster im System-Settings-Stil: Seitenleiste links, Bereiche
// rechts — Allgemein (Kurzbefehl + Feature-Schalter), Darstellung (Farben),
// Apps (Ignore/Floating), Tastatur (Referenz), Layouts (gespeicherte Setups).
final class SettingsWindowController: NSWindowController {
    private var cfg = AppConfig.load()
    private let contentContainer = NSView()
    private var sidebarButtons: [NSButton] = []
    private var layoutsList: NSStackView?

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "PODIUM Einstellungen"
        win.isReleasedWhenClosed = false
        self.init(window: win)

        let sidebar = NSStackView()
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 2
        sidebar.edgeInsets = NSEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sections = ["Allgemein", "Darstellung", "Apps", "Tastatur", "Layouts"]
        for (i, name) in sections.enumerated() {
            let b = NSButton(title: name, target: self, action: #selector(sidebarClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.alignment = .left
            b.font = .systemFont(ofSize: 13)
            b.contentTintColor = .labelColor
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 150).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            sidebar.addArrangedSubview(b)
            sidebarButtons.append(b)
        }

        let sidebarWrap = NSView()
        sidebarWrap.wantsLayer = true
        sidebarWrap.layer?.backgroundColor = NSColor.windowBackgroundColor.blended(withFraction: 0.06, of: .black)?.cgColor
        sidebarWrap.translatesAutoresizingMaskIntoConstraints = false
        sidebarWrap.addSubview(sidebar)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(sidebarWrap)
        root.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            sidebarWrap.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarWrap.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarWrap.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarWrap.widthAnchor.constraint(equalToConstant: 170),
            sidebar.leadingAnchor.constraint(equalTo: sidebarWrap.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: sidebarWrap.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: sidebarWrap.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        win.contentView = root
        win.center()

        NotificationCenter.default.addObserver(self, selector: #selector(layoutsChanged),
                                               name: LayoutPresetStore.changed, object: nil)
        selectPane(0)
    }

    @objc private func sidebarClicked(_ sender: NSButton) { selectPane(sender.tag) }

    private func selectPane(_ index: Int) {
        for (i, b) in sidebarButtons.enumerated() {
            b.layer?.backgroundColor = i == index
                ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                : NSColor.clear.cgColor
            b.contentTintColor = i == index ? .white : .labelColor
        }
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let pane: NSView
        switch index {
        case 0: pane = paneAllgemein()
        case 1: pane = paneDarstellung()
        case 2: pane = paneApps()
        case 3: pane = paneTastatur()
        default: pane = paneLayouts()
        }
        pane.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            pane.topAnchor.constraint(equalTo: contentContainer.topAnchor),
        ])
    }

    private func stack() -> NSStackView {
        let st = NSStackView()
        st.orientation = .vertical
        st.alignment = .leading
        st.spacing = 12
        st.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        return st
    }

    private func toggleRow(_ title: String, _ hint: String, isOn: Bool, action: Selector) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 2
        let cb = NSButton(checkboxWithTitle: title, target: self, action: action)
        cb.state = isOn ? .on : .off
        box.addArrangedSubview(cb)
        let h = hintLabel(hint)
        box.addArrangedSubview(h)
        return box
    }

    // MARK: Bereiche

    private func paneAllgemein() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Kurzbefehl"))
        let row = NSStackView(views: [label("Overlay ein-/ausblenden:"), ShortcutRecorderButton()])
        row.spacing = 10
        st.addArrangedSubview(row)
        st.addArrangedSubview(separator())
        st.addArrangedSubview(sectionHeader("Verhalten"))
        st.addArrangedSubview(toggleRow("Hintergrund-Fenster beim Schließen minimieren",
            "Bühnen-Fenster wandern ins Dock, wenn das Overlay zugeht (floatende ausgenommen).",
            isOn: SettingsStore.shared.autoMinimize, action: #selector(toggleAutoMinimize(_:))))
        st.addArrangedSubview(toggleRow("Radial-Menü (⌃⌥Space)",
            "Kreis-Menü am Mauszeiger für Hälften, Viertel und Maximieren.",
            isOn: SettingsStore.shared.radialMenu, action: #selector(toggleRadial(_:))))
        st.addArrangedSubview(toggleRow("Verbundene Ränder",
            "Zieht man am echten Rand eines gekachelten Fensters, folgen die Nachbarn.",
            isOn: SettingsStore.shared.linkedEdges, action: #selector(toggleLinked(_:))))
        st.addArrangedSubview(toggleRow("Layouts automatisch anwenden",
            "Beim Erkennen eines gespeicherten Monitor-Setups das Layout wiederherstellen.",
            isOn: SettingsStore.shared.autoApplyLayouts, action: #selector(toggleAutoApply(_:))))
        return st
    }

    private func paneDarstellung() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Monitor-Farben"))
        st.addArrangedSubview(hintLabel("Farbe für Badge, Rahmen und Bühnen-Punkt je Monitor (von links nach rechts)."))
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
            st.addArrangedSubview(row)
        }
        st.addArrangedSubview(NSButton(title: "Standardfarben", target: self, action: #selector(resetColors(_:))))
        return st
    }

    private func paneApps() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Ignorierte Apps"))
        st.addArrangedSubview(hintLabel("Erscheinen gar nicht im Overlay (ein App-Name pro Zeile)."))
        let ignoreEditor = AppListEditor(lines: cfg.ignoreNames, height: 80)
        ignoreEditor.onChange = { [weak self] names in
            self?.cfg.ignoreNames = names
            self?.cfg.save()
        }
        st.addArrangedSubview(ignoreEditor)
        st.addArrangedSubview(sectionHeader("Floatende Apps"))
        st.addArrangedSubview(hintLabel("Bleiben sichtbar, werden aber nie gekachelt — Ablegen zentriert nur (z. B. Finder)."))
        let floatEditor = AppListEditor(lines: cfg.floatingNames, height: 80)
        floatEditor.onChange = { [weak self] names in
            self?.cfg.floatingNames = names
            self?.cfg.save()
        }
        st.addArrangedSubview(floatEditor)
        st.addArrangedSubview(hintLabel("Finder und Systemeinstellungen sind zusätzlich fest per Bundle-ID hinterlegt."))
        return st
    }

    private func paneTastatur() -> NSView {
        let st = stack()
        st.spacing = 4
        for line in KeyboardHelp.lines + KeyboardHelp.globalLines where !line.text.isEmpty {
            let l = NSTextField(labelWithString: line.text)
            l.font = line.isHeader ? .systemFont(ofSize: 12, weight: .bold)
                                   : .monospacedSystemFont(ofSize: 11, weight: .regular)
            l.textColor = line.isHeader ? .secondaryLabelColor : .labelColor
            l.lineBreakMode = .byWordWrapping
            l.preferredMaxLayoutWidth = 470
            st.addArrangedSubview(l)
        }
        return st
    }

    private func paneLayouts() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Gespeicherte Layouts"))
        st.addArrangedSubview(hintLabel("Pro Monitor-Setup ein Layout — PODIUM erkennt das aktive Setup am Fingerabdruck aus Monitornamen und Auflösungen."))
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        layoutsList = list
        st.addArrangedSubview(list)
        rebuildLayoutsList()
        let save = NSButton(title: "＋ Aktuelles Layout speichern", target: self, action: #selector(saveLayoutClicked(_:)))
        st.addArrangedSubview(save)
        return st
    }

    private func rebuildLayoutsList() {
        guard let list = layoutsList else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let active = displaySetFingerprint()
        let presets = LayoutPresetStore.shared.presets
        if presets.isEmpty {
            list.addArrangedSubview(hintLabel("Noch keine Layouts gespeichert."))
            return
        }
        for p in presets {
            let isActive = p.fingerprint == active
            let name = label("\(p.name) · \(p.entries.count) Fenster" + (isActive ? "  ●" : ""))
            if isActive { name.textColor = .systemGreen }
            let apply = NSButton(title: "Anwenden", target: self, action: #selector(applyLayoutClicked(_:)))
            apply.identifier = NSUserInterfaceItemIdentifier(p.fingerprint)
            apply.isEnabled = isActive
            let del = NSButton(title: "Löschen", target: self, action: #selector(deleteLayoutClicked(_:)))
            del.identifier = NSUserInterfaceItemIdentifier(p.fingerprint)
            let row = NSStackView(views: [name, apply, del])
            row.spacing = 10
            list.addArrangedSubview(row)
        }
    }

    // MARK: Aktionen

    @objc private func layoutsChanged() { rebuildLayoutsList() }
    @objc private func saveLayoutClicked(_ sender: NSButton) { LayoutPresetStore.shared.saveCurrent() }
    @objc private func applyLayoutClicked(_ sender: NSButton) {
        guard let fp = sender.identifier?.rawValue,
              let p = LayoutPresetStore.shared.preset(for: fp) else { return }
        LayoutPresetStore.shared.apply(p)
    }
    @objc private func deleteLayoutClicked(_ sender: NSButton) {
        guard let fp = sender.identifier?.rawValue else { return }
        LayoutPresetStore.shared.delete(fingerprint: fp)
    }

    @objc private func toggleAutoMinimize(_ sender: NSButton) { SettingsStore.shared.autoMinimize = sender.state == .on }
    @objc private func toggleRadial(_ sender: NSButton) { SettingsStore.shared.radialMenu = sender.state == .on }
    @objc private func toggleLinked(_ sender: NSButton) { SettingsStore.shared.linkedEdges = sender.state == .on }
    @objc private func toggleAutoApply(_ sender: NSButton) { SettingsStore.shared.autoApplyLayouts = sender.state == .on }

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
