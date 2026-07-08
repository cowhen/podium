import CoreGraphics

// Reine Frame-Mathematik für den Loop-Modus: aus einer LoopAction + verfügbarer
// Fläche den Ziel-Frame für GENAU EIN Fenster berechnen — anders als
// BentoLayout/Layout, die immer für eine Gruppe von Fenstern rastern. Keine
// AX/AppKit-Abhängigkeit, komplett testbar.
enum LoopEngine {
    // Rand: an dieser Seite verankert, Breite/Höhe = area * Anteil (50/33/67%).
    // Ecke: in der Ecke verankert, BEIDE Kanten = area * Anteil (Default ½,
    // per Cycling auch ⅓/⅔) — unabhängig von "anderen" Fenstern (keine
    // Rastergröße wie bei BentoLayout.plan, der Loop-Modus bewegt solo).
    static func frame(zone: BentoZone, variant: EdgeVariant, in area: CGRect) -> CGRect {
        let inner = area.insetBy(dx: Layout.gap, dy: Layout.gap)
        switch zone {
        case .left, .right:
            let w = (inner.width * fraction(variant)).rounded()
            let x = zone == .left ? inner.minX : inner.maxX - w
            return CGRect(x: x, y: inner.minY, width: w, height: inner.height)
        case .top, .bottom:
            let h = (inner.height * fraction(variant)).rounded()
            let y = zone == .top ? inner.minY : inner.maxY - h
            return CGRect(x: inner.minX, y: y, width: inner.width, height: h)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let w = (inner.width * fraction(variant)).rounded()
            let h = (inner.height * fraction(variant)).rounded()
            let x = (zone == .topLeft || zone == .bottomLeft) ? inner.minX : inner.maxX - w
            let y = (zone == .topLeft || zone == .topRight) ? inner.minY : inner.maxY - h
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    private static func fraction(_ v: EdgeVariant) -> CGFloat {
        switch v {
        case .half: return 0.5
        case .third: return 1.0 / 3.0
        case .twoThirds: return 2.0 / 3.0
        }
    }

    // Restfläche für rand-verankerte Aktionen: `area` (unverändert, NICHT
    // gap-inset) minus das gezogene Fenster. `frame` muss an GENAU der
    // angegebenen Seite von `area` verankert sein (wie frame(zone:variant:in:)
    // es liefert) — sonst ist der Rest kein einzelnes Rechteck mehr (siehe
    // ExtraZone.edgeAnchor, das zentrierte Zonen deshalb ausschließt).
    // Bewusst OHNE eigenen Gap-Abzug: Layout.frames() insetted die
    // zurückgegebene Fläche beim Aufteilen unter den anderen Fenstern schon
    // selbst um Layout.gap — ein zusätzlicher Abzug hier würde den Abstand
    // zum gezogenen Fenster auf das Doppelte verdoppeln.
    static func remainder(of frame: CGRect, in area: CGRect, edge: BentoZone) -> CGRect {
        switch edge {
        case .left: return CGRect(x: frame.maxX, y: area.minY, width: area.maxX - frame.maxX, height: area.height)
        case .right: return CGRect(x: area.minX, y: area.minY, width: frame.minX - area.minX, height: area.height)
        case .top: return CGRect(x: area.minX, y: frame.maxY, width: area.width, height: area.maxY - frame.maxY)
        case .bottom: return CGRect(x: area.minX, y: area.minY, width: area.width, height: frame.minY - area.minY)
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return area
        }
    }

    // Wiederholtes Drücken derselben Randrichtung cycled durch die Varianten.
    static func nextVariant(_ v: EdgeVariant) -> EdgeVariant {
        let all = EdgeVariant.allCases
        let idx = all.firstIndex(of: v) ?? 0
        return all[(idx + 1) % all.count]
    }

    static func generalFrame(_ action: GeneralAction, in area: CGRect, current: CGRect) -> CGRect {
        let inner = area.insetBy(dx: Layout.gap, dy: Layout.gap)
        switch action {
        case .maximize:
            return inner
        case .almostMaximize:
            let w = (inner.width * Tuning.almostMaximizeRatio).rounded()
            let h = (inner.height * Tuning.almostMaximizeRatio).rounded()
            return CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h)
        case .maximizeHeight:
            let w = min(current.width, inner.width)
            let x = clamp(current.minX, lo: inner.minX, hi: inner.maxX - w)
            return CGRect(x: x, y: inner.minY, width: w, height: inner.height)
        case .maximizeWidth:
            let h = min(current.height, inner.height)
            let y = clamp(current.minY, lo: inner.minY, hi: inner.maxY - h)
            return CGRect(x: inner.minX, y: y, width: inner.width, height: h)
        case .center:
            let w = min(current.width, inner.width), h = min(current.height, inner.height)
            return CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h)
        }
    }

