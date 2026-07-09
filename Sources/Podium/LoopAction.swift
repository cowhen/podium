import CoreGraphics

// Reines Vokabular für den Loop-Modus: WAS mit einem einzelnen Fenster
// passieren soll, ohne jede Kenntnis von AX/AppKit. Nutzt BentoZone aus
// BentoLayout.swift für Rand/Ecke wieder, statt ein paralleles Enum zu bauen —
// die Zonen-Bedeutung (welche Seite/Ecke) ist identisch, nur die Anwendung
// (BentoLayout.plan rastert mit Nachbarn, LoopEngine positioniert solo) unterscheidet sich.
enum EdgeVariant: Int, CaseIterable {
    case half, third, twoThirds
}

enum HFourthSpan: Int, CaseIterable {
    case quarter = 1, half = 2, threeQuarters = 3
}

enum GeneralAction: CaseIterable {
    case maximize, almostMaximize, maximizeHeight, maximizeWidth, center
}

// Der "lange Schwanz" von Loop-Aktionen, die nicht auf einen der 8 Ring-Slots
// passen — erreichbar über eine eigene Zyklus-Taste statt eigener Shortcuts.
enum ExtraZone: Equatable, CaseIterable {
    case centerHalfHorizontal, centerHalfVertical
    case centerThirdHorizontal, centerThirdVertical
    case leftFourths(HFourthSpan), rightFourths(HFourthSpan)

    static var allCases: [ExtraZone] {
        [.centerHalfVertical, .centerHalfHorizontal,
         .centerThirdVertical, .centerThirdHorizontal,
         .leftFourths(.quarter), .leftFourths(.half), .leftFourths(.threeQuarters),
         .rightFourths(.quarter), .rightFourths(.half), .rightFourths(.threeQuarters)]
    }

    // Nur rand-verankerte Zonen lassen eine saubere rechteckige Restfläche
    // übrig, die sich mit anderen Fenstern füllen lässt (siehe
    // LoopEngine.remainder) — die zentrierten Varianten (centerHalf/
    // centerThird) haben links UND rechts (bzw. oben UND unten) einen Rand,
    // das ist kein einzelnes Rechteck mehr.
    var edgeAnchor: BentoZone? {
        switch self {
        case .leftFourths: return .left
        case .rightFourths: return .right
        case .centerHalfHorizontal, .centerHalfVertical, .centerThirdHorizontal, .centerThirdVertical: return nil
        }
    }
}

// Wie die Restfläche bei rand-verankerten Aktionen mit anderen Fenstern
// gefüllt wird — live per Taste (F) im Loop-Modus umschaltbar, siehe
// LoopMenuView. Startzustand ist immer .solo, siehe LoopMenuView.configure.
enum LoopFillMode: Int, CaseIterable {
    case solo, topThree, all

    var next: LoopFillMode { LoopFillMode(rawValue: (rawValue + 1) % Self.allCases.count)! }
}

enum LoopAction: Equatable {
    case edge(BentoZone, EdgeVariant)      // zone ∈ {.left,.right,.top,.bottom}
    case corner(BentoZone, EdgeVariant)    // zone ∈ {.topLeft,...}; Variante = Kantenlänge (½/⅓/⅔)
    case general(GeneralAction)
    case extra(ExtraZone)
    case hide, minimize, minimizeOthers, stash, unstash, undo
    // Monitor-Wechsel ist IMMER ein Throw auf ein explizites Ziel (0-basierter
    // Index in currentDisplays()) — auch ⇥ wird in LoopMenuView zu einem
    // throwToDisplay auf den geometrischen Nachbarn aufgelöst. Die Quelle wird
    // beim Anwenden frisch aus dem echten Fenster-Frame bestimmt, nie aus dem
    // (per jumpAnchor bereits verschobenen) Ring-Anker.
    case throwToDisplay(Int)

    // Ergonomischer Konstruktor für den Ring: routet zur passenden Case,
    // je nachdem ob die Zone ein Rand oder eine Ecke ist.
    static func zone(_ z: BentoZone, variant: EdgeVariant = .half) -> LoopAction {
        switch z {
        case .left, .right, .top, .bottom: return .edge(z, variant)
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .corner(z, variant)
        }
    }
}
