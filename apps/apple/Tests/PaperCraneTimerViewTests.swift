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
}
