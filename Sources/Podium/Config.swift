import AppKit

// Handgepflegte Config unter ~/.config/scrollwm/config.json
struct AppConfig {
    var ignoreNames: [String] = []
    var ignoreBundleIds: [String] = []
    var ignoreTitlePatterns: [String] = []
    // "Floatend": nicht ignoriert (bleiben sichtbar, landen auf der Bühne),
    // aber vom Kacheln ausgenommen — Drop auf eine Monitor-Box verschiebt sie
    // nur (zentriert, unverändert groß) und holt sie nach vorn, statt sie in
    // ein Split-Raster zu zwängen. Sinnvoll für Finder/Systemeinstellungen,
    // deren Größe man nicht von der App-Auswahl bestimmen lassen will.
    var floatingNames: [String] = []
    var floatingBundleIds: [String] = ["com.apple.finder", "com.apple.systempreferences"]

    func isFloating(pid: pid_t, name: String) -> Bool {
        if floatingNames.contains(name) { return true }
        guard let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return floatingBundleIds.contains(bid)
    }

    static var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/podium/config.json")
    }

    // Einmalige Migration vom alten Projektnamen (scrollwm -> podium): die
    // bestehende Config wird kopiert, das alte Verzeichnis bleibt unangetastet.
    private static func migrateLegacyConfig() {
        let fm = FileManager.default
        let old = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/scrollwm/config.json")
        guard !fm.fileExists(atPath: path.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: old, to: path)
    }

    static func load() -> AppConfig {
        migrateLegacyConfig()
        ensureTemplate()
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AppConfig()
        }
        var cfg = AppConfig()
        if let ig = json["ignore"] as? [String: Any] {
            cfg.ignoreNames = (ig["appNames"] as? [String]) ?? []
            cfg.ignoreBundleIds = (ig["bundleIds"] as? [String]) ?? []
            cfg.ignoreTitlePatterns = (ig["titlePatterns"] as? [String]) ?? []
        }
        // Fehlt der Abschnitt komplett, gelten die eingebauten Standards
        // (Finder, Systemeinstellungen) — ist er da, gilt exakt das Konfigurierte.
        if let fl = json["floating"] as? [String: Any] {
            cfg.floatingNames = (fl["appNames"] as? [String]) ?? []
            cfg.floatingBundleIds = (fl["bundleIds"] as? [String]) ?? []
        }
        return cfg
    }

    // Schreibt die komplette Config zurück (für den Einstellungsdialog) —
    // überschreibt bewusst die ganze Datei, "ignore"/"floating" sind die
    // einzigen bekannten Schlüssel.
    func save() {
        let json: [String: Any] = [
            "ignore": ["appNames": ignoreNames, "bundleIds": ignoreBundleIds, "titlePatterns": ignoreTitlePatterns],
            "floating": ["appNames": floatingNames, "bundleIds": floatingBundleIds],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: Self.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.path)
    }

    // Beim ersten Start eine leere Config + Beispiel anlegen.
    private static func ensureTemplate() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: path.path) else { return }
        try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let empty = """
        {
          "ignore": { "appNames": [], "bundleIds": [], "titlePatterns": [] },
          "floating": { "appNames": [], "bundleIds": ["com.apple.finder", "com.apple.systempreferences"] }
        }
        """
        try? empty.write(to: path, atomically: true, encoding: .utf8)
        let example = """
        {
          "ignore": {
            "appNames": ["Maccy", "Amphetamine"],
            "bundleIds": [],
            "titlePatterns": ["Picture in Picture"]
          },
          "floating": {
            "appNames": [],
            "bundleIds": ["com.apple.finder", "com.apple.systempreferences"]
          }
        }
        """
        try? example.write(to: path.deletingLastPathComponent().appendingPathComponent("config.example.json"),
                           atomically: true, encoding: .utf8)
    }
}
