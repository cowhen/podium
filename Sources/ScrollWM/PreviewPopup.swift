import AppKit

// Große Hover-Vorschau einer Fenster-Kachel: löst das "Content erkennen"-
// Problem der kleinen Thumbnails. Fängt keine Maus-Events (hitTest nil),
// damit sie den Drag/Hover darunter nicht stört.
final class PreviewPopup: FlippedView {
    init(info: WinInfo, image: NSImage?) {
        super.init(frame: NSRect(origin: .zero, size: Tuning.previewSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        layer?.masksToBounds = true

        let labelH: CGFloat = 30
        let iv = NSImageView(frame: NSRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.height - labelH - 12))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.image = image ?? appIcon(for: info.pid)
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 8
        iv.layer?.cornerCurve = .continuous
        iv.layer?.masksToBounds = true
        addSubview(iv)

        let label = NSTextField(labelWithString: info.title.isEmpty ? info.app : "\(info.app) — \(info.title)")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.frame = NSRect(x: 12, y: bounds.height - labelH + 5, width: bounds.width - 24, height: 17)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
