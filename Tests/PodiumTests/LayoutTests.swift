import XCTest
@testable import Podium

final class LayoutTests: XCTestCase {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let portrait = CGRect(x: 0, y: 0, width: 600, height: 1000)

    private func assertNoOverlap(_ rects: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for i in rects.indices {
            for j in rects.indices where j > i {
                XCTAssertTrue(rects[i].intersection(rects[j]).isEmpty || rects[i].intersection(rects[j]).isNull,
                              "Rects \(i) und \(j) überlappen: \(rects[i]) vs \(rects[j])", file: file, line: line)
            }
        }
    }

    private func assertInside(_ rects: [CGRect], _ outer: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (i, r) in rects.enumerated() {
            XCTAssertTrue(outer.insetBy(dx: -0.5, dy: -0.5).contains(r), "Rect \(i) ragt raus: \(r)", file: file, line: line)
        }
    }

    func testFrameCounts() {
        for (count, expected) in [(1, 1), (2, 2), (3, 3), (4, 4)] {
            XCTAssertEqual(Layout.frames(visible: area, vertical: false, count: count, split: 0).count, expected)
            XCTAssertEqual(Layout.frames(visible: portrait, vertical: true, count: count, split: 0).count, expected)
        }
    }

    func testNoOverlapAndInsideForAllVariants() {
        for count in 1...4 {
            for split in 0...2 {
                for cross in 0...2 {
                    for (a, v) in [(area, false), (portrait, true)] {
                        let rects = Layout.frames(visible: a, vertical: v, count: count, split: split, cross: cross)
                        assertNoOverlap(rects)
                        assertInside(rects, a)
                    }
                }
            }
        }
    }

    func testCrossRatioAffectsSmallGroup() {
        // 3er quer: cross=1 -> oberes Stapel-Fenster höher als unteres.
        let h = Layout.frames(visible: area, vertical: false, count: 3, split: 0, cross: 1)
        XCTAssertGreaterThan(h[1].height, h[2].height)
        // 2x2: cross=1 -> obere Reihe höher, split unangetastet (Spalten gleich).
        let g = Layout.frames(visible: area, vertical: false, count: 4, split: 0, cross: 1)
        XCTAssertGreaterThan(g[0].height, g[2].height)
        XCTAssertEqual(g[0].width, g[1].width, accuracy: 1)
    }

    func testSplitRatios() {
        let r = Layout.frames(visible: area, vertical: false, count: 2, split: 1)
        XCTAssertGreaterThan(r[0].width, r[1].width)   // 67/33: erstes größer
        let r2 = Layout.frames(visible: area, vertical: false, count: 2, split: 2)
        XCTAssertLessThan(r2[0].width, r2[1].width)    // 33/67: erstes kleiner
        let r3 = Layout.frames(visible: area, vertical: false, count: 2, split: 0)
        XCTAssertEqual(r3[0].width, r3[1].width, accuracy: 1)
    }

    func testThreeWindowLayoutOrientation() {
        let h = Layout.frames(visible: area, vertical: false, count: 3, split: 0)
        XCTAssertEqual(h[0].height, area.insetBy(dx: Layout.gap, dy: Layout.gap).height)  // volle linke Spalte
        let v = Layout.frames(visible: portrait, vertical: true, count: 3, split: 0)
        XCTAssertEqual(v[0].width, portrait.insetBy(dx: Layout.gap, dy: Layout.gap).width) // volle obere Reihe
    }

    func testGridNeighborsMatchFrames() {
        // Jeder rechte/untere Nachbar laut gridNeighbors muss im Frame-Layout
        // tatsächlich rechts bzw. unterhalb des Referenz-Index liegen.
        for count in 2...4 {
            for v in [false, true] {
                let rects = Layout.frames(visible: area, vertical: v, count: count, split: 0)
                let (leftOf, topOf) = Layout.gridNeighbors(count: count, vertical: v)
                for (i, l) in leftOf { XCTAssertGreaterThan(rects[i].minX, rects[l].minX, "count=\(count) v=\(v)") }
                for (i, t) in topOf { XCTAssertGreaterThan(rects[i].minY, rects[t].minY, "count=\(count) v=\(v)") }
            }
        }
    }

    func testForegroundPartitionNonOverlapping() {
        let bounds = [
            CGRect(x: 0, y: 0, width: 400, height: 400),
            CGRect(x: 500, y: 0, width: 400, height: 400),
            CGRect(x: 0, y: 500, width: 400, height: 400),
        ]
        let (front, rest) = foregroundPartition(bounds)
        XCTAssertEqual(front, [0, 1, 2])
        XCTAssertTrue(rest.isEmpty)
    }

    func testForegroundPartitionHidesOccluded() {
        let bounds = [
            CGRect(x: 0, y: 0, width: 400, height: 400),
            CGRect(x: 50, y: 50, width: 300, height: 300),   // liegt fast komplett unter 0
        ]
        let (front, rest) = foregroundPartition(bounds)
        XCTAssertEqual(front, [0])
        XCTAssertEqual(rest, [1])
    }

    func testForegroundPartitionCapsAtMax() {
        let bounds = (0..<6).map { CGRect(x: CGFloat($0) * 500, y: 0, width: 400, height: 400) }
        let (front, rest) = foregroundPartition(bounds)
        XCTAssertEqual(front.count, Tuning.maxAssigned)
        XCTAssertEqual(rest.count, 2)
    }

    func testSlotOrderMatchesRealPositions() {
        // Vorderstes Fenster (Index 0) liegt real RECHTS -> muss Slot 1 bekommen.
        let right = CGRect(x: 1300, y: 0, width: 1200, height: 1400)
        let left = CGRect(x: 0, y: 0, width: 1200, height: 1400)
        XCTAssertEqual(slotOrderIndices([right, left], vertical: false), [1, 0])
        // Hochkant: oben zuerst.
        let bottom = CGRect(x: 0, y: 2200, width: 1400, height: 2000)
        let top = CGRect(x: 0, y: 0, width: 1400, height: 2000)
        XCTAssertEqual(slotOrderIndices([bottom, top], vertical: true), [1, 0])
        // 4 Fenster: Zeilen-major (oben-links, oben-rechts, unten-links, unten-rechts).
        let tl = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tr = CGRect(x: 200, y: 0, width: 100, height: 100)
        let bl = CGRect(x: 0, y: 200, width: 100, height: 100)
        let br = CGRect(x: 200, y: 200, width: 100, height: 100)
        XCTAssertEqual(slotOrderIndices([br, tl, bl, tr], vertical: false), [1, 3, 2, 0])
    }

    func testForegroundPartitionThresholdBoundary() {
        // ~19% Überlappung der kleineren Fläche -> bleibt Vordergrund
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let slight = CGRect(x: 81, y: 0, width: 100, height: 100)
        XCTAssertEqual(foregroundPartition([a, slight]).front, [0, 1])
        // ~40% Überlappung -> zweites fällt raus
        let heavy = CGRect(x: 60, y: 0, width: 100, height: 100)
        XCTAssertEqual(foregroundPartition([a, heavy]).front, [0])
    }
}
