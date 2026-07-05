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
        Line(text: "↵  Bühne: fokussieren + schließen · Karte: nur schließen   ·   ⌘↵  immer fokussieren", isHeader: false),
        Line(text: "⌘⌫  Fenster schließen   ·   space  greifen/ablegen", isHeader: false),
        Line(text: "esc  Filter leeren / alles zurückrollen", isHeader: false),
        Line(text: "", isHeader: false),
        Line(text: "GREIFEN (space oder 1–4)", isHeader: true),
        Line(text: "← ↑ ↓ →  Slot tauschen, am Rand zum Nachbar-Monitor", isHeader: false),
        Line(text: "↵  nur ablegen, Overlay bleibt offen   ·   esc  ablegen", isHeader: false),
    ]

    // Globale Direkt-Hotkeys (ohne Overlay), siehe DirectActions.
    static let globalLines: [Line] = [
        Line(text: "GLOBAL (ohne Overlay)", isHeader: true),
        Line(text: "⌃⌥← ⌃⌥→  aktives Fenster: linke/rechte Hälfte", isHeader: false),
        Line(text: "⌃⌥↑  maximieren   ·   ⌃⌥↓  zentrieren", isHeader: false),
        Line(text: "⌃⌥1–4  aktives Fenster auf Monitor N werfen", isHeader: false),
    ]
}
