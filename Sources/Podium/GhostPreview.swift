import AppKit

// Isoliertes Ghost-Preview-Utility ausschließlich für Speed-Gated Linked
// Edges (siehe LinkedEdgeDrag.swift) — bewusst NICHT mit DragSnapManager.
// showPreview/hidePreview oder Overlay.swift/LoopMenu.swift's previewPanels
// geteilt (Projekt-Präzedenz: Isolation statt Kopplung zwischen einzelnen
// Drag-Features, siehe Kommentar bei LoopPreviewPanel in LoopMenu.swift).
// Fenster-Rezept ist bewusst dasselbe wie DragSnapManager.showPreview
// (borderless, .screenSaver, ignoresMouseEvents, kein Schatten am Fenster
// selbst — der Glow-Effekt des .border-Stils kommt vom CALayer, nicht vom
// NSWindow), nur eben ein zweites Mal für dieses Feature gebaut, plus
// weiches Ein-/Ausblenden statt hartem Schnitt (siehe Kernmechanik-Konzept:
// kontinuierliches statt binäres Feedback wirkt weniger disorientierend).

private func quartzToScreenRect(_ quartzRect: CGRect) -> NSRect {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: quartzRect.minX, y: primaryH - quartzRect.maxY,
                 width: quartzRect.width, height: quartzRect.height)
}

private func makeGhostWindow(view: NSView) -> NSWindow {
    let win = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.level = .screenSaver
    win.hasShadow = false
    win.ignoresMouseEvents = true
    win.isReleasedWhenClosed = false
    win.contentView = view
    win.alphaValue = 0   // Erstanzeige faded über show() ein, kein harter Pop-in
    return win
}

// Ein einzelnes Ghost-Panel — entweder gefüllt (.filled, Vorschau für einen
// Nachbarn) oder nur Rahmen+Glow (.border, Indikator ums gezogene Fenster
// selbst). Wiederverwendet zwischen Frames statt bei jedem Tick neu gebaut.
final class GhostPanel {
    enum Style { case filled, border }

    private var window: NSWindow?
    private let style: Style

    init(style: Style = .filled) { self.style = style }

    func show(quartzRect: CGRect, alpha: CGFloat = 1) {
        let rect = quartzToScreenRect(quartzRect)
        if window == nil {
            let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            switch style {
            case .filled:
                view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
                view.layer?.borderWidth = 2
                view.layer?.borderColor = NSColor.controlAccentColor.cgColor
            case .border:
                view.layer?.backgroundColor = NSColor.clear.cgColor
                view.layer?.borderWidth = 3
                view.layer?.borderColor = NSColor.controlAccentColor.cgColor
                view.layer?.shadowColor = NSColor.controlAccentColor.cgColor
                view.layer?.shadowOpacity = 0.6
                view.layer?.shadowRadius = 8
                view.layer?.shadowOffset = .zero
            }
            view.layer?.cornerRadius = 12
            view.layer?.cornerCurve = .continuous
            window = makeGhostWindow(view: view)
        }
        window?.setFrame(rect, display: true)
        window?.orderFrontRegardless()
        fade(to: alpha)
    }

    func hide() {
        fade(to: 0) { [weak self] in self?.window?.orderOut(nil) }
    }

    // Weiches Ein-/Ausblenden statt hartem Schnitt — auch für den
    // kontinuierlichen "Verbindung lockert sich"-Effekt innerhalb der
    // Hysterese-Bande genutzt (alpha kommt dann nicht nur 0/1, sondern
    // stufenlos aus der aktuellen Geschwindigkeit).
    private func fade(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        guard let window else { completion?(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Tuning.linkedEdgePreviewFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}

// Ein .filled-Panel pro betroffenem Nachbarn — wächst/schrumpft wie
// Overlay.swift's previewPanels/showPreviews(_:).
final class GhostPreviewSet {
    private var panels: [GhostPanel] = []

    func show(_ rects: [CGRect], alpha: CGFloat = 1) {
        while panels.count < rects.count { panels.append(GhostPanel(style: .filled)) }
        while panels.count > rects.count { panels.removeLast().hide() }
        for (panel, rect) in zip(panels, rects) { panel.show(quartzRect: rect, alpha: alpha) }
    }

    func hideAll() {
        panels.forEach { $0.hide() }
        panels = []
    }
}
