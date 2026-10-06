import CoreGraphics
import XCTest
@testable import App

final class HeLovesMeTimerViewTests: XCTestCase {
    func testPetalIsSlenderAtTheBaseWidestNearTheTipAndNotched() {
        let path = HeLovesMePetal().path(in: CGRect(x: 0, y: 0, width: 100, height: 30)).cgPath
        let bounds = path.boundingBoxOfPath

        XCTAssertEqual(bounds.minX, 0, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 30, accuracy: 1)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 15)))
        XCTAssertTrue(path.contains(CGPoint(x: 72, y: 2)))
        XCTAssertTrue(path.contains(CGPoint(x: 72, y: 28)))
        XCTAssertTrue(path.contains(CGPoint(x: 5, y: 15)))
        XCTAssertFalse(path.contains(CGPoint(x: 5, y: 5)))
        XCTAssertFalse(path.contains(CGPoint(x: 5, y: 25)))
        XCTAssertFalse(path.contains(CGPoint(x: 99, y: 15)))
        XCTAssertTrue(path.contains(CGPoint(x: 97, y: 10)))
        XCTAssertTrue(path.contains(CGPoint(x: 97, y: 20)))
    }
}