    static func extraFrame(_ zone: ExtraZone, in area: CGRect) -> CGRect {
        let inner = area.insetBy(dx: Layout.gap, dy: Layout.gap)
        switch zone {
        case .centerHalfHorizontal:
            let w = (inner.width * 0.5).rounded()
            return CGRect(x: inner.midX - w / 2, y: inner.minY, width: w, height: inner.height)
        case .centerHalfVertical:
            let h = (inner.height * 0.5).rounded()
            return CGRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h)
        case .centerThirdHorizontal:
            let w = (inner.width / 3).rounded()
            return CGRect(x: inner.midX - w / 2, y: inner.minY, width: w, height: inner.height)
        case .centerThirdVertical:
            let h = (inner.height / 3).rounded()
            return CGRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h)
        case .leftFourths(let span):
            let w = (inner.width * CGFloat(span.rawValue) / 4).rounded()
            return CGRect(x: inner.minX, y: inner.minY, width: w, height: inner.height)
        case .rightFourths(let span):
            let w = (inner.width * CGFloat(span.rawValue) / 4).rounded()
            return CGRect(x: inner.maxX - w, y: inner.minY, width: w, height: inner.height)
        }
    }

    // Display-Wechsel: Größe/Position PROPORTIONAL zum Quell-Monitor erhalten,
    // auf den Ziel-Monitor übertragen und dort vollständig hineingeklemmt —
    // kein Zentrieren/Zurücksetzen wie bei DirectActions.throwToDisplay.
    static func proportionalFrame(_ frame: CGRect, from source: Display, to destination: Display) -> CGRect {
        let sv = source.visible, dv = destination.visible
        guard sv.width > 0, sv.height > 0 else { return frame }
        let relX = (frame.minX - sv.minX) / sv.width
        let relY = (frame.minY - sv.minY) / sv.height
        let relW = frame.width / sv.width
        let relH = frame.height / sv.height
        let w = min(relW * dv.width, dv.width)
        let h = min(relH * dv.height, dv.height)
        let x = clamp(dv.minX + relX * dv.width, lo: dv.minX, hi: dv.maxX - w)
        let y = clamp(dv.minY + relY * dv.height, lo: dv.minY, hi: dv.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    enum ScreenDirection { case left, right, up, down }

    // Räumlicher Nachbar in Pfeilrichtung, nach echter Monitor-Anordnung —
    // eigenständige Kopie der Idee aus dem (entfernten) Overlay.neighborDisplay,
    // absichtlich nicht in Geometry.swift, das unverändert bleiben soll.
    static func neighborDisplay(of current: Display, direction: ScreenDirection, among displays: [Display]) -> Display? {
        let c = CGPoint(x: current.full.midX, y: current.full.midY)
        return displays
            .filter { d in
                guard d.id != current.id else { return false }
                let dx = d.full.midX - c.x, dy = d.full.midY - c.y
                switch direction {
                case .left: return dx < -10
                case .right: return dx > 10
                case .up: return dy < -10       // Quartz: +y = runter
                case .down: return dy > 10
                }
            }
            .min { hypot($0.full.midX - c.x, $0.full.midY - c.y) < hypot($1.full.midX - c.x, $1.full.midY - c.y) }
    }

    // Nächstgelegener Rand eines Frames innerhalb einer Fläche — für Stash.
    static func nearestEdge(of frame: CGRect, in area: CGRect) -> BentoZone {
        let distances: [(BentoZone, CGFloat)] = [
            (.left, frame.minX - area.minX),
            (.right, area.maxX - frame.maxX),
            (.top, frame.minY - area.minY),
            (.bottom, area.maxY - frame.maxY),
        ]
        return distances.min { $0.1 < $1.1 }!.0
    }

    // Schiebt den Frame fast vollständig über den angegebenen Rand hinaus,
    // sodass nur noch `sliver` Pixel sichtbar bleiben (Griff zum Zurückholen).
    static func stashFrame(_ frame: CGRect, edge: BentoZone, in area: CGRect, sliver: CGFloat = Tuning.stashSliver) -> CGRect {
        var f = frame
        switch edge {
        case .left: f.origin.x = area.minX - f.width + sliver
        case .right: f.origin.x = area.maxX - sliver
        case .top: f.origin.y = area.minY - f.height + sliver
        case .bottom: f.origin.y = area.maxY - sliver
        case .topLeft, .topRight, .bottomLeft, .bottomRight: break   // Stash kennt nur Ränder
        }
        return f
    }

    private static func clamp(_ v: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        guard lo <= hi else { return lo }
        return min(max(v, lo), hi)
    }
}
