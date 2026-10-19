import CoreGraphics
import XCTest
@testable import App

final class PaperCraneTimerViewTests: XCTestCase {
    func testFlatPaperKeepsItsColorAndTiltedPaperShadesOrGlows() {
        XCTAssertEqual(PaperCranePalette.tone(.color, shade: 1), PaperCranePalette.color)
        XCTAssertEqual(PaperCranePalette.tone(.white, shade: 1), PaperCranePalette.white)

        let shadedColor = PaperCranePalette.tone(.color, shade: 0.6)
        let shadedWhite = PaperCranePalette.tone(.white, shade: 0.6)
        XCTAssertLessThan(shadedColor.x, PaperCranePalette.color.x)
        XCTAssertGreaterThan(shadedWhite.x / PaperCranePalette.white.x, shadedColor.x / PaperCranePalette.color.x)

        let glowing = PaperCranePalette.tone(.color, shade: 1.3)
        XCTAssertGreaterThan(glowing.y, PaperCranePalette.color.y)
        XCTAssertLessThanOrEqual(glowing.x, 1)
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
