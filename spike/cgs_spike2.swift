import Foundation
import CoreGraphics
import AppKit

// Spike v2: Wirkt das Verschieben eines Fensters in einen ECHTEN (display-
// gebundenen) Space? Das war in v1 nicht getestet (dort nur Orphan-Space).

setbuf(stdout, nil)
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
func sym<T>(_ n: String, as t: T.Type) -> T { unsafeBitCast(dlsym(sky, n)!, to: T.self) }

typealias FnMainConn = @convention(c) () -> Int32
typealias FnCopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
typealias FnAddWindows = @convention(c) (Int32, CFArray, CFArray) -> Void
typealias FnCopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
typealias FnSetCurrent = @convention(c) (Int32, CFString, UInt64) -> Void

let cid = sym("CGSMainConnectionID", as: FnMainConn.self)()
let copyDisplaySpaces = sym("CGSCopyManagedDisplaySpaces", as: FnCopyDisplaySpaces.self)
let addWindows = sym("CGSAddWindowsToSpaces", as: FnAddWindows.self)
let copySpacesForWindows = sym("CGSCopySpacesForWindows", as: FnCopySpacesForWindows.self)

func spacesOf(_ wid: UInt32) -> [UInt64] {
    let a = copySpacesForWindows(cid, 0x7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue()
    return (a as? [NSNumber])?.map { $0.uint64Value } ?? []
}
func allAttachedSpaces() -> [UInt64] {
    guard let arr = copyDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
    return arr.flatMap { ($0["Spaces"] as? [[String: Any]])?.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value } ?? [] }
}

let attached = allAttachedSpaces()
print("Echte (display-gebundene) Spaces: \(attached)")

let wins = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
guard let cand = wins.first(where: {
    ($0[kCGWindowLayer as String] as? Int) == 0 &&
    (($0[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0) > 400 &&
    ($0[kCGWindowOwnerName as String] as? String) != "cgs_spike2"
}), let wid = cand[kCGWindowNumber as String] as? UInt32 else { print("kein Fenster"); exit(0) }

let owner = (cand[kCGWindowOwnerName as String] as? String) ?? "?"
let orig = spacesOf(wid)
print("Testfenster '\(owner)' wid=\(wid), aktuell spaces=\(orig)")

// Zielspace: ein echter Space, auf dem das Fenster NICHT ist.
guard let target = attached.first(where: { !orig.contains($0) }) else {
    print("kein anderer echter Space verfügbar — bitte vorher 2. Space anlegen"); exit(0)
}
print("\nschiebe wid=\(wid) -> ECHTER space \(target) ...")
addWindows(cid, [NSNumber(value: wid)] as CFArray, [NSNumber(value: target)] as CFArray)
let now = spacesOf(wid)
print("Fenster jetzt spaces=\(now)  -> Move-in-echten-Space wirkte: \(now.contains(target))")

// zurück
if let back = orig.first {
    addWindows(cid, [NSNumber(value: wid)] as CFArray, [NSNumber(value: back)] as CFArray)
    print("zurück auf \(back), jetzt spaces=\(spacesOf(wid))")
}
print("\nFERTIG.")
