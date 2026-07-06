import AppKit
import ApplicationServices

// Ein verwaltbares Fenster mit allem, was Overlay + Tiling brauchen.
struct WinInfo {
    let ax: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID
    let app: String
    let title: String
    let bounds: CGRect
    var minimized: Bool = false

    func with(bounds: CGRect) -> WinInfo {
        WinInfo(ax: ax, pid: pid, windowID: windowID, app: app, title: title,
                bounds: bounds, minimized: minimized)
    }
}

// Liest den echten Live-Zustand (AX + CGWindowList), wendet Anordnungen an.
// Kein interner Cache zwischen Overlay-Sitzungen — die echten Fensterpositionen
// SIND der Zustand.
final class WindowManager {

    // MARK: Live-Zustand einlesen

    // Bewusste Grenze: .optionOnScreenOnly sieht nur den aktiven Space —
    // Fenster auf anderen Spaces existieren für das Tool nicht.
    func collectWindows(cfg: AppConfig) -> [WinInfo] {
        let cgList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        // Vollständige Liste (inkl. Offscreen) für MINIMIERTE Fenster — die
        // fehlen in der OnScreen-Liste, sollen aber auf der Bühne erscheinen,
        // sonst verliert man sie nach dem Auto-Minimieren komplett.
        let cgAll = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var out: [WinInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            let name = app.localizedName ?? ""
            if cfg.ignoreNames.contains(name) || cfg.ignoreBundleIds.contains(app.bundleIdentifier ?? "") { continue }
            let pid = app.processIdentifier
            var candidates = cgList.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }

            var axWins: [(AXUIElement, String, CGRect)] = []
            for w in axWindows(of: pid) where isManageable(w) {
                let title = axString(w, kAXTitleAttribute as String) ?? ""
                if cfg.ignoreTitlePatterns.contains(where: { title.localizedCaseInsensitiveContains($0) }) { continue }
                guard let f = axFrame(w) else { continue }
                axWins.append((w, title, f))
            }

            // Echte 1:1-Zuordnung statt jedes AX-Fenster unabhängig matchen zu
            // lassen — sonst können zwei ähnlich positionierte Fenster derselben
            // App denselben CGWindowID (und damit dasselbe Thumbnail) bekommen.
            while !axWins.isEmpty && !candidates.isEmpty {
                var bestAX = 0, bestCand = 0, bestDist = CGFloat.greatestFiniteMagnitude
                for i in axWins.indices {
                    for j in candidates.indices {
                        guard let d = boundsDistance(candidates[j][kCGWindowBounds as String], axWins[i].2) else { continue }
                        if d < bestDist { bestDist = d; bestAX = i; bestCand = j }
                    }
                }
                guard bestDist < Tuning.axMatchMaxDistance,
                      let wid = candidates[bestCand][kCGWindowNumber as String] as? CGWindowID else { break }
                let (w, title, f) = axWins[bestAX]
                out.append(WinInfo(ax: w, pid: pid, windowID: wid, app: name, title: title, bounds: f))
                axWins.remove(at: bestAX)
                candidates.remove(at: bestCand)
            }

            // Zweiter Durchgang: minimierte Fenster (AX kennt sie weiter und
            // liefert den letzten Frame; Match gegen die Offscreen-Liste).
            let usedIDs = Set(out.filter { $0.pid == pid }.map { $0.windowID })
            var candidatesAll = cgAll.filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                    && !usedIDs.contains(($0[kCGWindowNumber as String] as? CGWindowID) ?? 0)
            }
            for w in axWindows(of: pid) where axBool(w, kAXMinimizedAttribute as String) {
                guard axString(w, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String) else { continue }
                let title = axString(w, kAXTitleAttribute as String) ?? ""
                if cfg.ignoreTitlePatterns.contains(where: { title.localizedCaseInsensitiveContains($0) }) { continue }
                guard let f = axFrame(w) else { continue }
                var bestCand = -1
                var bestDist = CGFloat.greatestFiniteMagnitude
                for j in candidatesAll.indices {
                    guard let dd = boundsDistance(candidatesAll[j][kCGWindowBounds as String], f) else { continue }
                    if dd < bestDist { bestDist = dd; bestCand = j }
                }
                guard bestCand >= 0, bestDist < Tuning.axMatchMaxDistance,
                      let wid = candidatesAll[bestCand][kCGWindowNumber as String] as? CGWindowID else { continue }
                out.append(WinInfo(ax: w, pid: pid, windowID: wid, app: name, title: title,
                                   bounds: f, minimized: true))
                candidatesAll.remove(at: bestCand)
            }
        }
        return out
    }

    // Front-to-back-Reihenfolge aus CGWindowList (topmost zuerst).
    func zOrderRank() -> [CGWindowID: Int] {
        let cgList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var rank: [CGWindowID: Int] = [:]
        for (i, e) in cgList.enumerated() {
            if let wid = e[kCGWindowNumber as String] as? CGWindowID { rank[wid] = i }
        }
        return rank
    }

    // Andere echte Fenster auf einem Monitor, Front-zuerst, ohne floatende
    // Apps (die nie ins erzwungene Bento-Raster sollen) und ohne das
    // ausgeschlossene (gezogene) Fenster selbst. EINE Quelle für "wer spielt
    // beim Bento-Layout mit" — von Drag-to-Edge und Radial-Menü genutzt,
    // damit beide für dieselbe Geste dieselben Mitspieler wählen.
    func otherWindows(on d: Display, excludingAX ax: AXUIElement, pid: pid_t, cfg: AppConfig) -> [WinInfo] {
        let rank = zOrderRank()
        let ds = currentDisplays()
        return collectWindows(cfg: cfg)
            .filter { !($0.pid == pid && CFEqual($0.ax, ax)) }
            .filter { !cfg.isFloating(pid: $0.pid, name: $0.app) }
            .filter { displayID(containing: CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), in: ds) == d.id }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
    }

    // Pro Monitor nach echter Z-Order sortiert (vorderstes zuerst) — Startzustand
    // für die Zeilen im Overlay, bevor der Nutzer Fenster in die Karte zieht.
    func perMonitorOrder(displays: [Display], wins: [WinInfo], rank: [CGWindowID: Int]) -> [CGDirectDisplayID: [WinInfo]] {
        var byDisplay: [CGDirectDisplayID: [WinInfo]] = [:]
        for w in wins {
            guard let id = displayID(containing: CGPoint(x: w.bounds.midX, y: w.bounds.midY), in: displays) else { continue }
            byDisplay[id, default: []].append(w)
        }
        for id in byDisplay.keys {
            byDisplay[id]!.sort { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
        }
        return byDisplay
    }

    // Aus den (nach Z-Order sortierten) Fenstern eines Monitors die "im
    // Vordergrund, kaum überlappenden" wählen (max 4) — Startzustand der
    // Karten-Box beim Öffnen. Fenster, die sich stark mit einer bereits
    // gewählten Kachel überlappen (z. B. dahinter geparkt/gestapelt), bleiben
    // für die Zeile übrig.
    func selectForeground(_ sorted: [WinInfo]) -> (front: [WinInfo], rest: [WinInfo]) {
        let (front, rest) = foregroundPartition(sorted.map { $0.bounds })
        return (front.map { sorted[$0] }, rest.map { sorted[$0] })
    }

    // MARK: Anwenden

    // Sofort-Kacheln von bis zu 4 Fenstern eines einzelnen Monitors — für
    // Klick/Drag auf eine Monitor-Box im Overlay.
    func tileGroup(_ wins: [AXUIElement], on display: Display, split: Int, cross: Int = 0,
                   mainR: CGFloat? = nil, crossR: CGFloat? = nil, verticalOverride: Bool? = nil) {
        guard !wins.isEmpty else { return }
        let vertical = verticalOverride ?? display.vertical
        let shown = Array(wins.prefix(Tuning.maxAssigned))
        let frames = Layout.frames(visible: display.visible, vertical: vertical,
                                   count: shown.count, split: split, cross: cross,
                                   mainR: mainR, crossR: crossR)
        tileShown(shown, frames: frames, vertical: vertical)
    }

    // Für "floatende" Apps (siehe AppConfig.isFloating): Größe unangetastet,
    // nur auf dem Monitor zentriert und nach vorn geholt.
    func floatWindow(_ ax: AXUIElement, on display: Display) {
        guard let f = axFrame(ax) else { axRaise(ax); return }
        let area = display.visible
        axSetFrame(ax, CGRect(x: area.midX - f.width / 2, y: area.midY - f.height / 2, width: f.width, height: f.height))
        axRaise(ax)
    }

    // Setzt die Frames der Fenster. Jedes Fenster wird an der TATSÄCHLICH
    // gesetzten Kante seines linken/oberen Raster-Nachbarn verankert (statt an
    // der berechneten), da manche Apps eine Mindestgröße erzwingen — sonst
    // überlappen die Nachbarn (gilt für 2er-Splits wie fürs 2x2-Raster).
    private func tileShown(_ shown: [AXUIElement], frames: [CGRect], vertical: Bool) {
        let (leftOf, topOf) = Layout.gridNeighbors(count: shown.count, vertical: vertical)
        var actual: [CGRect] = []
        for (i, w) in shown.enumerated() {
            var f = frames[i]
            if let l = leftOf[i] {
                let nx = actual[l].maxX + Layout.gap
                f = CGRect(x: nx, y: f.minY, width: max(Tuning.minWindowEdge, f.maxX - nx), height: f.height)
            }
            if let t = topOf[i] {
                let ny = actual[t].maxY + Layout.gap
                f = CGRect(x: f.minX, y: ny, width: f.width, height: max(Tuning.minWindowEdge, f.maxY - ny))
            }
            axSetFrame(w, f)
            actual.append(axFrame(w) ?? f)
        }
        for w in shown { axRaise(w) }
    }
}

private func boundsDistance(_ dict: Any?, _ f: CGRect) -> CGFloat? {
    guard let nd = dict as? NSDictionary, let r = CGRect(dictionaryRepresentation: nd) else { return nil }
    return abs(r.minX - f.minX) + abs(r.minY - f.minY) + abs(r.width - f.width) + abs(r.height - f.height)
}
