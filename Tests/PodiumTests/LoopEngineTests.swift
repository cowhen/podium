import XCTest
@testable import Podium

final class LoopEngineTests: XCTestCase {
    // inner = bounds.insetBy(dx: 8, dy: 8) = (8, 8, 984, 584)
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testEdgeHalfAnchorsAtThatEdge() {
        XCTAssertEqual(LoopEngine.frame(zone: .left, variant: .half, in: bounds),
                       CGRect(x: 8, y: 8, width: 492, height: 584))
        XCTAssertEqual(LoopEngine.frame(zone: .right, variant: .half, in: bounds),
                       CGRect(x: 500, y: 8, width: 492, height: 584))
        XCTAssertEqual(LoopEngine.frame(zone: .top, variant: .half, in: bounds),
                       CGRect(x: 8, y: 8, width: 984, height: 292))
        XCTAssertEqual(LoopEngine.frame(zone: .bottom, variant: .half, in: bounds),
                       CGRect(x: 8, y: 300, width: 984, height: 292))
    }

    func testRemainderIsTheOppositeSideAndLeavesExactlyOneGapWhenSubdivided() {
        let leftFrame = LoopEngine.frame(zone: .left, variant: .half, in: bounds)   // (8,8,492,584)
        let rem = LoopEngine.remainder(of: leftFrame, in: bounds, edge: .left)
        XCTAssertEqual(rem, CGRect(x: 500, y: 0, width: 500, height: 600))
        // Layout.frames insetted die Restfläche selbst um den Gap — die erste
        // Nachbar-Kachel darf deshalb genau EINEN Gap vom gezogenen Fenster
        // entfernt beginnen, nicht zwei.
        let neighborFrames = Layout.frames(visible: rem, vertical: false, count: 2, split: 0)
        XCTAssertEqual(neighborFrames[0].minX, leftFrame.maxX + Layout.gap)
    }

    func testRemainderForAllFourEdges() {
        let left = LoopEngine.frame(zone: .left, variant: .third, in: bounds)
        XCTAssertEqual(LoopEngine.remainder(of: left, in: bounds, edge: .left).minX, left.maxX)

        let right = LoopEngine.frame(zone: .right, variant: .third, in: bounds)
        XCTAssertEqual(LoopEngine.remainder(of: right, in: bounds, edge: .right).maxX, right.minX, accuracy: 0.5)

        let top = LoopEngine.frame(zone: .top, variant: .third, in: bounds)
        XCTAssertEqual(LoopEngine.remainder(of: top, in: bounds, edge: .top).minY, top.maxY)

        let bottom = LoopEngine.frame(zone: .bottom, variant: .third, in: bounds)
        XCTAssertEqual(LoopEngine.remainder(of: bottom, in: bounds, edge: .bottom).maxY, bottom.minY, accuracy: 0.5)
    }

    func testRemainderForCornerIsUndefinedSoReturnsFullArea() {
        let tl = LoopEngine.frame(zone: .topLeft, variant: .half, in: bounds)
        XCTAssertEqual(LoopEngine.remainder(of: tl, in: bounds, edge: .topLeft), bounds)
    }

    func testEdgeThirdAndTwoThirds() {
        XCTAssertEqual(LoopEngine.frame(zone: .left, variant: .third, in: bounds).width, 328)
        XCTAssertEqual(LoopEngine.frame(zone: .left, variant: .twoThirds, in: bounds).width, 656)
    }

    func testCornerHalfIsQuarterOfScreen() {
        XCTAssertEqual(LoopEngine.frame(zone: .topLeft, variant: .half, in: bounds),
                       CGRect(x: 8, y: 8, width: 492, height: 292))
        XCTAssertEqual(LoopEngine.frame(zone: .bottomRight, variant: .half, in: bounds),
                       CGRect(x: 500, y: 300, width: 492, height: 292))
    }

