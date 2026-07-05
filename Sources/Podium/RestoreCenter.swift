import AppKit

// Merkt sich die zuletzt "gesegnete" Fensteranordnung (beim Schließen des
// Overlays) und stellt sie nach Sleep/Wake oder Dock-Reconnect automatisch
// wieder her — die ursprüngliche Motivation des ganzen Tools: Fenster, die
// macOS nach dem Aufwachen in Ecken verschoben hat, kommen zurück an ihren
// Platz. In-Memory (AXUIElement-Referenzen), gilt also für die Laufzeit der
// App; nach einem App-Neustart erst wieder ab dem ersten Overlay-Schließen.
final class RestoreCenter {
    static let shared = RestoreCenter()

    private var blessed: [(ax: AXUIElement, frame: CGRect)] = []
    private var fingerprint = ""
    private var timer: Timer?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(scheduleRestore),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleRestore),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // Aktuellen Ist-Zustand als Soll-Anordnung übernehmen.
    func bless(_ wins: [WinInfo]) {
        blessed = wins.compactMap { w in axFrame(w.ax).map { (w.ax, $0) } }
        fingerprint = displaySetFingerprint()
    }

    func restoreNow() {
        guard !blessed.isEmpty, displaySetFingerprint() == fingerprint else { return }
        for (ax, frame) in blessed { axSetFrame(ax, frame) }
    }

    // Debounce: beim Aufwachen/Umstecken feuern mehrere Events, und macOS
    // sortiert die Displays selbst noch einige Sekunden lang um — erst danach
    // wiederherstellen, sonst kämpfen wir gegen das System an.
    @objc private func scheduleRestore() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.restoreNow()
        }
    }

}
