import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class GraveyardTimerViewTests: XCTestCase {
    func testGhostHasARoundHeadAndATatteredHemInsideItsBox() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 120)
        let path = GraveyardGhost().path(in: rect).cgPath
        let bounds = path.boundingBoxOfPath

        XCTAssertGreaterThanOrEqual(bounds.minX, -0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, 100.5)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, 120.5)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 10)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 60)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 90)))
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 98, y: 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 10, y: 114)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 114)))
    }

    func testGhostHemRipplesWithTheWave() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 120)

        XCTAssertNotEqual(
            GraveyardGhost(wave: 0).path(in: rect).cgPath.boundingBoxOfPath,
            GraveyardGhost(wave: 1.4).path(in: rect).cgPath.boundingBoxOfPath,
        )
    }

    func testEveryTombstoneStyleStandsOnItsBase() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 80)

        for style in GraveyardGrave.Style.allCases {
            let path = GraveyardTombstone(style: style).path(in: rect).cgPath
            let bounds = path.boundingBoxOfPath
            XCTAssertEqual(bounds.maxY, 80, accuracy: 0.5, "\(style)")
            XCTAssertLessThanOrEqual(bounds.maxX, 60.5, "\(style)")
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.5, "\(style)")
            XCTAssertTrue(path.contains(CGPoint(x: 30, y: 60)), "\(style)")
        }
        let cross = GraveyardTombstone(style: .cross).path(in: rect).cgPath
        XCTAssertTrue(cross.contains(CGPoint(x: 3, y: 22)))
        XCTAssertFalse(cross.contains(CGPoint(x: 3, y: 60)))
        let rounded = GraveyardTombstone(style: .rounded).path(in: rect).cgPath
        XCTAssertFalse(rounded.contains(CGPoint(x: 2, y: 2)))
        XCTAssertTrue(rounded.contains(CGPoint(x: 30, y: 2)))
    }
}