    func testCornerVariantsScaleBothEdgesAndStayAnchored() {
        // inner = (8,8,984,584); ⅓: w=328 h=195, ⅔: w=656 h=389
        let tlThird = LoopEngine.frame(zone: .topLeft, variant: .third, in: bounds)
        XCTAssertEqual(tlThird, CGRect(x: 8, y: 8, width: 328, height: 195))
        let brTwoThirds = LoopEngine.frame(zone: .bottomRight, variant: .twoThirds, in: bounds)
        XCTAssertEqual(brTwoThirds.maxX, 992, accuracy: 0.5)   // bleibt in der Ecke verankert
        XCTAssertEqual(brTwoThirds.maxY, 592, accuracy: 0.5)
        XCTAssertEqual(brTwoThirds.width, 656)
        XCTAssertEqual(brTwoThirds.height, 389)
    }

    func testNextVariantCyclesHalfThirdTwoThirdsAndWraps() {
        XCTAssertEqual(LoopEngine.nextVariant(.half), .third)
        XCTAssertEqual(LoopEngine.nextVariant(.third), .twoThirds)
        XCTAssertEqual(LoopEngine.nextVariant(.twoThirds), .half)
    }

    func testGeneralActions() {
        let current = CGRect(x: 100, y: 50, width: 300, height: 200)
        XCTAssertEqual(LoopEngine.generalFrame(.maximize, in: bounds, current: current),
                       CGRect(x: 8, y: 8, width: 984, height: 584))
        XCTAssertEqual(LoopEngine.generalFrame(.almostMaximize, in: bounds, current: current),
                       CGRect(x: 57, y: 37, width: 886, height: 526))
        XCTAssertEqual(LoopEngine.generalFrame(.maximizeHeight, in: bounds, current: current),
                       CGRect(x: 100, y: 8, width: 300, height: 584))
        XCTAssertEqual(LoopEngine.generalFrame(.maximizeWidth, in: bounds, current: current),
                       CGRect(x: 8, y: 50, width: 984, height: 200))
        XCTAssertEqual(LoopEngine.generalFrame(.center, in: bounds, current: current),
                       CGRect(x: 350, y: 200, width: 300, height: 200))
    }

