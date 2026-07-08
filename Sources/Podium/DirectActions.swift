import AppKit
import Carbon.HIToolbox

// Direkt-Hotkeys ohne Overlay (der Rectangle-Kern): wirken sofort auf das
// fokussierte Fenster der vordersten App. Jede Aktion ist frei belegbar
// (Einstellungen → Hotkeys); die klassischen ⌃⌥-Kürzel sind die
// Werks-Defaults. Frames kommen aus LoopEngine — dieselbe Mathematik wie im
// Loop-Modus, keine zweite Layout-Logik.
enum DirectActions {
    struct Action {
        let key: String          // UserDefaults-Schlüssel ("direct.<key>")
        let name: String         // Anzeige in den Einstellungen
        let defaultBinding: (keyCode: UInt32, mods: UInt32, label: String)?
        let run: () -> Void
    }

    // Feste, kuratierte Reihenfolge — Index bestimmt die HotKeyCenter-ID (100+i).
    static let actions: [Action] = {
        let cO = UInt32(controlKey | optionKey)
        func edge(_ zone: BentoZone, _ variant: EdgeVariant) -> () -> Void {
            { applyFrame { d, _ in LoopEngine.frame(zone: zone, variant: variant, in: d.visible) } }
        }
        func general(_ a: GeneralAction) -> () -> Void {
            { applyFrame { d, f in LoopEngine.generalFrame(a, in: d.visible, current: f) } }
        }
        return [
            Action(key: "leftHalf", name: "Linke Hälfte",
                   defaultBinding: (UInt32(kVK_LeftArrow), cO, "⌃⌥←"), run: edge(.left, .half)),
            Action(key: "rightHalf", name: "Rechte Hälfte",
                   defaultBinding: (UInt32(kVK_RightArrow), cO, "⌃⌥→"), run: edge(.right, .half)),
            Action(key: "topHalf", name: "Obere Hälfte", defaultBinding: nil, run: edge(.top, .half)),
            Action(key: "bottomHalf", name: "Untere Hälfte", defaultBinding: nil, run: edge(.bottom, .half)),
            Action(key: "leftThird", name: "Linkes Drittel", defaultBinding: nil, run: edge(.left, .third)),
            Action(key: "rightThird", name: "Rechtes Drittel", defaultBinding: nil, run: edge(.right, .third)),
            Action(key: "leftTwoThirds", name: "Linke zwei Drittel", defaultBinding: nil, run: edge(.left, .twoThirds)),
            Action(key: "rightTwoThirds", name: "Rechte zwei Drittel", defaultBinding: nil, run: edge(.right, .twoThirds)),
            Action(key: "topLeft", name: "Ecke oben links", defaultBinding: nil, run: edge(.topLeft, .half)),
            Action(key: "topRight", name: "Ecke oben rechts", defaultBinding: nil, run: edge(.topRight, .half)),
            Action(key: "bottomLeft", name: "Ecke unten links", defaultBinding: nil, run: edge(.bottomLeft, .half)),
            Action(key: "bottomRight", name: "Ecke unten rechts", defaultBinding: nil, run: edge(.bottomRight, .half)),
            Action(key: "maximize", name: "Maximieren",
                   defaultBinding: (UInt32(kVK_UpArrow), cO, "⌃⌥↑"), run: general(.maximize)),
            Action(key: "almostMaximize", name: "Fast maximieren", defaultBinding: nil, run: general(.almostMaximize)),
            Action(key: "center", name: "Zentrieren",
                   defaultBinding: (UInt32(kVK_DownArrow), cO, "⌃⌥↓"), run: general(.center)),
            Action(key: "maxHeight", name: "Volle Höhe", defaultBinding: nil, run: general(.maximizeHeight)),
            Action(key: "maxWidth", name: "Volle Breite", defaultBinding: nil, run: general(.maximizeWidth)),
            Action(key: "undo", name: "Rückgängig (Ursprungsgröße)", defaultBinding: nil, run: { undoFrame() }),
            Action(key: "display1", name: "Auf Monitor 1 werfen",
                   defaultBinding: (UInt32(kVK_ANSI_1), cO, "⌃⌥1"), run: { throwToDisplay(0) }),
            Action(key: "display2", name: "Auf Monitor 2 werfen",
                   defaultBinding: (UInt32(kVK_ANSI_2), cO, "⌃⌥2"), run: { throwToDisplay(1) }),
            Action(key: "display3", name: "Auf Monitor 3 werfen",
                   defaultBinding: (UInt32(kVK_ANSI_3), cO, "⌃⌥3"), run: { throwToDisplay(2) }),
            Action(key: "display4", name: "Auf Monitor 4 werfen",
                   defaultBinding: (UInt32(kVK_ANSI_4), cO, "⌃⌥4"), run: { throwToDisplay(3) }),
        ]
    }()

