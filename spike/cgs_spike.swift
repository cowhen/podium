import Foundation
import CoreGraphics
import AppKit

// Spike: Welche privaten CGS/SkyLight-Space-Operationen wirken aus einem
// normalen Prozess (kein SIP, keine Dock-Injection) auf diesem macOS?
// Jeder Schreibvorgang wird durch Zurücklesen verifiziert. Alles wird restauriert.

setbuf(stdout, nil)

func line(_ s: String = "") { print(s) }
func step(_ s: String) { print("\n=== \(s) ===") }

guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
    line("FEHLER: SkyLight nicht ladbar"); exit(1)
}
func sym<T>(_ name: String, as t: T.Type) -> T? {
    guard let p = dlsym(sky, name) else { line("  ⚠ Symbol fehlt: \(name)"); return nil }
    return unsafeBitCast(p, to: T.self)
}

typealias FnMainConn            = @convention(c) () -> Int32
typealias FnCopyDisplaySpaces   = @convention(c) (Int32) -> Unmanaged<CFArray>?
typealias FnGetCurrentSpace     = @convention(c) (Int32, CFString) -> UInt64
typealias FnSetCurrentSpace     = @convention(c) (Int32, CFString, UInt64) -> Void
typealias FnSpaceCreate         = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
typealias FnSpaceDestroy        = @convention(c) (Int32, UInt64) -> Void
typealias FnAddWindows          = @convention(c) (Int32, CFArray, CFArray) -> Void
typealias FnCopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

let mainConn            = sym("CGSMainConnectionID", as: FnMainConn.self)
let copyDisplaySpaces   = sym("CGSCopyManagedDisplaySpaces", as: FnCopyDisplaySpaces.self)
let getCurrent          = sym("CGSManagedDisplayGetCurrentSpace", as: FnGetCurrentSpace.self)
let setCurrent          = sym("CGSManagedDisplaySetCurrentSpace", as: FnSetCurrentSpace.self)
let spaceCreate         = sym("CGSSpaceCreate", as: FnSpaceCreate.self)
let spaceDestroy        = sym("CGSSpaceDestroy", as: FnSpaceDestroy.self)
let addWindows          = sym("CGSAddWindowsToSpaces", as: FnAddWindows.self)
let copySpacesForWindows = sym("CGSCopySpacesForWindows", as: FnCopySpacesForWindows.self)

guard let mainConn else { line("kein CGSMainConnectionID"); exit(1) }
let cid = mainConn()
line("CGSMainConnectionID = \(cid)")

