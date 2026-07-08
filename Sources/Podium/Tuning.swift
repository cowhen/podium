import CoreGraphics

// Alle Stellschrauben an einem Ort, statt als Magic Numbers verstreut.
enum Tuning {
    // Fenster gilt als "im Vordergrund", solange es sich mit keinem bereits
    // gewählten Fenster um mehr als diesen Anteil (der kleineren Fläche) überlappt.
    static let overlapThreshold: CGFloat = 0.2
    // Max. Bounds-Abweichung, bis zu der ein AX-Fenster einem CGWindowList-Eintrag
    // zugeordnet wird (Summe der |Δ| über x/y/w/h).
    static let axMatchMaxDistance: CGFloat = 60
    // Kleinere Fenster gelten als nicht verwaltbar (Paletten, Popovers, …)
    // bzw. werden beim Kacheln nie schmaler gequetscht als das.
    static let minWindowEdge: CGFloat = 120
    // Mindest-Langkante einer Monitor-Box in der Karte.
    static let minBoxLongEdge: CGFloat = 130
    // Die Bühne unter der Karte bricht spätestens bei dieser Breite um.
    static let stageMaxWidthFloor: CGFloat = 560
    // Max. Fenster in der Split-Anordnung einer Box.
    static let maxAssigned = 4
    // Bühnen-Kacheln (größer als früher die Zeilen-Kacheln — volle Breite verfügbar).
    static let stageTileSize = CGSize(width: 168, height: 112)
    // Hover-Zoom: Verzögerung bis zur großen Vorschau und deren Größe.
    static let hoverPreviewDelay: Double = 0.35
    static let previewSize = CGSize(width: 360, height: 280)
    // Loop-Modus: "fast maximieren" lässt diesen Anteil als Rand stehen.
    static let almostMaximizeRatio: CGFloat = 0.9
    // Loop-Modus: sichtbarer Streifen eines gestashten Fensters am Bildschirmrand.
    static let stashSliver: CGFloat = 6
}

// Überlappungsanteil relativ zur kleineren der beiden Flächen — so zählt ein
// kleines Fenster, das komplett unter einem großen liegt, auch dann als
// "stark überlappend", wenn sein Anteil an der großen Fläche winzig wäre.
func overlapFraction(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let inter = a.intersection(b)
    guard !inter.isNull else { return 0 }
    let interArea = inter.width * inter.height
    let minArea = min(a.width * a.height, b.width * b.height)
    guard minArea > 0 else { return 0 }
    return interArea / minArea
}

// Ordnet Fenster-Bounds den Raster-Slots von Layout.frames so zu, dass die
// Box-Vorschau der REALEN Bildschirmanordnung entspricht (Slot 0 = links bzw.
// oben, usw.) — sonst zeigt die Karte die Fenster seitenverkehrt. Quantisiert
// auf 50px-Bänder, damit fast gleiche Kanten nicht zufällig kippen.
func slotOrderIndices(_ bounds: [CGRect], vertical: Bool) -> [Int] {
    let q: CGFloat = 50
    let rowMajor = vertical || bounds.count == 4
    return bounds.indices.sorted { a, b in
        let ka = rowMajor ? ((bounds[a].minY / q).rounded(.down), bounds[a].minX)
                          : ((bounds[a].minX / q).rounded(.down), bounds[a].minY)
        let kb = rowMajor ? ((bounds[b].minY / q).rounded(.down), bounds[b].minX)
                          : ((bounds[b].minX / q).rounded(.down), bounds[b].minY)
        return ka < kb
    }
}

// Partitioniert (nach Z-Order sortierte) Fenster-Bounds in "Vordergrund"
// (kaum überlappend, max maxCount) und Rest. Pure Funktion → testbar.
func foregroundPartition(_ bounds: [CGRect],
                         maxCount: Int = Tuning.maxAssigned,
                         threshold: CGFloat = Tuning.overlapThreshold) -> (front: [Int], rest: [Int]) {
    var front: [Int] = []
    var rest: [Int] = []
    for (i, b) in bounds.enumerated() {
        let overlapsTooMuch = front.contains { overlapFraction(bounds[$0], b) > threshold }
        if front.count < maxCount && !overlapsTooMuch {
            front.append(i)
        } else {
            rest.append(i)
        }
    }
    return (front, rest)
}
