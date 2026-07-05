import AppKit
import CoreGraphics

// Live-Thumbnails brauchen Bildschirmaufnahme-Zugriff (zusätzlich zu
// Bedienungshilfen). Ohne Freigabe: Icon+Titel-Fallback, kein Blockieren.
@discardableResult
func ensureScreenRecordingAccess() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    CGRequestScreenCaptureAccess()
    return false
}

// CGWindowListCreateImage ist als deprecated markiert (Empfehlung: ScreenCaptureKit),
// bleibt aber für simple synchrone Einzelbild-Thumbnails die schlankere öffentliche API.
@available(macOS, deprecated: 14.0)
func windowThumbnail(_ windowID: CGWindowID, maxSize: CGSize) -> NSImage? {
    guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                                 [.boundsIgnoreFraming, .bestResolution]) else { return nil }
    let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    let scale = min(maxSize.width / img.size.width, maxSize.height / img.size.height, 1)
    let out = NSImage(size: NSSize(width: img.size.width * scale, height: img.size.height * scale))
    out.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: out.size))
    out.unlockFocus()
    return out
}

func appIcon(for pid: pid_t) -> NSImage? {
    NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
}

// Session-Cache für Thumbnails: die Kachel-Views werden bei jedem Umsortieren
// neu gebaut — ohne Cache würde jedes Rebuild alle Fenster neu abfotografieren
// (flackert und kostet). Wird bei jedem Overlay-Öffnen geleert.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [CGWindowID: NSImage] = [:]
    private let lock = NSLock()

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache = [:]
    }

    func image(for wid: CGWindowID) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[wid]
    }

    func store(_ img: NSImage, for wid: CGWindowID) {
        lock.lock(); defer { lock.unlock() }
        cache[wid] = img
    }

    // Einzelne Einträge verwerfen — nötig, wenn sich ein Fenster nach dem
    // Kacheln umgroßt hat und der alte Abzug nicht mehr stimmt.
    func remove(_ wid: CGWindowID) {
        lock.lock(); defer { lock.unlock() }
        cache[wid] = nil
    }
}
