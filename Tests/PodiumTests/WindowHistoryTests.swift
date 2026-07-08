import XCTest
@testable import Podium

final class WindowHistoryTests: XCTestCase {
    func testRecordsOnlyOnceAndReturnsFirstFrame() {
        let id: CGWindowID = 111
        let history = WindowHistory.shared
        history.forget(id)   // saubere Ausgangslage, falls ein anderer Test denselben Prozess teilt
        XCTAssertNil(history.undoFrame(id))

        history.recordIfNeeded(id, currentFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        history.recordIfNeeded(id, currentFrame: CGRect(x: 500, y: 500, width: 200, height: 200))
        XCTAssertEqual(history.undoFrame(id), CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testForgetClearsHistory() {
        let id: CGWindowID = 222
        let history = WindowHistory.shared
        history.recordIfNeeded(id, currentFrame: CGRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertNotNil(history.undoFrame(id))
        history.forget(id)
        XCTAssertNil(history.undoFrame(id))
    }

    func testDifferentWindowsAreIndependent() {
        let history = WindowHistory.shared
        history.forget(333); history.forget(444)
        history.recordIfNeeded(333, currentFrame: CGRect(x: 1, y: 1, width: 1, height: 1))
        XCTAssertNil(history.undoFrame(444))
        XCTAssertNotNil(history.undoFrame(333))
    }
}
