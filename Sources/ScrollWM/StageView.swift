import AppKit

// Ziehbarer Gruppenkopf einer App auf der Bühne: Icon + Name + Anzahl.
// Drag auf eine Monitor-Box legt die ersten zwei Fenster der App als Split.
final class GroupHeaderView: NSView {
    let app: String
    weak var controller: OverlayController?
    private var dragStart: NSPoint?
    private var ghost: NSImageView?
    private let icon = NSImageView()

    init(app: String, pid: pid_t, count: Int, controller: OverlayController) {
        self.app = app
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 22))

        icon.image = appIcon(for: pid)
        icon.frame = NSRect(x: 0, y: 2, width: 18, height: 18)
        addSubview(icon)

        let name = NSTextField(labelWithString: app)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = .secondaryLabelColor
        name.sizeToFit()
        name.frame.origin = NSPoint(x: 24, y: (22 - name.frame.height) / 2)
        addSubview(name)

        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.sizeToFit()
        countLabel.frame.origin = NSPoint(x: name.frame.maxX + 6, y: (22 - countLabel.frame.height) / 2)
        addSubview(countLabel)

        frame.size.width = countLabel.frame.maxX
        toolTip = "Ziehen legt die ersten zwei \(app)-Fenster als Split auf einen Monitor"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let root = window?.contentView else { return }
        let p = event.locationInWindow
        if ghost == nil, hypot(p.x - start.x, p.y - start.y) > 4 {
            controller?.dragBegan()
            let g = NSImageView(frame: NSRect(origin: .zero, size: NSSize(width: 40, height: 40)))
            g.image = icon.image
            g.alphaValue = 0.9
            root.addSubview(g)
            ghost = g
        }
        let local = root.convert(p, from: nil)
        ghost?.frame.origin = NSPoint(x: local.x - 20, y: local.y - 20)
        controller?.groupDragHover(at: p)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; ghost?.removeFromSuperview(); ghost = nil }
        guard ghost != nil else { return }
        controller?.groupDragEnded(app, at: event.locationInWindow)
    }
}

// Die Bühne: ALLE nicht zugeordneten Fenster in einer Fläche, gruppiert nach
// App (statt nach Monitor — die Position unsichtbarer Fenster ist fast
// wertlose Information und verdient nur einen Farbpunkt, keine eigene Zeile).
final class StageView: NSView {
    private(set) var tiles: [WindowTileView] = []
    private var headers: [GroupHeaderView] = []
    private let emptyLabel = NSTextField(labelWithString: "")
    weak var controller: OverlayController?

    override var isFlipped: Bool { true }

    init(controller: OverlayController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Gruppiert nach App (Reihenfolge des ersten Auftretens = Z-Order), Flow-
    // Layout mit Umbruch bei maxWidth. filter matcht App-Name oder Titel.
    func setWindows(_ wins: [WinInfo], filter: String, maxWidth: CGFloat,
                    dot: (WinInfo) -> NSColor?, floating: (WinInfo) -> Bool = { _ in false }) {
        tiles.forEach { $0.removeFromSuperview() }
        headers.forEach { $0.removeFromSuperview() }
        tiles = []; headers = []

        let filtered = filter.isEmpty ? wins : wins.filter {
            $0.app.localizedCaseInsensitiveContains(filter) || $0.title.localizedCaseInsensitiveContains(filter)
        }

        var order: [String] = []
        var byApp: [String: [WinInfo]] = [:]
        for w in filtered {
            if byApp[w.app] == nil { order.append(w.app) }
            byApp[w.app, default: []].append(w)
        }

        let tw = Tuning.stageTileSize.width, th = Tuning.stageTileSize.height
        let hgap: CGFloat = 8, vgap: CGFloat = 18, groupGap: CGFloat = 28, headerH: CGFloat = 28
        var x: CGFloat = 0, y: CGFloat = 0, lineMaxY: CGFloat = 0, usedWidth: CGFloat = 0

        for app in order {
            let group = byApp[app]!
            let gw = CGFloat(group.count) * tw + CGFloat(group.count - 1) * hgap
            if x > 0, x + min(gw, maxWidth) > maxWidth { x = 0; y = lineMaxY + vgap }

            let header = GroupHeaderView(app: app, pid: group[0].pid, count: group.count, controller: controller!)
            header.frame.origin = NSPoint(x: x, y: y)
            addSubview(header)
            headers.append(header)
            usedWidth = max(usedWidth, header.frame.maxX)

            var tx = x, ty = y + headerH
            for w in group {
                if tx > x, tx + tw > maxWidth { tx = x; ty += th + hgap }   // Umbruch innerhalb großer Gruppen
                let t = WindowTileView(info: w, isVisible: false, controller: controller!,
                                       frame: NSRect(x: tx, y: ty, width: tw, height: th),
                                       dot: dot(w), floating: floating(w))
                addSubview(t)
                tiles.append(t)
                tx += tw + hgap
                lineMaxY = max(lineMaxY, ty + th)
                usedWidth = max(usedWidth, tx - hgap)
            }
            x += min(gw, maxWidth) + groupGap
        }

        if filtered.isEmpty {
            emptyLabel.stringValue = wins.isEmpty ? "Alle Fenster sind zugeordnet"
                                                  : "Keine Treffer für „\(filter)“"
            emptyLabel.sizeToFit()
            emptyLabel.frame.origin = NSPoint(x: 0, y: 8)
            emptyLabel.isHidden = false
            lineMaxY = 30
            usedWidth = max(usedWidth, emptyLabel.frame.maxX)
        } else {
            emptyLabel.isHidden = true
        }
        // Frame auf die real genutzte Breite trimmen — der Aufrufer nutzt das,
        // um das Overlay nur so breit zu machen wie nötig.
        frame.size = NSSize(width: min(usedWidth, maxWidth), height: lineMaxY)
    }

    var hitAreaInWindow: NSRect { convert(bounds.insetBy(dx: -10, dy: -14), to: nil) }

    // Hebt die Bühne während eines Drags als Drop-Ziel ("unzuordnen") hervor.
    func setDropTarget(_ on: Bool) {
        layer?.backgroundColor = (on ? NSColor.controlAccentColor.withAlphaComponent(0.08) : nil)?.cgColor
    }

    // Verhindert, dass Klicks auf freie Fläche zum Hintergrund hochbubbeln.
    override func mouseDown(with event: NSEvent) {}
}
