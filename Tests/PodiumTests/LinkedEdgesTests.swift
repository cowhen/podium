import XCTest
@testable import Podium

final class LinkedEdgesTests: XCTestCase {
    func testRightEdgeGrowthPushesRightNeighborsLeftEdge() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 0, y: 0, width: 600, height: 600)   // rechte Kante 500 -> 600
        let rightNeighbor = CGRect(x: 508, y: 0, width: 492, height: 600)   // minX = 500+gap(8)

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [rightNeighbor])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0], CGRect(x: 608, y: 0, width: 392, height: 600))
    }

    func testLeftEdgeShrinkPullsLeftNeighborsRightEdge() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 100, y: 0, width: 400, height: 600)   // linke Kante 0 -> 100
        let leftNeighbor = CGRect(x: -508, y: 0, width: 500, height: 600)   // maxX = 0-gap(8) = -8

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [leftNeighbor])
        XCTAssertEqual(updates.count, 1)
        // neue rechte Kante = 100-8 = 92; Breite = 92 - (-508) = 600
        XCTAssertEqual(updates[0], CGRect(x: -508, y: 0, width: 600, height: 600))
    }

    func testBottomEdgeGrowthPushesNeighborBelow() {
        let old = CGRect(x: 0, y: 0, width: 800, height: 300)
        let new = CGRect(x: 0, y: 0, width: 800, height: 400)   // untere Kante (maxY) 300 -> 400
        let below = CGRect(x: 0, y: 308, width: 800, height: 292)   // minY = 300+gap(8)

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [below])
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0], CGRect(x: 0, y: 408, width: 800, height: 192))
    }

    func testDifferentRowIsNotTreatedAsNeighborDespiteMatchingXCoordinate() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 300)
        let new = CGRect(x: 0, y: 0, width: 600, height: 300)
        // Gleiche X-Kante (508 = 500+gap), aber komplett andere Reihe -> keine Überlappung.
        let farBelow = CGRect(x: 508, y: 400, width: 492, height: 200)

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [farBelow])
        XCTAssertTrue(updates.isEmpty)
    }

    func testUnrelatedWindowFarFromEdgeIsIgnored() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 0, y: 0, width: 600, height: 600)
        let farAway = CGRect(x: 2000, y: 0, width: 500, height: 600)   // ganz woanders

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [farAway])
        XCTAssertTrue(updates.isEmpty)
    }

    func testCornerResizeInTwoByTwoGridAffectsOnlyTrueEdgeNeighborsNotDiagonal() {
        // TL (resized) wächst per Eck-Resize; TR/BL teilen eine echte Kante,
        // BR nur die Ecke -> darf NICHT mitbewegt werden.
        let old = CGRect(x: 0, y: 0, width: 496, height: 296)
        let new = CGRect(x: 0, y: 0, width: 550, height: 350)
        let tr = CGRect(x: 504, y: 0, width: 496, height: 296)
        let bl = CGRect(x: 0, y: 304, width: 496, height: 296)
        let br = CGRect(x: 504, y: 304, width: 496, height: 296)

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [tr, bl, br])
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0], CGRect(x: 558, y: 0, width: 442, height: 296))   // TR
        XCTAssertEqual(updates[1], CGRect(x: 0, y: 358, width: 496, height: 242))   // BL
        XCTAssertNil(updates[2])   // BR bleibt unangetastet
    }

    func testNoActualSizeChangeProducesNoUpdates() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 600)
        let neighbor = CGRect(x: 508, y: 0, width: 492, height: 600)
        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: frame, resizedNew: frame,
                                                         candidates: [neighbor])
        XCTAssertTrue(updates.isEmpty)
    }

    func testPureMoveProducesNoUpdates() {
        // Fenster wird nur VERSCHOBEN (Größe identisch) — ohne den Größen-Guard
        // würden beide X-Zweige feuern und der Ex-Nachbar an der alten Kante
        // mitgerissen. Ein Move ist kein Resize; niemand darf folgen.
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 900, y: 200, width: 500, height: 600)
        let exNeighbor = CGRect(x: 508, y: 0, width: 492, height: 600)   // saß an old.maxX + gap

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [exNeighbor])
        XCTAssertTrue(updates.isEmpty)
    }

    func testNeighborNeverShrinksBelowMinimumEdge() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 0, y: 0, width: 990, height: 600)   // Nachbar hätte nur noch 18pt Platz
        let rightNeighbor = CGRect(x: 508, y: 0, width: 492, height: 600)

        let updates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                         candidates: [rightNeighbor], minEdge: 120)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0]?.width, 120)
    }

    func testToleranceAllowsSmallRoundingButRejectsUnrelatedGap() {
        let old = CGRect(x: 0, y: 0, width: 500, height: 600)
        let new = CGRect(x: 0, y: 0, width: 600, height: 600)
        // Erwartete alte Kante: old.maxX + gap = 500 + 8 = 508.
        let almostTouching = CGRect(x: 511, y: 0, width: 492, height: 600)   // 3pt Rundungsdrift, innerhalb Toleranz
        let clearlySeparate = CGRect(x: 700, y: 0, width: 492, height: 600)  // eigenständiges Layout, kein Nachbar

        let closeUpdates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                              candidates: [almostTouching])
        XCTAssertEqual(closeUpdates.count, 1)

        let farUpdates = LinkedEdges.computeNeighborUpdates(resizedOld: old, resizedNew: new,
                                                            candidates: [clearlySeparate])
        XCTAssertTrue(farUpdates.isEmpty)
    }
}