    // (Neu-)Registrierung aller belegten Bindings — auch nach Umbelegen in
    // den Einstellungen aufrufbar (settingsChanged in main.swift).
    static func register() {
        for (i, action) in actions.enumerated() {
            let id = UInt32(100 + i)
            HotKeyCenter.shared.unregister(id: id)
            guard let b = SettingsStore.shared.directBinding(for: action.key) ?? action.defaultBinding,
                  !SettingsStore.shared.directBindingCleared(action.key) else { continue }
            HotKeyCenter.shared.register(id: id, keyCode: b.keyCode, mods: b.mods) { action.run() }
        }
    }

    // MARK: Ziel-Fenster + Anwendung

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let w = axCopy(axApp, kAXFocusedWindowAttribute as String) { return (w as! AXUIElement) }
        return axWindows(of: app.processIdentifier).first
    }

    private static func displayOf(_ w: AXUIElement) -> Display? {
        guard let f = axFrame(w) else { return nil }
        let ds = currentDisplays()
        guard let id = displayID(containing: CGPoint(x: f.midX, y: f.midY), in: ds) else { return ds.first }
        return ds.first { $0.id == id }
    }

    private static func applyFrame(_ compute: (Display, CGRect) -> CGRect) {
        guard let w = focusedWindow(), let d = displayOf(w), let f = axFrame(w) else { return }
        recordHistory(w, frame: f)
        LinkedEdges.shared.suppress()
        axSetFrame(w, compute(d, f))
    }

    private static func undoFrame() {
        guard let w = focusedWindow(), let wid = windowID(of: w),
              let f = WindowHistory.shared.undoFrame(wid) else { return }
        LinkedEdges.shared.suppress()
        axSetFrame(w, f)
    }

    private static func throwToDisplay(_ index: Int) {
        let ds = currentDisplays().sorted { $0.full.minX < $1.full.minX }
        guard index < ds.count, let w = focusedWindow(), let d0 = displayOf(w), let f = axFrame(w) else { return }
        recordHistory(w, frame: f)
        LinkedEdges.shared.suppress()
        axSetFrame(w, LoopEngine.proportionalFrame(f, from: d0, to: ds[index]))
        axRaise(w)
    }

    private static func recordHistory(_ w: AXUIElement, frame: CGRect) {
        guard let wid = windowID(of: w) else { return }
        WindowHistory.shared.recordIfNeeded(wid, currentFrame: frame)
    }

    // CGWindowID des AX-Fensters über Bounds-Match (öffentliche API; die
    // Zuordnung ist dieselbe Heuristik wie in WindowManager.collectWindows).
    private static func windowID(of w: AXUIElement) -> CGWindowID? {
        guard let f = axFrame(w) else { return nil }
        let pid = axPid(w)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var best: (id: CGWindowID, dist: CGFloat)?
        for e in list where (e[kCGWindowOwnerPID as String] as? pid_t) == pid {
            guard let nd = e[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: nd),
                  let wid = e[kCGWindowNumber as String] as? CGWindowID else { continue }
            let dist = abs(r.minX - f.minX) + abs(r.minY - f.minY) + abs(r.width - f.width) + abs(r.height - f.height)
            if best == nil || dist < best!.dist { best = (wid, dist) }
        }
        guard let best, best.dist < Tuning.axMatchMaxDistance else { return nil }
        return best.id
    }
}
