import Foundation

// Zentrale Referenz der Overlay-Tastenbelegung — von Overlay.showCheatsheet()
// UND vom Einstellungsdialog genutzt, damit beide nie auseinanderlaufen.
enum KeyboardHelp {
    struct Line { let text: String; let isHeader: Bool }

    static let lines: [Line] = [
        Line(text: "BÜHNE", isHeader: true),
        Line(text: "tippen  Bühne filtern (Ring springt zum Treffer)", isHeader: false),
        Line(text: "← → ↑ ↓  durch alle Fenster wählen", isHeader: false),
        Line(text: "Maus über ein echtes Fenster (auf den Monitoren)  wählt es aus, Klick bestätigt wie ↵", isHeader: false),
        Line(text: "↵ oder Klick  positionieren (Loop-Modus)   ·   ⌘↵ oder Doppelklick  nur wechseln", isHeader: false),
        Line(text: "(per Einstellung invertierbar: ↵/Klick wechseln, ⌘↵ positionieren)", isHeader: false),
        Line(text: "Leertaste / Häkchen oben links  Fenster für Auto-Arrange ankreuzen", isHeader: false),
        Line(text: "↵ bei ≥2 Häkchen  Auto-Arrange: ausgewählte Fenster auf alle Monitore verteilen", isHeader: false),
        Line(text: "⌘M  minimieren   ·   ⌘H  App ausblenden   ·   ⌘⌫  Fenster schließen", isHeader: false),
        Line(text: "Rechtsklick auf Kachel  Aktionsmenü (fokussieren, minimieren, App beenden, …)", isHeader: false),
        Line(text: "esc  Filter leeren / alles zurückrollen", isHeader: false),
        Line(text: "⌃ beim Ziehen einer echten Fensterkante  verbundene Nachbarn resizen mit", isHeader: false),
        Line(text: "", isHeader: false),
        Line(text: "LOOP-MODUS", isHeader: true),
        Line(text: "← → ↑ ↓ (wiederholen cycled)  Rand: Hälfte → Drittel → zwei Drittel", isHeader: false),
        Line(text: "zwei Pfeiltasten gleichzeitig (z. B. ← + ↑)  direkt die passende Ecke", isHeader: false),
        Line(text: "U I J K (wiederholen cycled)  Ecken: ½ → ⅓ → ⅔", isHeader: false),
        Line(text: "E / ⇧E  weitere Positionen (Mitte-Hälfte/-Drittel, Viertel-Streifen)", isHeader: false),
        Line(text: "F / Rechtsklick  Restfläche füllen: solo → 3 größte Nachbarn → alle Nachbarn", isHeader: false),
        Line(text: "M A H W C  maximieren / fast maximieren / volle Höhe / volle Breite / zentrieren", isHeader: false),
        Line(text: "Z / ⇧Z  minimieren / andere minimieren   ·   X  ausblenden", isHeader: false),
        Line(text: "S / ⇧S  wegschieben / zurückholen   ·   ⌘Z  rückgängig", isHeader: false),
        Line(text: "1–9  auf Monitor werfen   ·   ⇥ / ⇧⇥  zum Nachbar-Monitor wechseln", isHeader: false),
        Line(text: "↵ oder Klick  anwenden   ·   esc  zurück zur Bühne (Fenster bleibt unverändert)", isHeader: false),
    ]

    // Globale Direkt-Hotkeys (ohne Overlay), siehe DirectActions — frei
    // belegbar unter Einstellungen → Hotkeys; hier die Werks-Defaults.
    static let globalLines: [Line] = [
        Line(text: "GLOBAL (ohne Overlay, frei belegbar unter Einstellungen → Hotkeys)", isHeader: true),
        Line(text: "⌃⌥← ⌃⌥→  aktives Fenster: linke/rechte Hälfte", isHeader: false),
        Line(text: "⌃⌥↑  maximieren   ·   ⌃⌥↓  zentrieren", isHeader: false),
        Line(text: "⌃⌥1–4  aktives Fenster auf Monitor N werfen (proportional)", isHeader: false),
        Line(text: "Drittel, Ecken, volle Höhe/Breite u. v. m. dort zusätzlich belegbar", isHeader: false),
    ]
}
