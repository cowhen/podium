import AppKit

// Oben-links-Koordinaten (wie überall sonst im Projekt), statt AppKits
// Standard unten-links.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

class FlippedVisualEffectView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}
