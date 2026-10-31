import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class MrSmilesTimerViewTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testHeartAndStarEyesAreMuchLargerThanTheOpenEye() {
        XCTAssertGreaterThan(MrSmilesEyeMetrics.heartWidth, 0.21)
        XCTAssertGreaterThan(MrSmilesEyeMetrics.heartHeight, 0.21)
        XCTAssertGreaterThan(MrSmilesEyeMetrics.starSize, 0.21)
        XCTAssertEqual(MrSmilesEyeMetrics.heartWidth, MrSmilesEyeMetrics.starSize, accuracy: 0.0001)
        XCTAssertGreaterThan(MrSmilesEyeMetrics.heartWidth, MrSmilesEyeMetrics.heartHeight)
    }

    func testHeartAndStarEyesTiltInwardAndSitFartherApart() {
        XCTAssertGreaterThan(MrSmilesEyeMetrics.inwardRotation, 10)
        XCTAssertEqual(MrSmilesEyeMetrics.rotation(isLeft: true), -MrSmilesEyeMetrics.inwardRotation, accuracy: 0.0001)
        XCTAssertEqual(MrSmilesEyeMetrics.rotation(isLeft: false), MrSmilesEyeMetrics.inwardRotation, accuracy: 0.0001)
        XCTAssertLessThan(MrSmilesEyeMetrics.symbolX, MrSmilesEyeMetrics.openX)
        XCTAssertEqual(MrSmilesEyeMetrics.centerX(isLeft: true, symbol: true), MrSmilesEyeMetrics.symbolX, accuracy: 0.0001)
        XCTAssertEqual(MrSmilesEyeMetrics.centerX(isLeft: false, symbol: true), 1 - MrSmilesEyeMetrics.symbolX, accuracy: 0.0001)
        XCTAssertGreaterThan(
            MrSmilesEyeMetrics.centerX(isLeft: false, symbol: true) - MrSmilesEyeMetrics.centerX(isLeft: true, symbol: true),
            MrSmilesEyeMetrics.centerX(isLeft: false, symbol: false) - MrSmilesEyeMetrics.centerX(isLeft: true, symbol: false),
        )
    }

    func testHeartHasWideCircularLobesAndARightAnglePoint() {
        let path = MrSmilesHeart().path(in: rect).cgPath
        let bounds = path.boundingBoxOfPath

        XCTAssertEqual(bounds.width / bounds.height, 1.16, accuracy: 0.03)
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50)))
        XCTAssertTrue(path.contains(CGPoint(x: 26, y: 32)))
        XCTAssertTrue(path.contains(CGPoint(x: 74, y: 32)))
        XCTAssertTrue(path.contains(CGPoint(x: 26, y: 12)))
        XCTAssertTrue(path.contains(CGPoint(x: 74, y: 12)))
        XCTAssertTrue(path.contains(CGPoint(x: 2, y: 32)))
        XCTAssertTrue(path.contains(CGPoint(x: 98, y: 32)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 85)))
        XCTAssertTrue(path.contains(CGPoint(x: 40, y: 70)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 18)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 4)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 97)))
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 2)))
        XCTAssertFalse(path.contains(CGPoint(x: 15, y: 75)))
        XCTAssertFalse(path.contains(CGPoint(x: 85, y: 75)))
    }

    func testStarHasChubbyRoundedPoints() {
        let path = MrSmilesStar().path(in: rect).cgPath

        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 22)))
        XCTAssertTrue(path.contains(CGPoint(x: 56, y: 22)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 18)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 12)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 99)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 99, y: 50)))
    }

    func testRoundedPolygonCutsSharpCorners() {
        let square = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
        ]
        let path = mrSmilesRoundedPolygon(square, cornerRadii: [20, 20, 20, 20]).cgPath

        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: 8)))
    }
}
