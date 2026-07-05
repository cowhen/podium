import CoreGraphics

// Berechnet die Frames der sichtbaren Fenster (max 4) in einem Monitor-Viewport.
enum Layout {
    static let gap: CGFloat = 8

    // splitMode: 0 = 50/50, 1 = 67/33 (erste Gruppe groß), 2 = 33/67 (klein).
    // Wirkt auf die Hauptachse jedes Layouts: beim 2er-Split direkt, beim
    // 3er auf die große Spalte/Reihe, beim 2x2 auf die linke Spalte.
    static func ratio(_ splitMode: Int) -> CGFloat {
        switch splitMode {
        case 1: return 0.67
        case 2: return 0.33
        default: return 0.5
        }
    }

    // Raster-Nachbarn passend zu frames(): welcher Index liegt links bzw.
    // über Index i. Grundlage für das Verankern an der tatsächlich gesetzten
    // Nachbar-Kante (Apps mit Mindestgröße) in WindowManager.tileShown.
    static func gridNeighbors(count: Int, vertical: Bool) -> (leftOf: [Int: Int], topOf: [Int: Int]) {
        switch count {
        case ..<2: return ([:], [:])
        case 2: return vertical ? ([:], [1: 0]) : ([1: 0], [:])
        case 3: return vertical ? ([2: 1], [1: 0, 2: 0]) : ([1: 0, 2: 0], [2: 1])
        default: return ([1: 0, 3: 2], [2: 0, 3: 1])
        }
    }

    // split = Hauptachse (Spalte/Reihe von Slot 0 bzw. linke Spalte im 2x2),
    // cross = Querachse innerhalb der kleinen Gruppe (Stapel im 3er, Reihen im 2x2).
    static func frames(visible area: CGRect, vertical: Bool, count: Int, split: Int, cross: Int = 0) -> [CGRect] {
        let inner = area.insetBy(dx: gap, dy: gap)
        switch count {
        case ..<2:
            return [inner]
        case 2:
            let r = ratio(split)
            if vertical {
                let total = inner.height - gap
                let h0 = (total * r).rounded()
                let h1 = total - h0
                let top = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: h0)
                let bottom = CGRect(x: inner.minX, y: inner.minY + h0 + gap, width: inner.width, height: h1)
                return [top, bottom]
            } else {
                let total = inner.width - gap
                let w0 = (total * r).rounded()
                let w1 = total - w0
                let left = CGRect(x: inner.minX, y: inner.minY, width: w0, height: inner.height)
                let right = CGRect(x: inner.minX + w0 + gap, y: inner.minY, width: w1, height: inner.height)
                return [left, right]
            }
        case 3:
            // Quer: 1 spannt die ganze linke Spalte (Breite = ratio), 2/3
            // rechts gestapelt. Hochkant (vertical): gedreht — 1 spannt die
            // ganze obere Reihe (Höhe = ratio), 2/3 darunter nebeneinander.
            let r = ratio(split)
            if vertical {
                let rowH = ((inner.height - gap) * r).rounded(), rowH2 = inner.height - gap - rowH
                let colW = ((inner.width - gap) * ratio(cross)).rounded(), colW2 = inner.width - gap - colW
                let rightX = inner.minX + colW + gap
                let bottomY = inner.minY + rowH + gap
                return [
                    CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: rowH),
                    CGRect(x: inner.minX, y: bottomY, width: colW, height: rowH2),
                    CGRect(x: rightX, y: bottomY, width: colW2, height: rowH2),
                ]
            } else {
                let colW = ((inner.width - gap) * r).rounded(), colW2 = inner.width - gap - colW
                let rowH = ((inner.height - gap) * ratio(cross)).rounded(), rowH2 = inner.height - gap - rowH
                let rightX = inner.minX + colW + gap
                let bottomY = inner.minY + rowH + gap
                return [
                    CGRect(x: inner.minX, y: inner.minY, width: colW, height: inner.height),
                    CGRect(x: rightX, y: inner.minY, width: colW2, height: rowH),
                    CGRect(x: rightX, y: bottomY, width: colW2, height: rowH2),
                ]
            }
        default:
            // 2x2-Raster: 1 oben links, 2 oben rechts, 3 unten links, 4 unten
            // rechts. split steuert die Spaltenbreite, cross die Reihenhöhe.
            let colW = ((inner.width - gap) * ratio(split)).rounded(), colW2 = inner.width - gap - colW
            let rowH = ((inner.height - gap) * ratio(cross)).rounded(), rowH2 = inner.height - gap - rowH
            let rightX = inner.minX + colW + gap
            let bottomY = inner.minY + rowH + gap
            return [
                CGRect(x: inner.minX, y: inner.minY, width: colW, height: rowH),
                CGRect(x: rightX, y: inner.minY, width: colW2, height: rowH),
                CGRect(x: inner.minX, y: bottomY, width: colW, height: rowH2),
                CGRect(x: rightX, y: bottomY, width: colW2, height: rowH2),
            ]
        }
    }
}
