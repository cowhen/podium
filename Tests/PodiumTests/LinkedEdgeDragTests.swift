import XCTest
@testable import Podium

final class LinkedEdgeDragTests: XCTestCase {
    // MARK: nextLinked (Hysterese)

    func testNextLinkedEngagesBelowLowThresholdRegardlessOfCurrentState() {
        XCTAssertTrue(LinkedEdgeVelocity.nextLinked(current: false, velocity: 50, engage: 100, disengage: 300))
        XCTAssertTrue(LinkedEdgeVelocity.nextLinked(current: true, velocity: 50, engage: 100, disengage: 300))
    }

    func testNextLinkedDisengagesAboveHighThresholdRegardlessOfCurrentState() {
        XCTAssertFalse(LinkedEdgeVelocity.nextLinked(current: true, velocity: 400, engage: 100, disengage: 300))
        XCTAssertFalse(LinkedEdgeVelocity.nextLinked(current: false, velocity: 400, engage: 100, disengage: 300))
    }

    func testNextLinkedInsideHysteresisBandKeepsCurrentStateLinked() {
        XCTAssertTrue(LinkedEdgeVelocity.nextLinked(current: true, velocity: 200, engage: 100, disengage: 300))
    }

    func testNextLinkedInsideHysteresisBandKeepsCurrentStateUnlinked() {
        XCTAssertFalse(LinkedEdgeVelocity.nextLinked(current: false, velocity: 200, engage: 100, disengage: 300))
    }

    func testNextLinkedAtExactThresholdsIsInclusive() {
        // engage/disengage selbst zählen schon als "über der Schwelle", nicht
        // erst der nächste Wert darüber — sonst könnte eine Geste exakt am
        // Rand nie ein- oder ausrasten.
        XCTAssertTrue(LinkedEdgeVelocity.nextLinked(current: false, velocity: 100, engage: 100, disengage: 300))
        XCTAssertFalse(LinkedEdgeVelocity.nextLinked(current: true, velocity: 300, engage: 100, disengage: 300))
    }

    // MARK: smoothed (EMA)

    func testSmoothedWithNoPreviousReturnsSampleUnchanged() {
        XCTAssertEqual(LinkedEdgeVelocity.smoothed(previous: nil, sample: 500, alpha: 0.35), 500)
    }

    func testSmoothedBlendsPreviousAndSampleByAlpha() {
        // 0.35*500 + 0.65*100 = 175 + 65 = 240
        XCTAssertEqual(LinkedEdgeVelocity.smoothed(previous: 100, sample: 500, alpha: 0.35), 240, accuracy: 0.001)
    }

    // MARK: previewAlpha (kontinuierliches Feedback)

    func testPreviewAlphaIsFullBelowEngageThreshold() {
        XCTAssertEqual(LinkedEdgeVelocity.previewAlpha(velocity: 50, engage: 100, disengage: 300), 1)
    }

    func testPreviewAlphaIsZeroAtOrAboveDisengageThreshold() {
        XCTAssertEqual(LinkedEdgeVelocity.previewAlpha(velocity: 300, engage: 100, disengage: 300), 0)
        XCTAssertEqual(LinkedEdgeVelocity.previewAlpha(velocity: 500, engage: 100, disengage: 300), 0)
    }

    func testPreviewAlphaInterpolatesLinearlyInsideBand() {
        // Genau in der Mitte zwischen 100 und 300 -> 0.5.
        XCTAssertEqual(LinkedEdgeVelocity.previewAlpha(velocity: 200, engage: 100, disengage: 300), 0.5, accuracy: 0.001)
    }
}