// ---- Helfer: Display/Space-Struktur lesen ----
struct DisplayInfo { let id: String; let current: UInt64; let spaces: [UInt64] }
func readDisplays() -> [DisplayInfo] {
    guard let copyDisplaySpaces,
          let arr = copyDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
    return arr.map { d in
        let disp = (d["Display Identifier"] as? String) ?? "?"
        let cur = ((d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0
        let spaces = (d["Spaces"] as? [[String: Any]])?
            .compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value } ?? []
        return DisplayInfo(id: disp, current: cur, spaces: spaces)
    }
}

func spacesOf(window wid: UInt32) -> [UInt64] {
    guard let copySpacesForWindows else { return [] }
    let arr = copySpacesForWindows(cid, 0x7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue()
    return (arr as? [NSNumber])?.map { $0.uint64Value } ?? []
}

// ============================================================
step("1) LESEN: CGSCopyManagedDisplaySpaces")
let before = readDisplays()
if before.isEmpty { line("  ⚠ nichts gelesen — Read funktioniert NICHT") }
for d in before { line("  Display \(d.id): current=\(d.current), spaces=\(d.spaces)") }

step("2) LESEN: CGSManagedDisplayGetCurrentSpace pro Display")
if let getCurrent {
    for d in before {
        let c = getCurrent(cid, d.id as CFString)
        line("  \(d.id): \(c)  (matcht struktur: \(c == d.current))")
    }
} else { line("  Symbol fehlt") }

step("3) LESEN: Fenster + sein Space (CGSCopySpacesForWindows)")
let wins = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
let candidate = wins.first { w in
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 99
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    let b = w[kCGWindowBounds as String] as? [String: CGFloat]
    let area = (b?["Width"] ?? 0) * (b?["Height"] ?? 0)
    return layer == 0 && area > 200_000 && owner != "ScrollWM" && owner != "cgs_spike"
}
guard let candidate, let testWID = candidate[kCGWindowNumber as String] as? UInt32 else {
    line("  ⚠ kein Testfenster gefunden — Schreibtests übersprungen"); exit(0)
}
let testOwner = (candidate[kCGWindowOwnerName as String] as? String) ?? "?"
line("  Testfenster: '\(testOwner)' wid=\(testWID), aktuell auf spaces=\(spacesOf(window: testWID))")

// ============================================================
step("4) SCHREIBEN: CGSSpaceCreate (neuen Space anlegen)")
var createdSpace: UInt64 = 0
if let spaceCreate {
    line("  rufe CGSSpaceCreate(cid, 1, nil) ...")
    createdSpace = spaceCreate(cid, 1, nil)
    line("  zurückgegeben: spaceID=\(createdSpace)")
    let after = readDisplays()
    let allAfter = Set(after.flatMap { $0.spaces })
    let appeared = allAfter.contains(createdSpace)
    line("  taucht in Display-Struktur auf: \(appeared)  (sonst: 'Orphan'-Space)")
} else { line("  Symbol fehlt") }

step("5) SCHREIBEN: Fenster in anderen Space schieben (CGSAddWindowsToSpaces)")
// Zielspace bestimmen: erstellter Space, sonst ein anderer existierender.
let origSpaces = spacesOf(window: testWID)
var targetSpace: UInt64 = 0
if createdSpace != 0 { targetSpace = createdSpace }
else { targetSpace = before.flatMap { $0.spaces }.first { !origSpaces.contains($0) } ?? 0 }

if let addWindows, targetSpace != 0 {
    line("  schiebe wid=\(testWID) -> space \(targetSpace) ...")
    addWindows(cid, [NSNumber(value: testWID)] as CFArray, [NSNumber(value: targetSpace)] as CFArray)
    let now = spacesOf(window: testWID)
    line("  Fenster jetzt auf spaces=\(now)  -> Move wirkte: \(now.contains(targetSpace))")
    // zurückschieben
    if let orig = origSpaces.first {
        addWindows(cid, [NSNumber(value: testWID)] as CFArray, [NSNumber(value: orig)] as CFArray)
        line("  zurückgeschoben auf \(orig), jetzt spaces=\(spacesOf(window: testWID))")
    }
} else { line("  übersprungen (Symbol fehlt oder kein Zielspace)") }

step("6) SCHREIBEN: Space wechseln (CGSManagedDisplaySetCurrentSpace)")
if let setCurrent, let getCurrent, let mainDisplay = before.first(where: { $0.spaces.count > 1 }) ?? (createdSpace != 0 ? before.first : nil) {
    let from = getCurrent(cid, mainDisplay.id as CFString)
    let to = mainDisplay.spaces.first { $0 != from } ?? createdSpace
    if to != 0 {
        line("  Display \(mainDisplay.id): wechsle \(from) -> \(to) ...")
        setCurrent(cid, mainDisplay.id as CFString, to)
        usleep(400_000)
        let now = getCurrent(cid, mainDisplay.id as CFString)
        line("  jetzt current=\(now)  -> Switch wirkte: \(now == to)")
        // zurück
        setCurrent(cid, mainDisplay.id as CFString, from)
        line("  zurückgewechselt, current=\(getCurrent(cid, mainDisplay.id as CFString))")
    } else { line("  kein zweiter Space zum Wechseln vorhanden") }
} else { line("  übersprungen (nur 1 Space pro Display vorhanden / Symbol fehlt)") }

step("7) AUFRÄUMEN: erstellten Space löschen")
if createdSpace != 0, let spaceDestroy {
    spaceDestroy(cid, createdSpace)
    let gone = !Set(readDisplays().flatMap { $0.spaces }).contains(createdSpace)
    line("  Space \(createdSpace) gelöscht (verschwunden: \(gone))")
}

line("\nFERTIG.")
