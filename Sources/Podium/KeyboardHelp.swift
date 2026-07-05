import Foundation

// Zentrale Referenz der Overlay-Tastenbelegung — von Overlay.showCheatsheet()
// UND vom Einstellungsdialog genutzt, damit beide nie auseinanderlaufen.
enum KeyboardHelp {
    struct Line { let text: String; let isHeader: Bool }

    static let lines: [Line] = [
        Line(text: "AUSWAHL", isHeader: true),
        Line(text: "tippen  Bühne filtern (Ring springt zum Treffer)", isHeader: false),
        Line(text: "← →  durch alle Fenster   ·   ↑ ↓  Karte ↔ Bühne", isHeader: false),
        Line(text: "⇧← ⇧→  Ratio Hauptachse   ·   ⇧↑ ⇧↓  Ratio Querachse   ·   =  zurücksetzen", isHeader: false),
        Line(text: "(Ratio wirkt schon bei bloßer Auswahl — kein Greifen nötig)", isHeader: false),
        Line(text: "1–4  auf Monitor werfen (greift automatisch)", isHeader: false),
        Line(text: "↵  Fenster fokussieren + Overlay schließen   ·   ⌘⌫  Fenster schließen", isHeader: false),
        Line(text: "space  greifen/ablegen   ·   esc  Filter leeren / alles zurückrollen", isHeader: false),
        Line(text: "", isHeader: false),
        Line(text: "GREIFEN (space oder 1–4)", isHeader: true),
        Line(text: "← ↑ ↓ →  Slot tauschen, am Rand zum Nachbar-Monitor", isHeader: false),
        Line(text: "↵  nur ablegen, Overlay bleibt offen   ·   esc  ablegen", isHeader: false),
    ]
}
