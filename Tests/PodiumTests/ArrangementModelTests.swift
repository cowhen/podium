import XCTest
import ApplicationServices
@testable import Podium

final class ArrangementModelTests: XCTestCase {
    private let d1: CGDirectDisplayID = 1
    private let d2: CGDirectDisplayID = 2

    // Dummy-WinInfo: AXUIElement wird nie angefasst (Model ist pur).
    private func win(_ id: CGWindowID, app: String = "App") -> WinInfo {
        WinInfo(ax: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
                pid: 1, windowID: id, app: app, title: "t\(id)",
                bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    // MARK: Zuordnung

    func testDropAppendsWhileRoomExists() {
        var m = ArrangementModel()
        m.stage = [win(1), win(2)]
        m.dropFromOutside(win(1), onto: d1)
        m.dropFromOutside(win(2), onto: d1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [1, 2])
        XCTAssertTrue(m.stage.isEmpty)
    }

    func testDropOnFullBoxDisplacesToStageFront() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1), win(2), win(3), win(4)]
        m.stage = [win(9)]
        m.dropFromOutside(win(5), onto: d1, preferredSlot: 1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [1, 5, 3, 4])
        XCTAssertEqual(m.stage.map(\.windowID), [2, 9])   // Verdrängtes vorn
    }

    func testDropOnFullBoxWithoutSlotReplacesLast() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1), win(2), win(3), win(4)]
        m.dropFromOutside(win(5), onto: d1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [1, 2, 3, 5])
        XCTAssertEqual(m.stage.map(\.windowID), [4])
    }

    func testCrossBoxMoveReportsSourceAndLeavesNoDuplicate() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1), win(2)]
        let source = m.dropFromOutside(win(2), onto: d2)
        XCTAssertEqual(source, d1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [1])
        XCTAssertEqual(m.assigned[d2]?.map(\.windowID), [2])
        XCTAssertFalse(m.onStage(2))
    }

    func testRemoveEverywhereClearsStageAndBox() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1)]
        m.stage = [win(2)]
        XCTAssertEqual(m.removeEverywhere(1), d1)
        XCTAssertNil(m.removeEverywhere(2))   // war nur auf der Bühne
        XCTAssertNil(m.boxOwner(of: 1))
        XCTAssertFalse(m.onStage(2))
    }

    func testDemoteMovesBoxWindowToStageEnd() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1), win(2)]
        m.stage = [win(9)]
        XCTAssertEqual(m.demote(win(1)), d1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [2])
        XCTAssertEqual(m.stage.map(\.windowID), [9, 1])
        XCTAssertNil(m.demote(win(9)))   // Bühnen-Fenster: no-op
    }

    func testSwapInBoxGuardsInvalidIndices() {
        var m = ArrangementModel()
        m.assigned[d1] = [win(1), win(2)]
        m.swapInBox(d1, 0, 1)
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [2, 1])
        m.swapInBox(d1, 0, 5)   // out of range: unverändert
        XCTAssertEqual(m.assigned[d1]?.map(\.windowID), [2, 1])
    }

    // MARK: Ratio-Logik

    func testStepModeOrderAndClamping() {
        XCTAssertEqual(ArrangementModel.stepMode(2, up: true), 0)    // 33 -> 50
        XCTAssertEqual(ArrangementModel.stepMode(0, up: true), 1)    // 50 -> 67
        XCTAssertEqual(ArrangementModel.stepMode(1, up: true), 1)    // 67 geklemmt
        XCTAssertEqual(ArrangementModel.stepMode(0, up: false), 2)   // 50 -> 33
        XCTAssertEqual(ArrangementModel.stepMode(2, up: false), 2)   // 33 geklemmt
    }

    func testClickCycleTwoWindows() {
        // Klick auf Slot 1: erst dessen Seite groß, zweiter Klick zurück.
        var s = ArrangementModel.clickCycle(count: 2, idx: 1, main: 0, cross: 0)
        XCTAssertEqual(s.main, 2)
        s = ArrangementModel.clickCycle(count: 2, idx: 1, main: s.main, cross: s.cross)
        XCTAssertEqual(s.main, 0)
    }

    func testClickCycleSmallWindowThreeStages() {
        // Kleines Fenster im 3er (Slot 2): Seite groß -> im Stapel groß -> Reset.
        var s = ArrangementModel.clickCycle(count: 3, idx: 2, main: 0, cross: 0)
        XCTAssertEqual(s.main, 2)
        s = ArrangementModel.clickCycle(count: 3, idx: 2, main: s.main, cross: s.cross)
        XCTAssertEqual((s.main, s.cross).1, 2)
        s = ArrangementModel.clickCycle(count: 3, idx: 2, main: s.main, cross: s.cross)
        XCTAssertEqual(s.main, 0)
        XCTAssertEqual(s.cross, 0)
    }

    func testClickCycleGridColumns() {
        // 2x2: gerade Slots = linke Spalte, ungerade = rechte.
        XCTAssertEqual(ArrangementModel.clickCycle(count: 4, idx: 0, main: 0, cross: 0).main, 1)
        XCTAssertEqual(ArrangementModel.clickCycle(count: 4, idx: 3, main: 0, cross: 0).main, 2)
    }
}
