import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class PaperCraneTimerViewTests: XCTestCase {
    func testFlatPaperKeepsItsColorAndTiltedPaperShadesOrGlows() {
        let red = PaperCranePalette.papers[0]
        XCTAssertEqual(PaperCranePalette.tone(.outside, shade: 1), red.outside)
        XCTAssertEqual(PaperCranePalette.tone(.inside, shade: 1), red.inside)

        let shaded = PaperCranePalette.tone(.outside, shade: 0.6)
        XCTAssertEqual(shaded.x, red.outside.x * 0.6, accuracy: 0.0001)

        let glowing = PaperCranePalette.tone(.outside, shade: 1.3)
        XCTAssertGreaterThan(glowing.y, red.outside.y)
        XCTAssertLessThanOrEqual(glowing.x, 1)

        let blue = PaperCranePalette.papers[5]
        XCTAssertEqual(PaperCranePalette.tone(.outside, shade: 1, paper: blue), blue.outside)
        XCTAssertEqual(PaperCranePalette.tone(.inside, shade: 1, paper: blue), blue.inside)
    }

    func testTenDistinctPapersEachWithALighterInsideAndDarkerEdge() {
        let papers = PaperCranePalette.papers
        XCTAssertEqual(papers.count, 10)
        XCTAssertEqual(papers[0].outside, SIMD3(0.8, 0.255, 0.224))
        for (index, paper) in papers.enumerated() {
            XCTAssertFalse(papers[..<index].contains(paper))
            for channel in 0..<3 {
                XCTAssertGreaterThan(paper.inside[channel], paper.outside[channel])
                XCTAssertLessThan(paper.edge[channel], paper.outside[channel])
            }
        }
    }

    func testFirstCraneOfEveryRunIsRedAndEachNextCraneChangesColor() {
        for _ in 0..<20 {
            let run = UUID()
            XCTAssertEqual(PaperCranePalette.paper(run: run, crane: 0), PaperCranePalette.papers[0])
            XCTAssertEqual(PaperCranePalette.paper(run: run, crane: -3), PaperCranePalette.papers[0])
            for crane in 1..<30 {
                XCTAssertNotEqual(PaperCranePalette.paper(run: run, crane: crane), PaperCranePalette.paper(run: run, crane: crane - 1))
            }
        }
    }

    func testCraneColorsAreStableForARunAndSpreadAcrossThePalette() {
        let run = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let sequence = (0..<200).map { PaperCranePalette.paper(run: run, crane: $0) }
        XCTAssertEqual(sequence, (0..<200).map { PaperCranePalette.paper(run: run, crane: $0) })
        XCTAssertEqual(Set(sequence.map(\.outside.x)).count, Set(PaperCranePalette.papers.map(\.outside.x)).count)

        let other = UUID(uuidString: "0B1E5D2A-4C3F-4E8B-9A7D-2F6C1E0B9D84")!
        XCTAssertNotEqual(sequence, (0..<200).map { PaperCranePalette.paper(run: other, crane: $0) })
    }

    func testArrowheadOpensBackTowardTheTail() {
        let head = PaperCraneTable.arrowhead(at: CGPoint(x: 100, y: 50), from: CGPoint(x: 0, y: 50)).cgPath
        let bounds = head.boundingBoxOfPath

        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.001)
        XCTAssertLessThan(bounds.minX, 100)
        XCTAssertGreaterThan(bounds.minX, 94)
        XCTAssertEqual(bounds.midY, 50, accuracy: 0.001)
        XCTAssertGreaterThan(bounds.height, 3)
    }

    func testCraneGlyphFillsItsBoxWithTheFinishedCraneSilhouette() {
        let path = PaperCraneGlyph().path(in: CGRect(x: 0, y: 0, width: 48, height: 36)).cgPath
        let bounds = path.boundingBoxOfPath

        XCTAssertFalse(PaperCraneGlyph.outline.isEmpty)
        XCTAssertGreaterThan(bounds.width, 30)
        XCTAssertLessThanOrEqual(bounds.width, 48.001)
        XCTAssertLessThanOrEqual(bounds.height, 36.001)
        XCTAssertEqual(bounds.midX, 24, accuracy: 0.01)
        XCTAssertEqual(bounds.midY, 18, accuracy: 0.01)
        var inside = 0
        for row in 0..<20 {
            for column in 0..<20 {
                let x = bounds.minX + bounds.width * (CGFloat(column) + 0.5) / 20
                let y = bounds.minY + bounds.height * (CGFloat(row) + 0.5) / 20
                if path.contains(CGPoint(x: x, y: y)) {
                    inside += 1
                }
            }
        }
        let filled = Double(inside) / 400
        XCTAssertGreaterThan(filled, 0.15)
        XCTAssertLessThan(filled, 0.75)
    }
}
