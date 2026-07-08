import CoreGraphics

// App-Lebenszeit-Gedächtnis für "Undo/Ursprungsgröße" im Loop-Modus — merkt
// sich pro Fenster den allerersten Frame, den Podium in dieser Sitzung
// angetroffen hat, unabhängig davon, ob die Bühne zwischenzeitlich
// geschlossen/neu geöffnet wurde (wie Loop's WindowRecords).
final class WindowHistory {
    static let shared = WindowHistory()
    private var initial: [CGWindowID: CGRect] = [:]

    func recordIfNeeded(_ id: CGWindowID, currentFrame: CGRect) {
        if initial[id] == nil { initial[id] = currentFrame }
    }

    func undoFrame(_ id: CGWindowID) -> CGRect? { initial[id] }

    // Bei echtem Fenster-Schließen vergessen, sonst wächst der Speicher unbegrenzt.
    func forget(_ id: CGWindowID) { initial[id] = nil }
}
