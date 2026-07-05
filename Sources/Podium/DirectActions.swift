import AppKit
import Carbon.HIToolbox

// Direkt-Hotkeys ohne Overlay (der Rectangle-Kern): wirken sofort auf das
// fokussierte Fenster der vordersten App. ⌃⌥← / ⌃⌥→ = linke/rechte Hälfte
// (bzw. obere/untere auf Hochkant-Monitoren), ⌃⌥↑ = maximieren,
// ⌃⌥↓ = zentrieren, ⌃⌥1–4 = auf Monitor N werfen (Größe bleibt, geklemmt).
enum DirectActions {
    static func register() {
        let mods = UInt32(controlKey | optionKey)
        HotKeyCenter.shared.register(id: 10, keyCode: UInt32(kVK_LeftArrow), mods: mods) { halve(first: true) }
        HotKeyCenter.shared.register(id: 11, keyCode: UInt32(kVK_RightArrow), mods: mods) { halve(first: false) }
        HotKeyCenter.shared.register(id: 12, keyCode: UInt32(kVK_UpArrow), mods: mods) { maximize() }
        HotKeyCenter.shared.register(id: 13, keyCode: UInt32(kVK_DownArrow), mods: mods) { center() }
        let digits: [UInt32] = [UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4)]
        for (i, code) in digits.enumerated() {
            HotKeyCenter.shared.register(id: UInt32(20 + i), keyCode: code, mods: mods) { throwToDisplay(i) }
        }
    }

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

    private static func halve(first: Bool) {
        guard let w = focusedWindow(), let d = displayOf(w) else { return }
        let frames = Layout.frames(visible: d.visible, vertical: d.vertical, count: 2, split: 0)
        axSetFrame(w, first ? frames[0] : frames[1])
    }

    private static func maximize() {
        guard let w = focusedWindow(), let d = displayOf(w) else { return }
        axSetFrame(w, d.visible.insetBy(dx: Layout.gap, dy: Layout.gap))
    }

    private static func center() {
        guard let w = focusedWindow(), let d = displayOf(w), let f = axFrame(w) else { return }
        axSetFrame(w, CGRect(x: d.visible.midX - f.width / 2, y: d.visible.midY - f.height / 2,
                             width: f.width, height: f.height))
    }

    private static func throwToDisplay(_ index: Int) {
        let ds = currentDisplays().sorted { $0.full.minX < $1.full.minX }
        guard index < ds.count, let w = focusedWindow(), let f = axFrame(w) else { return }
        let d = ds[index]
        let width = min(f.width, d.visible.width - 2 * Layout.gap)
        let height = min(f.height, d.visible.height - 2 * Layout.gap)
        axSetFrame(w, CGRect(x: d.visible.midX - width / 2, y: d.visible.midY - height / 2,
                             width: width, height: height))
        axRaise(w)
    }
}
