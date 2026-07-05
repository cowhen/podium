import ApplicationServices
import AppKit

// Dünne Hülle um die Accessibility-API. Nichts Privates, kein SIP.

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
    return err == .success ? value : nil
}

func axString(_ el: AXUIElement, _ attr: String) -> String? {
    axCopy(el, attr) as? String
}

func axBool(_ el: AXUIElement, _ attr: String) -> Bool {
    (axCopy(el, attr) as? NSNumber)?.boolValue ?? false
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let posV = axCopy(el, kAXPositionAttribute as String),
          let sizeV = axCopy(el, kAXSizeAttribute as String) else { return nil }
    var p = CGPoint.zero
    var s = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &p)
    AXValueGetValue(sizeV as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

func axSetFrame(_ el: AXUIElement, _ rect: CGRect) {
    var p = rect.origin
    var s = rect.size
    if let sv = AXValueCreate(.cgSize, &s) {
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv)
    }
    if let pv = AXValueCreate(.cgPoint, &p) {
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv)
    }
    // Größe erneut setzen: manche Apps clampen Position vor Resize.
    if let sv = AXValueCreate(.cgSize, &s) {
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv)
    }
}

func axSettablePosition(_ el: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(el, kAXPositionAttribute as CFString, &settable)
    return settable.boolValue
}

func axWindows(of pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    guard let arr = axCopy(app, kAXWindowsAttribute as String) as? [AXUIElement] else { return [] }
    return arr
}

func axPid(_ el: AXUIElement) -> pid_t {
    var pid: pid_t = 0
    AXUIElementGetPid(el, &pid)
    return pid
}

// Fenster schließen = dessen Schließen-Knopf drücken (wie ein echter Klick
// auf das rote Ampel-Licht; die App kann also z. B. noch "Sichern?" fragen).
func axClose(_ el: AXUIElement) {
    guard let btn = axCopy(el, kAXCloseButtonAttribute as String) else { return }
    AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
}

func axRaise(_ el: AXUIElement) {
    AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
}

func axFocus(_ el: AXUIElement) {
    NSRunningApplication(processIdentifier: axPid(el))?.activate()
    axRaise(el)
    AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
}

// Verwaltbar = normales, größenveränderbares, nicht-minimiertes Fenster.
func isManageable(_ el: AXUIElement) -> Bool {
    guard axString(el, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String) else { return false }
    if axBool(el, kAXMinimizedAttribute as String) { return false }
    guard axSettablePosition(el) else { return false }
    if let f = axFrame(el), f.width < Tuning.minWindowEdge || f.height < Tuning.minWindowEdge { return false }
    return true
}
