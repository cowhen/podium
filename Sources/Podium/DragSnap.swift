import AppKit
import ApplicationServices

// Drag-to-Edge-Snap fürs echte Ziehen auf dem Desktop (wie Windows Aero Snap /
// Rectangle): zieht man ein Fenster an den Rand, zeigt eine Vorschau die
// Zielhälfte, beim Loslassen wird sie übernommen. Zwei so gezogene Fenster
// (eins nach links, eins nach rechts) ergeben automatisch einen echten 50/50-
// Split, weil beide dieselben Layout.frames-Hälften treffen.
//
// Rein per NSEvent-Globalmonitor (öffentliche API, nur Lesezugriff, kann
// anders als ein CGEventTap keine Events blockieren/verändern) — kein Hack,
// kein Watchdog nötig, da Monitore vom System nicht zwangsdeaktiviert werden.
// "Wird gezogen" wird rein aus der Positionsänderung des fokussierten
// Fensters abgeleitet, ohne Titelleisten-Hit-Testing.
final class DragSnapManager {
    static let shared = DragSnapManager()

    private enum Zone { case left, right, top, bottom }

    private var downMonitor: Any?
    private var draggedMonitor: Any?
    private var upMonitor: Any?

    private var candidate: AXUIElement?
    private var originalFrame: CGRect?
    private var isDragging = false
    private var activeZone: Zone?
    private var previewWindow: NSWindow?

    func start() {
        guard downMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleDown()
        }
        draggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleDragged()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleUp()
        }
    }

    private func handleDown() {
        candidate = nil
        originalFrame = nil
        isDragging = false
        guard SettingsStore.shared.dragSnap,
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let w = axCopy(axApp, kAXFocusedWindowAttribute as String) else { return }
        let win = (w as! AXUIElement)
        guard isManageable(win) else { return }
        candidate = win
        originalFrame = axFrame(win)
    }

    private func handleDragged() {
        guard SettingsStore.shared.dragSnap, let c = candidate, let orig = originalFrame,
              let cur = axFrame(c) else { return }
        if !isDragging {
            // Erst als Verschieben werten, wenn sich die Position spürbar
            // geändert hat, die Größe aber gleich blieb (kein Resize-Drag).
            guard cur.size == orig.size, hypot(cur.minX - orig.minX, cur.minY - orig.minY) > 6 else { return }
            isDragging = true
        }
        updatePreview()
    }

    private func handleUp() {
        defer { candidate = nil; originalFrame = nil; isDragging = false; hidePreview() }
        guard isDragging, let c = candidate, let zone = activeZone,
              let d = displayUnderMouse() else { return }
        let frames = Layout.frames(visible: d.visible, vertical: false, count: 2, split: 0)
        switch zone {
        case .left: axSetFrame(c, frames[0])
        case .right: axSetFrame(c, frames[1])
        case .top: axSetFrame(c, Layout.frames(visible: d.visible, vertical: true, count: 2, split: 0)[0])
        case .bottom: axSetFrame(c, Layout.frames(visible: d.visible, vertical: true, count: 2, split: 0)[1])
        }
        axRaise(c)
    }

    // MARK: Zonen & Vorschau

    private func displayUnderMouse() -> Display? {
        let mouse = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: mouse.x, y: primaryH - mouse.y)   // AppKit unten-links -> Quartz oben-links
        let ds = currentDisplays()
        guard let id = displayID(containing: q, in: ds) else { return ds.first }
        return ds.first { $0.id == id }
    }

    private static let margin: CGFloat = 24

    private func zone(in d: Display, quartzPoint q: CGPoint) -> Zone? {
        let f = d.full
        if q.x - f.minX < Self.margin { return .left }
        if f.maxX - q.x < Self.margin { return .right }
        if q.y - f.minY < Self.margin { return .top }       // Quartz: kleines y = oben
        if f.maxY - q.y < Self.margin { return .bottom }
        return nil
    }

    private func updatePreview() {
        guard let d = displayUnderMouse() else { hidePreview(); return }
        let mouse = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: mouse.x, y: primaryH - mouse.y)
        guard let z = zone(in: d, quartzPoint: q) else {
            activeZone = nil
            hidePreview()
            return
        }
        guard z != activeZone else { return }
        activeZone = z
        let frames2H = Layout.frames(visible: d.visible, vertical: false, count: 2, split: 0)
        let frames2V = Layout.frames(visible: d.visible, vertical: true, count: 2, split: 0)
        let quartzRect: CGRect
        switch z {
        case .left: quartzRect = frames2H[0]
        case .right: quartzRect = frames2H[1]
        case .top: quartzRect = frames2V[0]
        case .bottom: quartzRect = frames2V[1]
        }
        showPreview(quartzRect: quartzRect)
    }

    private func showPreview(quartzRect: CGRect) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: quartzRect.minX, y: primaryH - quartzRect.maxY,
                          width: quartzRect.width, height: quartzRect.height)
        if previewWindow == nil {
            let win = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .screenSaver
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
            view.autoresizingMask = [.width, .height]   // folgt setFrame() bei Zonenwechsel
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            view.layer?.borderWidth = 2
            view.layer?.borderColor = NSColor.controlAccentColor.cgColor
            view.layer?.cornerRadius = 12
            view.layer?.cornerCurve = .continuous
            win.contentView = view
            previewWindow = win
        }
        previewWindow?.setFrame(rect, display: true)
        previewWindow?.orderFrontRegardless()
    }

    private func hidePreview() {
        activeZone = nil
        previewWindow?.orderOut(nil)
    }
}
