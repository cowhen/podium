import XCTest
@testable import Podium

final class BentoLayoutTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testEdgeZones() {
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 5, y: 300), margin: 24, cornerSize: 60), .left)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 995, y: 300), margin: 24, cornerSize: 60), .right)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 500, y: 5), margin: 24, cornerSize: 60), .top)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 500, y: 595), margin: 24, cornerSize: 60), .bottom)
        XCTAssertNil(BentoLayout.zone(in: bounds, point: CGPoint(x: 500, y: 300), margin: 24, cornerSize: 60))
    }

    func testCornerZonesTakePriorityOverEdges() {
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 10, y: 10), margin: 24, cornerSize: 60), .topLeft)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 990, y: 10), margin: 24, cornerSize: 60), .topRight)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 10, y: 590), margin: 24, cornerSize: 60), .bottomLeft)
        XCTAssertEqual(BentoLayout.zone(in: bounds, point: CGPoint(x: 990, y: 590), margin: 24, cornerSize: 60), .bottomRight)
    }

    func testEdgePlanIsCleanTwoWaySplit() {
        let left = BentoLayout.plan(zone: .left, othersAvailable: 3)
        XCTAssertEqual(left.tokens, [.dragged, .other(0)])   // nie mehr als 1 anderes, Rand bleibt fixer Split
        XCTAssertEqual(left.vertical, false)   // Rand erzwingt die Richtung, unabhängig vom Monitor
        let top = BentoLayout.plan(zone: .top, othersAvailable: 3)
        XCTAssertEqual(top.tokens, [.dragged, .other(0)])
        XCTAssertEqual(top.vertical, true)
        let bottom = BentoLayout.plan(zone: .bottom, othersAvailable: 0)
        XCTAssertEqual(bottom.tokens, [.other(0), .dragged])
    }

    func testCornerPlanGrowsToFourWhenEnoughWindows() {
        let tl = BentoLayout.plan(zone: .topLeft, othersAvailable: 3)
        XCTAssertEqual(tl.tokens, [.dragged, .other(0), .other(1), .other(2)])
        XCTAssertNil(tl.vertical)   // Ecke: natürliche Monitor-Ausrichtung gilt
        let br = BentoLayout.plan(zone: .bottomRight, othersAvailable: 3)
        XCTAssertEqual(br.tokens, [.other(0), .other(1), .other(2), .dragged])
        // Alle 4 Slots einmalig belegt, kein Fenster doppelt/fehlend.
        for zone: BentoZone in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let tokens = BentoLayout.plan(zone: zone, othersAvailable: 3).tokens
            XCTAssertEqual(Set(tokens.map { "\($0)" }).count, 4)
        }
    }

    func testCornerPlanDegradesToThreeWindowLayout() {
        // Linke Ecken -> immer die große linke Spalte, unabhängig von oben/unten.
        XCTAssertEqual(BentoLayout.plan(zone: .topLeft, othersAvailable: 2).tokens, [.dragged, .other(0), .other(1)])
        XCTAssertEqual(BentoLayout.plan(zone: .bottomLeft, othersAvailable: 2).tokens, [.dragged, .other(0), .other(1)])
        XCTAssertEqual(BentoLayout.plan(zone: .topRight, othersAvailable: 2).tokens, [.other(0), .dragged, .other(1)])
        XCTAssertEqual(BentoLayout.plan(zone: .bottomRight, othersAvailable: 2).tokens, [.other(0), .other(1), .dragged])
    }

    func testCornerPlanDegradesToEdgeWhenTooFewWindows() {
        XCTAssertEqual(BentoLayout.plan(zone: .topLeft, othersAvailable: 1).tokens, [.dragged, .other(0)])
        XCTAssertEqual(BentoLayout.plan(zone: .topRight, othersAvailable: 1).tokens, [.other(0), .dragged])
        XCTAssertEqual(BentoLayout.plan(zone: .topLeft, othersAvailable: 0).tokens, [.dragged])
    }
}
