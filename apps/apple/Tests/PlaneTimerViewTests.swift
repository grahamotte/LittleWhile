import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class PlaneTimerViewTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testJetPointsUpWithSweptWingsInsideItsBox() {
        let path = PlaneJet().path(in: rect).cgPath
        let bounds = path.boundingBoxOfPath

        XCTAssertGreaterThanOrEqual(bounds.minX, -0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, 100.5)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, 100.5)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 5)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 90)))
        XCTAssertTrue(path.contains(CGPoint(x: 5, y: 61)))
        XCTAssertTrue(path.contains(CGPoint(x: 95, y: 61)))
        XCTAssertTrue(path.contains(CGPoint(x: 30, y: 94)))
        XCTAssertFalse(path.contains(CGPoint(x: 5, y: 5)))
        XCTAssertFalse(path.contains(CGPoint(x: 95, y: 5)))
        XCTAssertFalse(path.contains(CGPoint(x: 10, y: 90)))
    }

    func testJetPartsAreMirroredAcrossTheFuselage() {
        for part in PlaneJet.Part.allCases {
            let bounds = PlaneJet(part: part).path(in: rect).cgPath.boundingBoxOfPath
            XCTAssertEqual(bounds.midX, 50, accuracy: 0.5, "\(part)")
        }
        let cockpit = PlaneJet(part: .cockpit).path(in: rect).cgPath.boundingBoxOfPath
        let tail = PlaneJet(part: .tail).path(in: rect).cgPath.boundingBoxOfPath
        XCTAssertLessThan(cockpit.maxY, tail.minY)
    }
}
