import AppKit

// Gruppenkopf einer App auf der Bühne: Icon + Name + Anzahl.
final class GroupHeaderView: NSView {
    let app: String
    private let icon = NSImageView()

    init(app: String, pid: pid_t, count: Int) {
        self.app = app
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
    }

    required init?(coder: NSCoder) { fatalError() }
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

    // Gruppiert nach App (Reihenfolge des ersten Auftretens = Z-Order, per
    // Einstellung abschaltbar — dann eine flache, nur nach Z-Order sortierte
    // Gruppe ohne Kopfzeile), Flow-Layout mit Umbruch bei maxWidth. filter
    // matcht App-Name oder Titel. Kachelgröße kommt aus den Einstellungen —
    // größere Kacheln lassen weniger pro Zeile zu, die Bühne wächst dadurch
    // automatisch mehrzeilig (dasselbe Umbruch-Verhalten wie eh schon).
    func setWindows(_ wins: [WinInfo], filter: String, maxWidth: CGFloat,
                    dot: (WinInfo) -> NSColor?, floating: (WinInfo) -> Bool = { _ in false }) {
        tiles.forEach { $0.removeFromSuperview() }
        headers.forEach { $0.removeFromSuperview() }
        tiles = []; headers = []

        let filtered = filter.isEmpty ? wins : wins.filter {
            $0.app.localizedCaseInsensitiveContains(filter) || $0.title.localizedCaseInsensitiveContains(filter)
        }

        var groups: [(app: String?, wins: [WinInfo])] = []
        if SettingsStore.shared.stageGroupByApp {
            var order: [String] = []
            var byApp: [String: [WinInfo]] = [:]
            for w in filtered {
                if byApp[w.app] == nil { order.append(w.app) }
                byApp[w.app, default: []].append(w)
            }
            groups = order.map { (app: $0, wins: byApp[$0]!) }
        } else if !filtered.isEmpty {
            groups = [(app: nil, wins: filtered)]
        }

        // Auf die verfügbare Breite clampen — sonst ragt die erste Kachel
        // einer Zeile bei sehr großer eingestellter Kachelbreite übers Overlay hinaus.
        let tw = min(SettingsStore.shared.stageTileWidth, maxWidth)
        let th = tw * (Tuning.stageTileSize.height / Tuning.stageTileSize.width)
        let hgap: CGFloat = 8, vgap: CGFloat = 18, groupGap: CGFloat = 28, headerH: CGFloat = 28
        var x: CGFloat = 0, y: CGFloat = 0, lineMaxY: CGFloat = 0, usedWidth: CGFloat = 0

        for (appName, group) in groups {
            let gw = CGFloat(group.count) * tw + CGFloat(group.count - 1) * hgap
            if x > 0, x + min(gw, maxWidth) > maxWidth { x = 0; y = lineMaxY + vgap }

            var ty = y
            if let appName {
                let header = GroupHeaderView(app: appName, pid: group[0].pid, count: group.count)
                header.frame.origin = NSPoint(x: x, y: y)
                addSubview(header)
                headers.append(header)
                usedWidth = max(usedWidth, header.frame.maxX)
                ty = y + headerH
            }

            var tx = x
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

    // Verhindert, dass Klicks auf freie Fläche zum Hintergrund hochbubbeln.
    override func mouseDown(with event: NSEvent) {}
}
