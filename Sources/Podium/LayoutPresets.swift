import AppKit

// Gespeicherte Fenster-Layouts, eines pro Monitor-Konstellation (Fingerprint).
// Fenster werden über App-Identität gemerkt, nicht über Fenster-IDs — die
// überleben keinen App-Neustart. Beim Anwenden wird dreistufig gematcht:
// exakter Titel -> Titel-Präfix -> n-tes Fenster derselben App (Z-Order).
struct LayoutPreset: Codable {
    struct Entry: Codable {
        let bundleID: String
        let app: String
        let title: String
        let frame: CGRect
    }
    var name: String
    let fingerprint: String
    var entries: [Entry]
    var savedAt: Date
}

final class LayoutPresetStore {
    static let shared = LayoutPresetStore()
    static let changed = Notification.Name("PodiumLayoutsChanged")

    private(set) var presets: [LayoutPreset] = []

    private var path: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/podium/layouts.json")
    }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: path),
              let list = try? JSONDecoder().decode([LayoutPreset].self, from: data) else { return }
        presets = list
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(presets) else { return }
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: path)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    func preset(for fingerprint: String) -> LayoutPreset? {
        presets.first { $0.fingerprint == fingerprint }
    }

    // Aktuellen Ist-Zustand unter dem aktiven Fingerprint speichern —
    // ersetzt ein vorhandenes Preset desselben Setups.
    func saveCurrent(name: String? = nil) {
        let cfg = AppConfig.load()
        let wins = appWM.collectWindows(cfg: cfg)
        let fp = displaySetFingerprint()
        let entries = wins.compactMap { w -> LayoutPreset.Entry? in
            guard let bid = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier else { return nil }
            return LayoutPreset.Entry(bundleID: bid, app: w.app, title: w.title, frame: w.bounds)
        }
        let autoName = name ?? "\(NSScreen.screens.count) Monitor\(NSScreen.screens.count == 1 ? "" : "e")"
        let preset = LayoutPreset(name: autoName, fingerprint: fp, entries: entries, savedAt: Date())
        presets.removeAll { $0.fingerprint == fp }
        presets.append(preset)
        persist()
    }

    func delete(fingerprint: String) {
        presets.removeAll { $0.fingerprint == fingerprint }
        persist()
    }

    // Preset auf die echten Fenster anwenden. Nur bewegen, was sicher
    // gematcht wird — der Rest bleibt unangetastet. Liefert die Anzahl
    // platzierter Fenster.
    @discardableResult
    func apply(_ preset: LayoutPreset) -> Int {
        let cfg = AppConfig.load()
        var wins = appWM.collectWindows(cfg: cfg)
        let rank = appWM.zOrderRank()
        wins.sort { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }

        var placed = 0
        var used = Set<CGWindowID>()

        func take(_ w: WinInfo, frame: CGRect) {
            axSetFrame(w.ax, frame)
            used.insert(w.windowID)
            placed += 1
        }

        // Stufe 1+2: exakter Titel, dann Titel-Präfix (innerhalb der App).
        var remaining: [LayoutPreset.Entry] = []
        for e in preset.entries {
            let candidates = wins.filter { !used.contains($0.windowID) && bundleID(of: $0) == e.bundleID }
            if let exact = candidates.first(where: { $0.title == e.title }) {
                take(exact, frame: e.frame)
            } else if let prefix = candidates.first(where: {
                !e.title.isEmpty && ($0.title.hasPrefix(e.title) || e.title.hasPrefix($0.title))
            }) {
                take(prefix, frame: e.frame)
            } else {
                remaining.append(e)
            }
        }
        // Stufe 3: n-tes übriges Fenster derselben App nach Z-Order.
        for e in remaining {
            guard let w = wins.first(where: { !used.contains($0.windowID) && bundleID(of: $0) == e.bundleID })
            else { continue }
            take(w, frame: e.frame)
        }
        return placed
    }

    // Beim Setup-Wechsel (Opt-in) das passende Preset automatisch anwenden.
    // Debounce, weil macOS beim Umstecken mehrere Events feuert und die
    // Displays erst nacheinander registriert.
    private var autoTimer: Timer?
    func screenSetupChanged() {
        guard SettingsStore.shared.autoApplyLayouts else { return }
        autoTimer?.invalidate()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self, let p = self.preset(for: displaySetFingerprint()) else { return }
            self.apply(p)
        }
    }

    private func bundleID(of w: WinInfo) -> String {
        NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? ""
    }
}
