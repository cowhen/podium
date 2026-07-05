import Foundation

// Handgepflegte Config unter ~/.config/scrollwm/config.json
struct AppConfig {
    var ignoreNames: [String] = []
    var ignoreBundleIds: [String] = []
    var ignoreTitlePatterns: [String] = []

    static var path: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/scrollwm/config.json")
    }

    static func load() -> AppConfig {
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
        return cfg
    }

    // Beim ersten Start eine leere Config + Beispiel anlegen.
    private static func ensureTemplate() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: path.path) else { return }
        try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let empty = """
        {
          "ignore": { "appNames": [], "bundleIds": [], "titlePatterns": [] }
        }
        """
        try? empty.write(to: path, atomically: true, encoding: .utf8)
        let example = """
        {
          "ignore": {
            "appNames": ["Maccy", "Amphetamine"],
            "bundleIds": ["com.apple.systempreferences"],
            "titlePatterns": ["Picture in Picture"]
          }
        }
        """
        try? example.write(to: path.deletingLastPathComponent().appendingPathComponent("config.example.json"),
                           atomically: true, encoding: .utf8)
    }
}
