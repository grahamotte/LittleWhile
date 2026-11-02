import SwiftUI
import XCTest
@testable import LittleWhileCore

final class PlaneGlobeTests: XCTestCase {
    private let center = CGPoint(x: 200, y: 300)

    func testVectorsRoundTripLatitudeAndLongitude() {
        let point = PlaneVector(latitude: 35.7, longitude: 139.7)

        XCTAssertEqual(point.length, 1, accuracy: 1e-12)
        XCTAssertEqual(point.latitude, 35.7, accuracy: 1e-9)
        XCTAssertEqual(point.longitude, 139.7, accuracy: 1e-9)
        XCTAssertEqual(PlaneVector(latitude: 90, longitude: 40).longitude, 0)
        XCTAssertEqual(PlaneVector(x: 0, y: 0, z: 0).normalized, PlaneVector(x: 1, y: 0, z: 0))
    }

    func testSlerpFollowsTheGreatCircleAtConstantSpeed() {
        let start = PlaneVector(latitude: 0, longitude: 0)
        let end = PlaneVector(latitude: 0, longitude: 90)

        let middle = PlaneVector.slerp(start, end, 0.5)
        XCTAssertEqual(middle.longitude, 45, accuracy: 1e-9)
        XCTAssertEqual(middle.length, 1, accuracy: 1e-12)
        XCTAssertEqual(start.angle(to: PlaneVector.slerp(start, end, 0.25)), .pi / 8, accuracy: 1e-9)
        XCTAssertEqual(PlaneVector.slerp(start, start, 0.5), start)
        let opposite = PlaneVector(latitude: 0, longitude: 180)
        XCTAssertEqual(PlaneVector.slerp(start, opposite, 0).longitude, 0, accuracy: 1e-9)
    }

