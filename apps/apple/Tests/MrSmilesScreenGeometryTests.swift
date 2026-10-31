import XCTest
@testable import LittleWhileCore

final class MrSmilesScreenGeometryTests: XCTestCase {
    func testScreenWithoutHomeIndicatorUsesSquareCorners() {
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 20, safeAreaBottom: 0), 0)
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 0, safeAreaBottom: 0), 0)
    }

    func testRoundedScreenUsesTheLargerSafeAreaEstimate() {
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 59, safeAreaBottom: 34), 61.2, accuracy: 0.001)
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 62, safeAreaBottom: 34), 62)
    }

    func testLandscapeKeepsAConservativeRoundedCornerEstimate() {
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 0, safeAreaBottom: 21), 60)
    }

    func testLargerInsetsDoNotExaggerateCornerSize() {
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 120, safeAreaBottom: 34), 80)
        XCTAssertEqual(MrSmilesScreenGeometry.cornerRadius(safeAreaTop: 59, safeAreaBottom: 100), 80)
    }
}
