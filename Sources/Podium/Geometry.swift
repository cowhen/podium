import AppKit

// Ein Display in Quartz-Koordinaten (Ursprung oben-links, global) — passt zu AX.
struct Display {
    let id: CGDirectDisplayID
    let name: String      // z.B. "LG ULTRAGEAR" — für Monitor-Pinning in der Config
    let full: CGRect      // gesamte Fläche
    let visible: CGRect   // ohne Menüleiste/Dock
    var vertical: Bool { full.height > full.width }
}

func currentDisplays() -> [Display] {
    guard let primary = NSScreen.screens.first else { return [] }
    let primaryHeight = primary.frame.height
    return NSScreen.screens.compactMap { screen in
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let id = num.uint32Value
        let vf = screen.visibleFrame
        // AppKit (unten-links) → Quartz (oben-links)
        let visible = CGRect(x: vf.origin.x,
                             y: primaryHeight - vf.origin.y - vf.height,
                             width: vf.width, height: vf.height)
        return Display(id: id, name: screen.localizedName, full: CGDisplayBounds(id), visible: visible)
    }
}

// Akzentfarbe pro Monitor-Index (Karte, Badges, Bühnen-Punkte): Farbe erfasst
// man schneller als Ziffern — die Nummer bleibt als zweiter Kanal erhalten.
// Konfigurierbar über die Einstellungen (SettingsStore).
func monitorAccent(_ index: Int) -> NSColor {
    let palette = SettingsStore.shared.monitorColors
    return palette[index % palette.count]
}

// Kennung der aktuellen Monitor-Konstellation: Display-IDs sind über
// Reconnects nicht stabil, Namen+Auflösung schon. Basis für Wake-Restore
// und die gespeicherten Layouts.
func displaySetFingerprint() -> String {
    NSScreen.screens
        .map { "\($0.localizedName):\(Int($0.frame.width))x\(Int($0.frame.height))" }
        .sorted()
        .joined(separator: "|")
}

func displayID(containing point: CGPoint, in displays: [Display]) -> CGDirectDisplayID? {
    if let hit = displays.first(where: { $0.full.contains(point) }) { return hit.id }
    // Randfälle (Rundung an Monitor-Grenzen) -> nächstgelegenen Monitor statt
    // blind den ersten nehmen, sonst landen Fenster fälschlich auf Monitor 1.
    return displays.min(by: { distance($0.full, point) < distance($1.full, point) })?.id
}

private func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
    let dx = max(r.minX - p.x, 0, p.x - r.maxX)
    let dy = max(r.minY - p.y, 0, p.y - r.maxY)
    return hypot(dx, dy)
}