    func testProjectionPutsTheCameraCenterInTheMiddleWithNorthUpAndEastRight() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))

        XCTAssertEqual(globe.project(PlaneVector(latitude: 0, longitude: 0)), center)
        XCTAssertEqual(globe.project(PlaneVector(latitude: 90, longitude: 0)).y, 200, accuracy: 1e-9)
        XCTAssertEqual(globe.project(PlaneVector(latitude: 0, longitude: 90)).x, 300, accuracy: 1e-9)
        XCTAssertEqual(globe.project(PlaneVector(latitude: 90, longitude: 0), altitude: 0.1).y, 190, accuracy: 1e-9)
        XCTAssertEqual(globe.depth(PlaneVector(latitude: 0, longitude: 0)), 1, accuracy: 1e-12)
        XCTAssertEqual(globe.depth(PlaneVector(latitude: 0, longitude: 180)), -1, accuracy: 1e-12)

        let tilted = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 50, longitude: -120))
        let point = tilted.project(PlaneVector(latitude: 50, longitude: -120))
        XCTAssertEqual(point.x, center.x, accuracy: 1e-9)
        XCTAssertEqual(point.y, center.y, accuracy: 1e-9)
        XCTAssertLessThan(tilted.project(PlaneVector(latitude: 60, longitude: -120)).y, center.y)
        XCTAssertGreaterThan(tilted.project(PlaneVector(latitude: 50, longitude: -110)).x, center.x)
    }

    func testScreenVectorsForeshortenTowardTheRim() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))

        XCTAssertEqual(globe.screenVector(PlaneVector(x: 0, y: 0, z: 1)), CGVector(dx: 0, dy: -1))
        XCTAssertEqual(globe.screenVector(PlaneVector(x: 0, y: 1, z: 0)), CGVector(dx: 1, dy: 0))
        XCTAssertEqual(globe.screenVector(PlaneVector(x: 1, y: 0, z: 0)), CGVector(dx: 0, dy: 0))
        let tilted = globe.screenVector(PlaneVector(latitude: 0, longitude: 60) * 1)
        XCTAssertEqual(tilted.dx, sin(.pi / 3), accuracy: 1e-9)
        XCTAssertEqual(tilted.dy, 0, accuracy: 1e-9)
    }

    func testVisibleLandIsDrawnInPlaceAndHiddenLandIsSkipped() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))
        let front = PlaneAtlas.ring("-100,-100 100,-100 100,100 -100,100")
        let back = PlaneAtlas.ring("1700,-100 1790,-100 1790,100 1700,100")

        let path = globe.landPath(front).cgPath
        XCTAssertTrue(path.contains(center))
        XCTAssertLessThan(path.boundingBoxOfPath.width, 40)
        XCTAssertTrue(globe.landPath(back).isEmpty)
        XCTAssertTrue(globe.landPath(Array(front.prefix(2))).isEmpty)
    }

    func testLandCrossingTheHorizonIsClippedAlongTheEdgeOfTheGlobe() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))
        let ring = PlaneAtlas.ring("600,-300 1200,-300 1200,300 600,300")

        let path = globe.landPath(ring).cgPath
        let bounds = path.boundingBoxOfPath
        XCTAssertEqual(bounds.maxX, 300, accuracy: 0.5)
        XCTAssertTrue(path.contains(CGPoint(x: 296, y: 300)))
        XCTAssertTrue(path.contains(CGPoint(x: 290, y: 330)))
        XCTAssertFalse(path.contains(CGPoint(x: 270, y: 300)))
        XCTAssertFalse(path.contains(center))
    }

    func testLandWrappingBehindTheGlobeFollowsTheRimTheShortWayRound() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))
        let ring = PlaneAtlas.ring("-1200,600 -600,600 0,600 600,600 1200,600 1800,600 1800,900 -1800,900 -1800,600")

        let path = globe.landPath(ring).cgPath
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 205)))
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 210)))
        XCTAssertFalse(path.contains(CGPoint(x: 200, y: 220)))
        XCTAssertFalse(path.contains(center))
        XCTAssertFalse(path.contains(CGPoint(x: 200, y: 395)))
    }

    func testLandWrappingThePointBehindTheGlobeOnlyFillsTheSliversThatPeekOverTheRim() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))
        let ring = PlaneAtlas.ring("800,-600 800,600 1800,600 -800,600 -800,-600 1800,-600")

        let path = globe.landPath(ring).cgPath
        XCTAssertTrue(path.contains(CGPoint(x: 299.5, y: 300)))
        XCTAssertTrue(path.contains(CGPoint(x: 100.5, y: 300)))
        XCTAssertFalse(path.contains(center))
        XCTAssertFalse(path.contains(CGPoint(x: 200, y: 220)))
        XCTAssertFalse(path.contains(CGPoint(x: 260, y: 300)))
        XCTAssertFalse(path.contains(CGPoint(x: 140, y: 300)))
    }

    func testRealLandNeverCoversTheWholeGlobeFromAnyAngle() {
        let probes = [CGPoint(x: 200, y: 300), CGPoint(x: 290, y: 300), CGPoint(x: 110, y: 300), CGPoint(x: 200, y: 390), CGPoint(x: 200, y: 210)]
        for latitude in stride(from: -80.0, through: 80, by: 20) {
            for longitude in stride(from: -180.0, to: 180, by: 20) {
                let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: latitude, longitude: longitude))
                for ring in PlaneAtlas.land {
                    let path = globe.landPath(ring).cgPath
                    XCTAssertFalse(probes.allSatisfy { path.contains($0) }, "\(latitude), \(longitude)")
                }
            }
        }
    }

    func testLinesStopAtTheHorizon() {
        let globe = PlaneGlobe(center: center, radius: 100, camera: PlaneCamera(latitude: 0, longitude: 0))

        let bounds = globe.linePath(PlaneGlobe.parallel(latitude: 0)).cgPath.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, 100, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 300, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 0, accuracy: 1e-6)
        XCTAssertTrue(globe.linePath([PlaneVector(latitude: 0, longitude: 170), PlaneVector(latitude: 0, longitude: 175)]).isEmpty)
        let meridian = globe.linePath(PlaneGlobe.meridian(longitude: 0)).cgPath.boundingBoxOfPath
        XCTAssertEqual(meridian.minY, 200, accuracy: 0.5)
        XCTAssertEqual(meridian.maxY, 400, accuracy: 0.5)
    }

    func testArcsSampleTheGreatCircleUpToTheRequestedFraction() {
        let start = PlaneVector(latitude: 0, longitude: 0)
        let end = PlaneVector(latitude: 0, longitude: 90)

        let full = PlaneGlobe.arc(from: start, to: end)
        XCTAssertEqual(full.first, start)
        XCTAssertEqual(full.last?.longitude ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(full.count, 46)
        let half = PlaneGlobe.arc(from: start, to: end, fraction: 0.5)
        XCTAssertEqual(half.last?.longitude ?? 0, 45, accuracy: 1e-9)
        XCTAssertEqual(PlaneGlobe.arc(from: start, to: end, fraction: .nan).count, 2)
        XCTAssertEqual(PlaneGlobe.parallel(latitude: 30).count, 91)
        XCTAssertEqual(PlaneGlobe.meridian(longitude: 30).count, 46)
    }

    func testDraggingSpinsTheCameraAgainstTheFingerAndClampsNearThePoles() {
        let camera = PlaneCamera(latitude: 10, longitude: 170)

        let dragged = camera.dragged(by: CGSize(width: -100 * CGFloat.pi / 9, height: 100 * CGFloat.pi / 36), radius: 100)
        XCTAssertEqual(dragged.latitude, 15, accuracy: 1e-9)
        XCTAssertEqual(dragged.longitude, -170, accuracy: 1e-9)
        XCTAssertEqual(camera.dragged(by: CGSize(width: 0, height: 10_000), radius: 100).latitude, PlaneCamera.maximumLatitude)
        XCTAssertEqual(camera.dragged(by: CGSize(width: 0, height: -10_000), radius: 100).latitude, -PlaneCamera.maximumLatitude)
        XCTAssertEqual(camera.dragged(by: CGSize(width: 50, height: 50), radius: 0), camera)
        XCTAssertEqual(camera.dragged(by: CGSize(width: CGFloat.nan, height: 0), radius: 100), camera)
    }

    func testCameraHoldsAfterADragThenGlidesBackToThePlane() {
        let manual = PlaneCamera(latitude: 0, longitude: 0)
        let follow = PlaneCamera(latitude: 0, longitude: 60)

        XCTAssertEqual(PlaneCamera.returning(from: manual, to: follow, idle: 0), manual)
        XCTAssertEqual(PlaneCamera.returning(from: manual, to: follow, idle: PlaneCamera.idleDelay), manual)
        let halfway = PlaneCamera.returning(from: manual, to: follow, idle: PlaneCamera.idleDelay + PlaneCamera.returnDuration / 2)
        XCTAssertEqual(halfway?.longitude ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(halfway?.latitude ?? 1, 0, accuracy: 1e-9)
        let early = PlaneCamera.returning(from: manual, to: follow, idle: PlaneCamera.idleDelay + PlaneCamera.returnDuration * 0.1)
        XCTAssertLessThan(early?.longitude ?? 60, 6)
        XCTAssertNil(PlaneCamera.returning(from: manual, to: follow, idle: PlaneCamera.idleDelay + PlaneCamera.returnDuration))
        XCTAssertNil(PlaneCamera.returning(from: manual, to: follow, idle: .infinity))
        XCTAssertEqual(PlaneCamera.returning(from: manual, to: follow, idle: -5), manual)
        XCTAssertNil(PlaneCamera.returning(from: manual, to: follow, idle: PlaneCamera.idleDelay + 0.01, duration: 0))
        XCTAssertEqual(PlaneCamera(PlaneVector(latitude: 20, longitude: -30)).longitude, -30, accuracy: 1e-9)
        XCTAssertEqual(PlaneCamera.idle, PlaneCamera(latitude: 25, longitude: 15))
    }
}
