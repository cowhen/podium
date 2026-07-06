import AppKit
import ApplicationServices

// Drag-to-Edge-Snap fürs echte Ziehen auf dem Desktop (wie Windows Aero Snap /
// Rectangle): zieht man ein Fenster an den Rand, zeigt eine Vorschau die
// Zielhälfte, in eine Ecke zeigt sie ein wachsendes Bento-Raster (bis zu 4
// Fenster). Beim Loslassen wird die Anordnung übernommen — inklusive der
// "anderen" beteiligten Fenster, die für ein sauberes Layout mit umgesetzt
// werden. Nutzt BentoLayout — dasselbe Vokabular wie Radial-Menü und die
// Box-Vorschau im Overlay, damit sich die Geste überall gleich verhält.
//
// Rein per NSEvent-Globalmonitor (öffentliche API, nur Lesezugriff, kann
// anders als ein CGEventTap keine Events blockieren/verändern) — kein Hack,
// kein Watchdog nötig, da Monitore vom System nicht zwangsdeaktiviert werden.
// "Wird gezogen" wird rein aus der Positionsänderung des fokussierten
// Fensters abgeleitet, ohne Titelleisten-Hit-Testing.
final class DragSnapManager {
    static let shared = DragSnapManager()

    private static let margin: CGFloat = 24
    private static let cornerSize: CGFloat = 90

    private var downMonitor: Any?
    private var draggedMonitor: Any?
    private var upMonitor: Any?

    private var candidate: AXUIElement?
    private var candidatePid: pid_t = 0
    private var originalFrame: CGRect?
    private var isDragging = false
    private var activeZone: BentoZone?
    private var previewWindows: [NSWindow] = []

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
        candidatePid = app.processIdentifier
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
        guard isDragging, let c = candidate, let zone = activeZone, let d = displayUnderMouse() else { return }
        let others = appWM.otherWindows(on: d, excludingAX: c, pid: candidatePid, cfg: AppConfig.load())
        BentoApply.apply(zone: zone, dragged: c, others: others.map { $0.ax }, display: d)
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

    private func updatePreview() {
        guard let d = displayUnderMouse() else { activeZone = nil; hidePreview(); return }
        let mouse = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let q = CGPoint(x: mouse.x, y: primaryH - mouse.y)
        guard let z = BentoLayout.zone(in: d.full, point: q, margin: Self.margin, cornerSize: Self.cornerSize) else {
            activeZone = nil
            hidePreview()
            return
        }
        guard z != activeZone else { return }
        activeZone = z
        let others = appWM.otherWindows(on: d, excludingAX: candidate!, pid: candidatePid, cfg: AppConfig.load())
        let plan = BentoLayout.plan(zone: z, othersAvailable: others.count)
        guard let draggedIdx = plan.tokens.firstIndex(of: .dragged) else { hidePreview(); return }
        let frames = Layout.frames(visible: d.visible, vertical: plan.vertical ?? d.vertical, count: plan.tokens.count, split: 0)
        showPreview(quartzRect: frames[draggedIdx])
    }

    private func showPreview(quartzRect: CGRect) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: quartzRect.minX, y: primaryH - quartzRect.maxY,
                          width: quartzRect.width, height: quartzRect.height)
        if previewWindows.isEmpty {
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
            previewWindows = [win]
        }
        previewWindows[0].setFrame(rect, display: true)
        previewWindows[0].orderFrontRegardless()
    }

    private func hidePreview() {
        activeZone = nil
        previewWindows.forEach { $0.orderOut(nil) }
    }
}