    func testMaximizeHeightClampsOriginWhenCurrentIsOutOfBounds() {
        // Fenster steht (fast) am rechten Rand -> Breite darf es nicht aus der Fläche schieben.
        let current = CGRect(x: 900, y: 50, width: 300, height: 200)
        let f = LoopEngine.generalFrame(.maximizeHeight, in: bounds, current: current)
        XCTAssertEqual(f.maxX, 992, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(f.minX, 8)
    }

    func testExtraZones() {
        XCTAssertEqual(LoopEngine.extraFrame(.centerHalfHorizontal, in: bounds),
                       CGRect(x: 254, y: 8, width: 492, height: 584))
        XCTAssertEqual(LoopEngine.extraFrame(.centerHalfVertical, in: bounds),
                       CGRect(x: 8, y: 154, width: 984, height: 292))
        XCTAssertEqual(LoopEngine.extraFrame(.leftFourths(.quarter), in: bounds),
                       CGRect(x: 8, y: 8, width: 246, height: 584))
        XCTAssertEqual(LoopEngine.extraFrame(.rightFourths(.half), in: bounds),
                       CGRect(x: 500, y: 8, width: 492, height: 584))
    }

    func testProportionalFramePreservesRelativePositionAcrossDisplays() {
        let source = Display(id: 1, name: "A", full: CGRect(x: 0, y: 0, width: 1000, height: 600),
                             visible: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let destination = Display(id: 2, name: "B", full: CGRect(x: 1000, y: 0, width: 1000, height: 600),
                                  visible: CGRect(x: 2000, y: 0, width: 1000, height: 600))
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let result = LoopEngine.proportionalFrame(frame, from: source, to: destination)
        XCTAssertEqual(result.minX, 2100, accuracy: 0.5)
        XCTAssertEqual(result.minY, 100, accuracy: 0.5)
        XCTAssertEqual(result.width, 400, accuracy: 0.5)
        XCTAssertEqual(result.height, 300, accuracy: 0.5)
    }

    func testProportionalFrameClampsWithinSmallerDestination() {
        let source = Display(id: 1, name: "A", full: CGRect(x: 0, y: 0, width: 2000, height: 1200),
                             visible: CGRect(x: 0, y: 0, width: 2000, height: 1200))
        let destination = Display(id: 2, name: "B", full: CGRect(x: 0, y: 0, width: 800, height: 600),
                                  visible: CGRect(x: 0, y: 0, width: 800, height: 600))
        // Fenster nahe der rechten unteren Ecke der großen Quelle.
        let frame = CGRect(x: 1900, y: 1100, width: 90, height: 90)
        let result = LoopEngine.proportionalFrame(frame, from: source, to: destination)
        XCTAssertLessThanOrEqual(result.maxX, destination.visible.maxX + 0.5)
        XCTAssertLessThanOrEqual(result.maxY, destination.visible.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(result.minX, destination.visible.minX)
        XCTAssertGreaterThanOrEqual(result.minY, destination.visible.minY)
    }

    func testNeighborDisplayHorizontalArrangement() {
        let left = Display(id: 1, name: "L", full: CGRect(x: 0, y: 0, width: 1000, height: 600), visible: .zero)
        let mid = Display(id: 2, name: "M", full: CGRect(x: 1000, y: 0, width: 1000, height: 600), visible: .zero)
        let right = Display(id: 3, name: "R", full: CGRect(x: 2000, y: 0, width: 1000, height: 600), visible: .zero)
        let all = [left, mid, right]
        XCTAssertEqual(LoopEngine.neighborDisplay(of: mid, direction: .right, among: all)?.id, right.id)
        XCTAssertEqual(LoopEngine.neighborDisplay(of: mid, direction: .left, among: all)?.id, left.id)
        XCTAssertNil(LoopEngine.neighborDisplay(of: left, direction: .left, among: all))
    }

    func testNeighborDisplayVerticalArrangement() {
        let top = Display(id: 1, name: "T", full: CGRect(x: 0, y: 0, width: 1000, height: 600), visible: .zero)
        let bottom = Display(id: 2, name: "B", full: CGRect(x: 0, y: 600, width: 1000, height: 600), visible: .zero)
        let all = [top, bottom]
        XCTAssertEqual(LoopEngine.neighborDisplay(of: top, direction: .down, among: all)?.id, bottom.id)
        XCTAssertEqual(LoopEngine.neighborDisplay(of: bottom, direction: .up, among: all)?.id, top.id)
        XCTAssertNil(LoopEngine.neighborDisplay(of: top, direction: .up, among: all))
    }

    func testNearestEdge() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertEqual(LoopEngine.nearestEdge(of: CGRect(x: 5, y: 200, width: 300, height: 200), in: area), .left)
        XCTAssertEqual(LoopEngine.nearestEdge(of: CGRect(x: 695, y: 200, width: 300, height: 200), in: area), .right)
        XCTAssertEqual(LoopEngine.nearestEdge(of: CGRect(x: 300, y: 5, width: 300, height: 200), in: area), .top)
        XCTAssertEqual(LoopEngine.nearestEdge(of: CGRect(x: 300, y: 395, width: 300, height: 200), in: area), .bottom)
    }

    func testStashFrameLeavesOnlySliverVisible() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let frame = CGRect(x: 5, y: 200, width: 300, height: 200)
        XCTAssertEqual(LoopEngine.stashFrame(frame, edge: .left, in: area, sliver: 6).origin.x, -294)
        XCTAssertEqual(LoopEngine.stashFrame(frame, edge: .right, in: area, sliver: 6).origin.x, 994)
        XCTAssertEqual(LoopEngine.stashFrame(frame, edge: .top, in: area, sliver: 6).origin.y, -194)
        XCTAssertEqual(LoopEngine.stashFrame(frame, edge: .bottom, in: area, sliver: 6).origin.y, 594)
    }
}
