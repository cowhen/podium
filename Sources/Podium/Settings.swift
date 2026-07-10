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
    // Fenster beim Ziehen an den Bildschirmrand auf die halbe Fläche snappen.
    var dragSnap: Bool {
        get { flag("dragSnap", default: true) }
        set { setFlag("dragSnap", newValue) }
    }
    // Podium: Fenster nach App gruppieren (mit Gruppenkopf) statt als eine
    // flache, nur nach Z-Order sortierte Liste.
    var stageGroupByApp: Bool {
        get { flag("stageGroupByApp", default: true) }
        set { setFlag("stageGroupByApp", newValue) }
    }
    // Interaktionsmodell des Podiums: false = Enter/Klick öffnen den Loop-Modus
    // (⌘↵/Doppelklick wechseln nur), true = Enter/Klick wechseln nur wie ein
    // klassischer Switcher (Loop-Modus über ⌘↵). Die Leertaste ist in beiden
    // Modi fürs Auto-Arrange-Häkchen reserviert (siehe tileCheckToggled).
    var stageEnterSwitches: Bool {
        get { flag("stageEnterSwitches", default: false) }
        set { setFlag("stageEnterSwitches", newValue) }
    }

    // MARK: Direkt-Hotkey-Bindings (Einstellungen → Hotkeys)

    // Pro Aktion optional ein Binding; "cleared" markiert bewusst gelöschte
    // Werks-Defaults (sonst kämen sie beim nächsten Start zurück).
    func directBinding(for key: String) -> (keyCode: UInt32, mods: UInt32, label: String)? {
        guard let dict = d.dictionary(forKey: "direct.\(key)"),
              let code = dict["keyCode"] as? Int, let mods = dict["mods"] as? Int,
              let label = dict["label"] as? String else { return nil }
        return (UInt32(code), UInt32(mods), label)
    }

    func directBindingCleared(_ key: String) -> Bool {
        (d.dictionary(forKey: "direct.\(key)")?["cleared"] as? Bool) ?? false
    }

    func setDirectBinding(for key: String, keyCode: UInt32, mods: UInt32, label: String) {
        d.set(["keyCode": Int(keyCode), "mods": Int(mods), "label": label], forKey: "direct.\(key)")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    func clearDirectBinding(for key: String) {
        d.set(["cleared": true], forKey: "direct.\(key)")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // MARK: Zahlen-Optionen mit explizitem Default.

    private func number(_ key: String, default def: CGFloat) -> CGFloat {
        (d.object(forKey: key) as? Double).map { CGFloat($0) } ?? def
    }

    private func setNumber(_ key: String, _ v: CGFloat) {
        d.set(Double(v), forKey: key)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // Breite einer Podiums-Kachel — Höhe folgt im festen Seitenverhältnis von
    // Tuning.stageTileSize. Größere Kacheln lassen pro Zeile weniger Platz,
    // das Podium bricht dann automatisch mehrzeilig um (bestehende
    // Flow-Layout-Logik in StageView, unverändert).
    var stageTileWidth: CGFloat {
        get { number("stageTileWidth", default: Tuning.stageTileSize.width) }
        set { setNumber("stageTileWidth", newValue) }
    }

    // MARK: Loop-Modus

    // Füllmodus, mit dem der Loop-Ring bei jeder neuen Sitzung startet (F/
    // Rechtsklick cyclen innerhalb der Sitzung live weiter). Ohne gespeicherten
    // Wert liefert d.integer(forKey:) 0 zurück — das ist bereits
    // LoopFillMode.solo.rawValue, also kein gesonderter Existenz-Check nötig.
    var defaultFillMode: LoopFillMode {
        get { LoopFillMode(rawValue: d.integer(forKey: "defaultFillMode")) ?? .solo }
        set {
            d.set(newValue.rawValue, forKey: "defaultFillMode")
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
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
    // Generalisiert: get liefert das aktuelle Label (nil = unbelegt), commit
    // persistiert die neue Kombination. Default = Overlay-Hotkey.
    private var getLabel: () -> String? = { SettingsStore.shared.hotkeyLabel }
    private var commit: (UInt32, UInt32, String) -> Void = {
        SettingsStore.shared.setHotkey(keyCode: $0, mods: $1, label: $2)
    }

    convenience init() {
        self.init(title: "", target: nil, action: nil)
        finishSetup()
    }

    convenience init(getLabel: @escaping () -> String?,
                     commit: @escaping (UInt32, UInt32, String) -> Void) {
        self.init(title: "", target: nil, action: nil)
        self.getLabel = getLabel
        self.commit = commit
        finishSetup()
    }

    private func finishSetup() {
        title = getLabel() ?? "–"
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func refreshTitle() { title = getLabel() ?? "–" }

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
        refreshTitle()
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
        commit(UInt32(event.keyCode), mods, label)
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
    private var groupsList: NSStackView?

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

        let sections = ["Allgemein", "Hotkeys", "Darstellung", "Apps", "Tastatur", "Layouts"]
        for (i, name) in sections.enumerated() {
            let b = NSButton(title: name, target: self, action: #selector(sidebarClicked(_:)))
            b.tag = i
            b.isBordered = false
            b.alignment = .left
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 160).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
            sidebarWrap.widthAnchor.constraint(equalToConstant: 184),
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
        let sections = ["Allgemein", "Hotkeys", "Darstellung", "Apps", "Tastatur", "Layouts"]
        for (i, b) in sidebarButtons.enumerated() {
            b.layer?.backgroundColor = i == index
                ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                : NSColor.clear.cgColor
            // Einzug + Farbe über attributedTitle — contentTintColor greift
            // bei Borderless-Buttons mit Alignment nicht zuverlässig.
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 10
            b.attributedTitle = NSAttributedString(string: sections[i], attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: i == index ? .medium : .regular),
                .foregroundColor: i == index ? NSColor.white : NSColor.labelColor,
                .paragraphStyle: para,
            ])
        }
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let pane: NSView
        switch index {
        case 0: pane = paneAllgemein()
        case 1: pane = paneHotkeys()
        case 2: pane = paneDarstellung()
        case 3: pane = paneApps()
        case 4: pane = paneTastatur()
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
        st.addArrangedSubview(sectionHeader("Verhalten"))
        st.addArrangedSubview(toggleRow("Enter/Klick wechselt nur (Loop-Modus über ⌘↵)",
            "An: Enter/Klick fokussieren das Fenster und schließen (klassischer Switcher), ⌘↵ öffnet den Loop-Modus. Aus: Enter/Klick öffnen den Loop-Modus, ⌘↵ oder Doppelklick wechseln nur. In beiden Modi: Leertaste kreuzt ein Fenster fürs Auto-Arrange an — bei ≥2 Häkchen verteilt Enter sie proportional auf alle Monitore.",
            isOn: SettingsStore.shared.stageEnterSwitches, action: #selector(toggleEnterSwitches(_:))))
        st.addArrangedSubview(toggleRow("Hintergrund-Fenster beim Schließen minimieren",
            "Podiums-Fenster wandern ins Dock, wenn das Overlay zugeht (floatende ausgenommen).",
            isOn: SettingsStore.shared.autoMinimize, action: #selector(toggleAutoMinimize(_:))))
        st.addArrangedSubview(toggleRow("Verbundene Ränder",
            "Ziehst du eine echte Fensterkante langsam, passen sich angrenzende Fenster automatisch mit an — schnell/ruckartig gezogen bleiben sie unberührt. Keine Taste nötig; ⌃ (Control) gehalten erzwingt trotzdem immer verbunden, unabhängig vom Tempo (Sicherheitsnetz für Trackpad/Motorik).",
            isOn: SettingsStore.shared.linkedEdges, action: #selector(toggleLinked(_:))))
        st.addArrangedSubview(toggleRow("Layouts automatisch anwenden",
            "Beim Erkennen eines gespeicherten Monitor-Setups das Layout wiederherstellen.",
            isOn: SettingsStore.shared.autoApplyLayouts, action: #selector(toggleAutoApply(_:))))
        st.addArrangedSubview(toggleRow("Drag-to-Edge-Snap",
            "Ein Fenster an den Bildschirmrand ziehen füllt die halbe Fläche — zwei so gezogene Fenster ergeben einen Split.",
            isOn: SettingsStore.shared.dragSnap, action: #selector(toggleDragSnap(_:))))
        st.addArrangedSubview(separator())
        st.addArrangedSubview(sectionHeader("Loop-Modus"))
        let fillPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fillPopup.addItems(withTitles: ["Solo", "3 größte", "Alle"])
        fillPopup.selectItem(at: SettingsStore.shared.defaultFillMode.rawValue)
        fillPopup.target = self
        fillPopup.action = #selector(fillModeChanged(_:))
        let fillRow = NSStackView(views: [label("Start-Füllmodus:"), fillPopup])
        fillRow.spacing = 10
        st.addArrangedSubview(fillRow)
        st.addArrangedSubview(hintLabel("Womit eine neue Loop-Sitzung beginnt. F oder Rechtsklick cyclen innerhalb der Sitzung live weiter: Solo → 3 größte Nachbarn → alle Nachbarn."))
        return st
    }

    // Eine Zeile pro Direkt-Aktion: Name + Recorder + Löschen. Frei belegbar,
    // die klassischen ⌃⌥-Kürzel sind Werks-Defaults. Der Aktivierungs-Hotkey
    // (Podium ein-/ausblenden) steht oben mit auf dieser Seite — alle
    // globalen Hotkeys an einem Ort, statt über Allgemein/Hotkeys verteilt.
    private func paneHotkeys() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Aktivierung"))
        let activationRow = NSStackView(views: [label("Podium ein-/ausblenden:"), ShortcutRecorderButton()])
        activationRow.spacing = 10
        st.addArrangedSubview(activationRow)
        st.addArrangedSubview(separator())
        st.addArrangedSubview(sectionHeader("Direkt-Hotkeys (ohne Overlay)"))
        st.addArrangedSubview(hintLabel("Wirken sofort auf das fokussierte Fenster der vordersten App. Klick auf die Taste nimmt eine neue Kombination auf (Escape bricht ab), – löscht die Belegung."))

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        for action in DirectActions.actions {
            let key = action.key
            let name = label(action.name)
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 190).isActive = true
            let recorder = ShortcutRecorderButton(
                getLabel: {
                    if SettingsStore.shared.directBindingCleared(key) { return nil }
                    return SettingsStore.shared.directBinding(for: key)?.label ?? action.defaultBinding?.label
                },
                commit: { code, mods, label in
                    SettingsStore.shared.setDirectBinding(for: key, keyCode: code, mods: mods, label: label)
                })
            let clear = NSButton(title: "–", target: self, action: #selector(clearHotkeyClicked(_:)))
            clear.identifier = NSUserInterfaceItemIdentifier(key)
            let row = NSStackView(views: [name, recorder, clear])
            row.spacing = 8
            rows.addArrangedSubview(row)
        }

        let clip = NSScrollView()
        clip.hasVerticalScroller = true
        clip.drawsBackground = false
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.heightAnchor.constraint(equalToConstant: 380).isActive = true
        clip.widthAnchor.constraint(equalToConstant: 440).isActive = true
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            rows.topAnchor.constraint(equalTo: flipped.topAnchor),
            rows.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            flipped.bottomAnchor.constraint(equalTo: rows.bottomAnchor),
            flipped.widthAnchor.constraint(equalToConstant: 420),
        ])
        clip.documentView = flipped
        st.addArrangedSubview(clip)
        return st
    }

    @objc private func clearHotkeyClicked(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        SettingsStore.shared.clearDirectBinding(for: key)
        selectPane(1)   // Pane neu aufbauen, Recorder-Titel spiegeln den neuen Zustand
    }

    private func paneDarstellung() -> NSView {
        let st = stack()
        st.addArrangedSubview(sectionHeader("Podium"))
        st.addArrangedSubview(toggleRow("Fenster nach App gruppieren",
            "Gruppenkopf mit Icon/Name/Anzahl je App statt einer flachen, nur nach Z-Order sortierten Liste.",
            isOn: SettingsStore.shared.stageGroupByApp, action: #selector(toggleGroupByApp(_:))))
        let sizeRow = NSStackView(views: [label("Kachelgröße:"), tileSizeSlider()])
        sizeRow.spacing = 10
        st.addArrangedSubview(sizeRow)
        st.addArrangedSubview(hintLabel("Größere Kacheln zeigen mehr vom Fenster, lassen aber weniger pro Zeile zu — das Podium wächst dann passend in die Höhe und wird mehrzeilig."))
        st.addArrangedSubview(separator())
        st.addArrangedSubview(sectionHeader("Monitor-Farben"))
        st.addArrangedSubview(hintLabel("Farbe für Badge, Rahmen und Podiums-Punkt je Monitor (von links nach rechts)."))
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

    private func tileSizeSlider() -> NSSlider {
        let s = NSSlider(value: Double(SettingsStore.shared.stageTileWidth), minValue: 110, maxValue: 320,
                         target: self, action: #selector(tileSizeChanged(_:)))
        s.isContinuous = true
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return s
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
        st.addArrangedSubview(separator())
        st.addArrangedSubview(sectionHeader("Gruppen (Auto-Arrange)"))
        st.addArrangedSubview(hintLabel("Angekreuzte Fenster derselben Gruppe landen beim Auto-Arrange garantiert auf demselben Monitor (ein App-Name pro Zeile, wie oben)."))
        let groupsList = NSStackView()
        groupsList.orientation = .vertical
        groupsList.alignment = .leading
        groupsList.spacing = 8
        self.groupsList = groupsList
        st.addArrangedSubview(groupsList)
        rebuildGroupsList()
        let addGroup = NSButton(title: "＋ Gruppe hinzufügen", target: self, action: #selector(addGroupClicked(_:)))
        st.addArrangedSubview(addGroup)
        return st
    }

    private func rebuildGroupsList() {
        guard let list = groupsList else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if cfg.groups.isEmpty {
            list.addArrangedSubview(hintLabel("Noch keine Gruppen angelegt."))
            return
        }
        // Stabile Anzeige-Reihenfolge (Dictionary hat keine) — alphabetisch.
        for name in cfg.groups.keys.sorted() {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4
            let del = NSButton(title: "Löschen", target: self, action: #selector(deleteGroupClicked(_:)))
            del.identifier = NSUserInterfaceItemIdentifier(name)
            let header = NSStackView(views: [label(name), del])
            header.spacing = 8
            row.addArrangedSubview(header)
            let editor = AppListEditor(lines: cfg.groups[name] ?? [], height: 60)
            editor.onChange = { [weak self] apps in
                self?.cfg.groups[name] = apps
                self?.cfg.save()
            }
            row.addArrangedSubview(editor)
            list.addArrangedSubview(row)
            list.addArrangedSubview(separator())
        }
    }

    @objc private func addGroupClicked(_ sender: NSButton) {
        var n = 1
        var name = "Gruppe \(n)"
        while cfg.groups[name] != nil { n += 1; name = "Gruppe \(n)" }
        cfg.groups[name] = []
        cfg.save()
        rebuildGroupsList()
    }

    @objc private func deleteGroupClicked(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        cfg.groups.removeValue(forKey: name)
        cfg.save()
        rebuildGroupsList()
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
            let applyAndLaunch = NSButton(title: "+ Apps starten", target: self, action: #selector(applyAndLaunchClicked(_:)))
            applyAndLaunch.identifier = NSUserInterfaceItemIdentifier(p.fingerprint)
            applyAndLaunch.isEnabled = isActive
            let del = NSButton(title: "Löschen", target: self, action: #selector(deleteLayoutClicked(_:)))
            del.identifier = NSUserInterfaceItemIdentifier(p.fingerprint)
            let row = NSStackView(views: [name, apply, applyAndLaunch, del])
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
    @objc private func applyAndLaunchClicked(_ sender: NSButton) {
        guard let fp = sender.identifier?.rawValue,
              let p = LayoutPresetStore.shared.preset(for: fp) else { return }
        LayoutPresetStore.shared.applyLaunchingMissingApps(p)
    }
    @objc private func deleteLayoutClicked(_ sender: NSButton) {
        guard let fp = sender.identifier?.rawValue else { return }
        LayoutPresetStore.shared.delete(fingerprint: fp)
    }

    @objc private func toggleAutoMinimize(_ sender: NSButton) { SettingsStore.shared.autoMinimize = sender.state == .on }
    @objc private func toggleLinked(_ sender: NSButton) { SettingsStore.shared.linkedEdges = sender.state == .on }
    @objc private func toggleAutoApply(_ sender: NSButton) { SettingsStore.shared.autoApplyLayouts = sender.state == .on }
    @objc private func toggleDragSnap(_ sender: NSButton) { SettingsStore.shared.dragSnap = sender.state == .on }
    @objc private func toggleGroupByApp(_ sender: NSButton) { SettingsStore.shared.stageGroupByApp = sender.state == .on }
    @objc private func toggleEnterSwitches(_ sender: NSButton) { SettingsStore.shared.stageEnterSwitches = sender.state == .on }
    @objc private func tileSizeChanged(_ sender: NSSlider) { SettingsStore.shared.stageTileWidth = CGFloat(sender.doubleValue) }
    @objc private func fillModeChanged(_ sender: NSPopUpButton) {
        SettingsStore.shared.defaultFillMode = LoopFillMode(rawValue: sender.indexOfSelectedItem) ?? .solo
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
