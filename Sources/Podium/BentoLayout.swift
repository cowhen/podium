import CoreGraphics

// Gemeinsames Vokabular für "an den Rand/in die Ecke snappen" — genutzt von
// Drag-to-Edge (echter Desktop), Radial-Menü und Box-Drop im Overlay, damit
// sich die Geste überall exakt gleich anfühlt und dieselbe Bento-Anordnung
// entsteht. Rand = sauberer 2er-Split, Ecke = Bento-Raster (bis zu 4 Fenster).
enum BentoZone: CaseIterable, Equatable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

// Ein Slot-Plan: welches Fenster (gezogenes oder "das n-te andere") landet in
// welchem Layout.frames-Index. Rein positionell — der Aufrufer füllt Token in
// echte Fenster um (AXUIElement auf dem Desktop, WinInfo in der Box).
enum BentoToken: Equatable { case dragged; case other(Int) }

enum BentoLayout {
    // Randzonen mit Toleranz `margin`, Eckzonen mit quadratischer Toleranz
    // `cornerSize` (hat Vorrang, wenn beide zutreffen). bounds/point müssen
    // dieselbe Konvention nutzen (oben-links, wie überall im Projekt — passt
    // sowohl für Quartz-Bildschirmkoordinaten als auch Box-lokale Koordinaten).
    static func zone(in bounds: CGRect, point p: CGPoint, margin: CGFloat, cornerSize: CGFloat) -> BentoZone? {
        let nearLeft = p.x - bounds.minX < cornerSize
        let nearRight = bounds.maxX - p.x < cornerSize
        let nearTop = p.y - bounds.minY < cornerSize
        let nearBottom = bounds.maxY - p.y < cornerSize
        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if p.x - bounds.minX < margin { return .left }
        if bounds.maxX - p.x < margin { return .right }
        if p.y - bounds.minY < margin { return .top }
        if bounds.maxY - p.y < margin { return .bottom }
        return nil
    }

    // Kernstück: aus einer Zone und der Anzahl verfügbarer "anderer" Fenster
    // (Front-zuerst) einen Slot-Plan bauen. Rand = fixer 2er-Split (genau 1
    // anderes Fenster, Rest bleibt unangetastet). Ecke = das Bento-Raster
    // wächst auf bis zu 4 Fenster; reichen die vorhandenen Fenster nicht für
    // eine echte Quadranten-Aufteilung (nur 0-1 andere), fällt die Ecke auf
    // die naheliegende Randbewegung zurück (links/rechts je nach Ecken-Seite).
    // vertical: true/false erzwingt die Stapelrichtung (Randzonen — "oben"
    // bleibt oben, egal wie der Monitor steht); nil = natürliche
    // Monitor-Ausrichtung gilt (Eckzonen — ein 3er/2x2-Raster soll auf einem
    // Hochkant-Monitor weiterhin wie gewohnt rotieren).
    static func plan(zone: BentoZone, othersAvailable: Int) -> (tokens: [BentoToken], vertical: Bool?) {
        switch zone {
        case .left: return ([.dragged, .other(0)], false)
        case .right: return ([.other(0), .dragged], false)
        case .top: return ([.dragged, .other(0)], true)
        case .bottom: return ([.other(0), .dragged], true)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let count = min(othersAvailable + 1, 4)
            let leftSide = zone == .topLeft || zone == .bottomLeft
            switch count {
            case 1:
                return ([.dragged], nil)
            case 2:
                // Zu wenig Fenster für echte Quadranten: wie der nähere Rand,
                // aber ohne die Ausrichtung zu erzwingen (Ecke != Rand-Absicht).
                return leftSide ? ([.dragged, .other(0)], nil) : ([.other(0), .dragged], nil)
            case 3:
                // Layout count=3: Slot 0 = große linke Spalte, 1/2 = rechts
                // gestapelt (oben/unten). Linke Ecken -> große Spalte,
                // rechte Ecken -> passender gestapelter Slot.
                if leftSide { return ([.dragged, .other(0), .other(1)], nil) }
                let top = zone == .topRight
                return top ? ([.other(0), .dragged, .other(1)], nil) : ([.other(0), .other(1), .dragged], nil)
            default:
                // 2x2, zeilen-major: 0=TL 1=TR 2=BL 3=BR. Gezogenes Fenster an
                // den Eck-Index, die restlichen 3 Slots in Front-Reihenfolge auffüllen.
                let idx: Int
                switch zone {
                case .topLeft: idx = 0
                case .topRight: idx = 1
                case .bottomLeft: idx = 2
                default: idx = 3
                }
                var slots = [BentoToken](repeating: .dragged, count: 4)
                var otherIdx = 0
                for i in 0..<4 where i != idx {
                    slots[i] = .other(otherIdx)
                    otherIdx += 1
                }
                return (slots, nil)
            }
        }
    }
}
