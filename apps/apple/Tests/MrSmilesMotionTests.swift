import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class MrSmilesMotionTests: XCTestCase {
    private let seed = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let size = CGSize(width: 300, height: 500)

    func testSeedStartsAtCenterWithCalmDiagonalVelocity() {
        let motion = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        XCTAssertEqual(motion.position, CGPoint(x: 150, y: 250))
        let speed = hypot(motion.velocity.dx, motion.velocity.dy)
        XCTAssertGreaterThanOrEqual(speed, 48)
        XCTAssertLessThan(speed, 84)
        XCTAssertGreaterThanOrEqual(abs(motion.velocity.dx) / speed, sin(.pi / 8))
        XCTAssertGreaterThanOrEqual(abs(motion.velocity.dy) / speed, sin(.pi / 8))
        XCTAssertEqual(motion.elapsed, 0)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testSameRunSeedReproducesPositionVelocityAndWinks() {
        var first = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        var second = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        first.advance(to: 1_800)
        second.advance(to: 1_800)
        assertEqual(first, second)
        XCTAssertEqual(first.leftWinkUntil, second.leftWinkUntil)
        XCTAssertEqual(first.rightWinkUntil, second.rightWinkUntil)
    }

    func testDifferentRunSeedsChangeDirectionAndSpeed() {
        let first = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        let second = MrSmilesMotion(
            seed: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!,
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
        )
        XCTAssertNotEqual(first.velocity.dx / first.velocity.dy, second.velocity.dx / second.velocity.dy)
        XCTAssertNotEqual(hypot(first.velocity.dx, first.velocity.dy), hypot(second.velocity.dx, second.velocity.dy))
    }

    func testFreeMotionUsesElapsedActiveTime() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 10, dy: -20))
        motion.advance(to: 2)
        XCTAssertEqual(motion.position, CGPoint(x: 170, y: 210))
        motion.advance(to: 3)
        XCTAssertEqual(motion.position, CGPoint(x: 180, y: 190))
        XCTAssertEqual(motion.elapsed, 3)
    }

    func testUnchangedOrEarlierTimeDoesNotMoveOrRewind() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 10, dy: -20))
        motion.advance(to: 2)
        let paused = motion
        motion.advance(to: 2)
        assertEqual(motion, paused)
        motion.advance(to: 1)
        assertEqual(motion, paused)
        motion.advance(to: -1)
        assertEqual(motion, paused)
    }

    func testNonFiniteElapsedTimeIsIgnored() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 10, dy: -20))
        let initial = motion
        for time in [TimeInterval.nan, .infinity, -.infinity] {
            motion.advance(to: time)
            assertEqual(motion, initial)
        }
    }

    func testRightEdgeReflectsWhenCircleReachesScreenEdge() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 100, dy: 0))
        motion.advance(to: 1.29)
        XCTAssertEqual(motion.position.x, 279, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, 100)
        motion.advance(to: 1.3)
        XCTAssertEqual(motion.position.x + 20, size.width, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, -100)
        motion.advance(to: 1.4)
        XCTAssertEqual(motion.position.x, 270, accuracy: 0.000_001)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testLeftEdgeReflectsWithoutWinking() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: -100, dy: 0))
        motion.advance(to: 1.4)
        XCTAssertEqual(motion.position.x, 30, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, 100)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testTopEdgeWinksEyeOnIncomingHorizontalSide() {
        for horizontal in [CGFloat(-10), CGFloat(10)] {
            var motion = makeMotion(position: CGPoint(x: 150, y: 150), velocity: CGVector(dx: horizontal, dy: -100))
            motion.advance(to: 1.3)
            XCTAssertEqual(motion.position.y, 20, accuracy: 0.000_001)
            XCTAssertEqual(motion.velocity.dx, horizontal, accuracy: 0.000_001)
            XCTAssertEqual(motion.velocity.dy, 100)
            XCTAssertEqual(motion.leftEyeWinking, horizontal < 0)
            XCTAssertEqual(motion.rightEyeWinking, horizontal > 0)
        }
    }

    func testVerticalTopContactUsesRightEye() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 150), velocity: CGVector(dx: 0, dy: -100))
        motion.advance(to: 1.3)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertTrue(motion.rightEyeWinking)
    }

    func testBottomEdgeDoesNotWink() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 400), velocity: CGVector(dx: -10, dy: 100))
        motion.advance(to: 0.8)
        XCTAssertEqual(motion.position.y, 480, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, -100)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testUpperRightRoundedCornerWinksRightEyeAtPhysicalContact() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 60), velocity: CGVector(dx: 30, dy: -40))
        motion.advance(to: 0.79)
        XCTAssertEqual(motion.velocity.dx, 30)
        XCTAssertFalse(motion.rightEyeWinking)
        motion.advance(to: 0.8)
        XCTAssertEqual(motion.position.x, 264, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 28, accuracy: 0.000_001)
        XCTAssertEqual(hypot(motion.position.x - 240, motion.position.y - 60) + 20, 60, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, -30, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 40, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertEqual(motion.rightWinkUntil, 1.8, accuracy: 0.000_001)
    }

    func testUpperLeftRoundedCornerWinksLeftEyeAtPhysicalContact() {
        var motion = makeMotion(position: CGPoint(x: 60, y: 60), velocity: CGVector(dx: -30, dy: -40))
        motion.advance(to: 0.8)
        XCTAssertEqual(motion.position.x, 36, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 28, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, 30, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 40, accuracy: 0.000_001)
        XCTAssertTrue(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testObliqueRoundedContactReflectsAboutActualNormal() {
        var motion = makeMotion(position: CGPoint(x: 244, y: 33), velocity: CGVector(dx: 40, dy: -10))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position.x, 264, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 28, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, 1.6, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 41.2, accuracy: 0.000_001)
        XCTAssertEqual(motion.angularVelocity, 0, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertFalse(motion.leftEyeWinking)
    }

    func testLowerRoundedCornersNeverWink() {
        for horizontal in [CGFloat(-1), CGFloat(1)] {
            var motion = makeMotion(
                position: CGPoint(x: horizontal < 0 ? 60 : 240, y: 440),
                velocity: CGVector(dx: horizontal * 30, dy: 40),
            )
            motion.advance(to: 0.8)
            XCTAssertEqual(motion.velocity.dx, horizontal * -30, accuracy: 0.000_001)
            XCTAssertEqual(motion.velocity.dy, -40, accuracy: 0.000_001)
            XCTAssertFalse(motion.leftEyeWinking)
            XCTAssertFalse(motion.rightEyeWinking)
        }
    }

    func testWinkLastsExactlyOneSecondOfActiveTime() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 60), velocity: CGVector(dx: 30, dy: -40))
        motion.advance(to: 0.8)
        XCTAssertTrue(motion.rightEyeWinking)
        motion.advance(to: 1.79)
        XCTAssertTrue(motion.rightEyeWinking)
        motion.advance(to: 1.8)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testLargeAdvanceExpiresOldWinksUsingActualCollisionTime() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 60), velocity: CGVector(dx: 30, dy: -40))
        motion.advance(to: 2)
        XCTAssertEqual(motion.rightWinkUntil, 1.8, accuracy: 0.000_001)
        XCTAssertFalse(motion.rightEyeWinking)
        XCTAssertEqual(motion.position.x, 228, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 76, accuracy: 0.000_001)
    }

    func testWinkDeadlinesRemainIndependentAcrossSuccessiveCorners() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 240, y: 60),
            velocity: CGVector(dx: 30, dy: -40),
        )
        motion.advance(to: 0.8)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: -500, dy: 0)))
        motion.advance(to: 1.3)
        XCTAssertTrue(motion.leftEyeWinking)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertNotEqual(motion.leftWinkUntil, motion.rightWinkUntil)
    }

    func testLargeAdvanceDoesNotTunnelAcrossMultipleWalls() {
        var motion = MrSmilesMotion(
            size: CGSize(width: 100, height: 100),
            faceRadius: 10,
            screenCornerRadius: 0,
            position: CGPoint(x: 50, y: 50),
            velocity: CGVector(dx: 230, dy: 0),
        )
        motion.advance(to: 2)
        XCTAssertEqual(motion.position.x, 30, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 50)
        XCTAssertEqual(motion.velocity.dx, 230)
    }

    func testOneLargeStepMatchesManySmallStepsAcrossRoundedCorners() {
        var large = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 80)
        var small = large
        large.advance(to: 300)
        for frame in 1...18_000 {
            small.advance(to: Double(frame) / 60)
        }
        assertEqual(large, small, accuracy: 0.000_01)
        XCTAssertEqual(large.leftWinkUntil, small.leftWinkUntil, accuracy: 0.000_01)
        XCTAssertEqual(large.rightWinkUntil, small.rightWinkUntil, accuracy: 0.000_01)
    }

    func testTwoHourReplayExactlyMatchesUnevenFrameTiming() {
        var replay = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 80)
        var live = replay
        replay.advance(to: 7_200)
        for frame in 1...10_000 {
            let time = Double(frame) * 0.72 - Double(frame % 3) * 0.01
            live.advance(to: time)
        }
        live.advance(to: 7_200)
        assertEqual(replay, live, accuracy: 0)
        XCTAssertEqual(replay.leftWinkUntil, live.leftWinkUntil)
        XCTAssertEqual(replay.rightWinkUntil, live.rightWinkUntil)
    }

    func testLongMotionKeepsCircleInsideRoundedScreenAtAStableNonzeroSpeed() {
        var motion = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        let initialSpeed = hypot(motion.velocity.dx, motion.velocity.dy)
        for frame in 1...5_000 {
            motion.advance(to: Double(frame) / 5)
            XCTAssertGreaterThanOrEqual(motion.position.x, 20 - 0.000_001)
            XCTAssertLessThanOrEqual(motion.position.x, 280 + 0.000_001)
            XCTAssertGreaterThanOrEqual(motion.position.y, 20 - 0.000_001)
            XCTAssertLessThanOrEqual(motion.position.y, 480 + 0.000_001)
            let x = min(240, max(60, motion.position.x))
            let y = min(440, max(60, motion.position.y))
            XCTAssertLessThanOrEqual(hypot(motion.position.x - x, motion.position.y - y), 40 + 0.000_001)
            let speed = hypot(motion.velocity.dx, motion.velocity.dy)
            XCTAssertGreaterThan(speed, 0)
            XCTAssertLessThanOrEqual(speed, initialSpeed + 0.000_001)
        }
    }

    func testAmbientReboundsDoNotCollapseIntoHorizontalMotion() {
        var motion = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        var minimumY = motion.position.y
        var maximumY = motion.position.y
        for second in 1...300 {
            motion.advance(to: Double(second))
            minimumY = min(minimumY, motion.position.y)
            maximumY = max(maximumY, motion.position.y)
            let speed = hypot(motion.velocity.dx, motion.velocity.dy)
            XCTAssertGreaterThanOrEqual(abs(motion.velocity.dy), speed * 0.23)
        }
        XCTAssertGreaterThan(maximumY - minimumY, 300)
    }

    func testFastAmbientMotionSettlesTowardCruisingSpeedWithoutStopping() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 500, dy: 0),
            livelyRebounds: true,
        )
        motion.advance(to: 120)
        let speed = hypot(motion.velocity.dx, motion.velocity.dy)
        XCTAssertGreaterThanOrEqual(speed, 72)
        XCTAssertLessThanOrEqual(speed, 84)
    }

    func testFaceLargerThanScreenCornerUsesSquareInsetBounds() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 50,
            screenCornerRadius: 30,
            position: CGPoint(x: 240, y: 60),
            velocity: CGVector(dx: 10, dy: -10),
        )
        motion.advance(to: 1)
        XCTAssertEqual(motion.position, CGPoint(x: 250, y: 50))
        XCTAssertLessThan(motion.velocity.dx, 0)
        XCTAssertGreaterThan(motion.velocity.dy, 0)
        XCTAssertTrue(motion.rightEyeWinking)
    }

    func testSimultaneousSquareCornerContactReflectsBothComponents() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 0,
            position: CGPoint(x: 230, y: 120),
            velocity: CGVector(dx: 50, dy: -100),
        )
        motion.advance(to: 1)
        XCTAssertEqual(motion.position, CGPoint(x: 280, y: 20))
        XCTAssertEqual(motion.velocity.dx, -50, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 100, accuracy: 0.000_001)
    }

    func testStartingOnBoundaryMovingOutwardReflectsImmediately() {
        var motion = makeMotion(position: CGPoint(x: 280, y: 250), velocity: CGVector(dx: 100, dy: 0))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position.x, 230)
        XCTAssertEqual(motion.velocity.dx, -100)
    }

    func testStartingOnBoundaryMovingInwardDoesNotReflectAgain() {
        var motion = makeMotion(position: CGPoint(x: 280, y: 250), velocity: CGVector(dx: -100, dy: 0))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position.x, 230)
        XCTAssertEqual(motion.velocity.dx, -100)
    }

    func testStartingOnRoundedBoundaryMovingOutwardReflectsImmediately() {
        var motion = makeMotion(position: CGPoint(x: 264, y: 28), velocity: CGVector(dx: 30, dy: -40))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position.x, 249, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 48, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
    }

    func testStartingOnRoundedBoundaryMovingInwardDoesNotReflectAgain() {
        var motion = makeMotion(position: CGPoint(x: 264, y: 28), velocity: CGVector(dx: -30, dy: 40))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position.x, 249, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 48, accuracy: 0.000_001)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testCornerAndStraightEdgeSeamReflectsOnce() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 70), velocity: CGVector(dx: 0, dy: -50))
        motion.advance(to: 1)
        XCTAssertEqual(motion.position, CGPoint(x: 240, y: 20))
        XCTAssertEqual(motion.velocity.dy, 50, accuracy: 0.000_001)
        motion.advance(to: 1.5)
        XCTAssertEqual(motion.position.y, 45, accuracy: 0.000_001)
    }

    func testOutOfBoundsStartingPointIsConfinedToRoundedBoundary() {
        let motion = makeMotion(position: CGPoint(x: 500, y: -100), velocity: CGVector(dx: 0, dy: 0))
        XCTAssertEqual(motion.position.x, 240 + 40 / sqrt(2), accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 60 - 40 / sqrt(2), accuracy: 0.000_001)
    }

    func testStationaryFaceDoesNotMoveOrWink() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        motion.advance(to: 1_000)
        XCTAssertEqual(motion.position, CGPoint(x: 150, y: 250))
        XCTAssertEqual(motion.elapsed, 1_000)
        XCTAssertFalse(motion.leftEyeWinking)
        XCTAssertFalse(motion.rightEyeWinking)
    }

    func testOversizedFaceStopsOnFilledAxes() {
        var motion = MrSmilesMotion(
            size: CGSize(width: 100, height: 100),
            faceRadius: 200,
            screenCornerRadius: 400,
            position: CGPoint(x: -1, y: 200),
            velocity: CGVector(dx: 40, dy: 70),
        )
        motion.advance(to: 1_000)
        XCTAssertEqual(motion.position, CGPoint(x: 50, y: 50))
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, 0)
    }

    func testFaceFillingOneAxisStillBouncesOnOtherAxis() {
        var motion = MrSmilesMotion(
            size: CGSize(width: 100, height: 300),
            faceRadius: 50,
            screenCornerRadius: 50,
            position: CGPoint(x: 50, y: 150),
            velocity: CGVector(dx: 40, dy: 100),
        )
        motion.advance(to: 2)
        XCTAssertEqual(motion.position, CGPoint(x: 50, y: 150))
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, -100)
    }

    func testInvalidGeometryAndVelocityProduceFiniteStationaryState() {
        var motion = MrSmilesMotion(
            size: CGSize(width: -CGFloat.infinity, height: CGFloat.nan),
            faceRadius: .infinity,
            screenCornerRadius: .nan,
            position: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
            velocity: CGVector(dx: CGFloat.infinity, dy: CGFloat.nan),
        )
        motion.advance(to: 10)
        XCTAssertEqual(motion.position, CGPoint.zero)
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, 0)
    }

    func testNegativeRadiiBehaveAsZero() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: -20,
            screenCornerRadius: -50,
            position: CGPoint(x: 290, y: 250),
            velocity: CGVector(dx: 10, dy: 0),
        )
        motion.advance(to: 1)
        XCTAssertEqual(motion.position.x, 300)
        XCTAssertEqual(motion.velocity.dx, -10)
    }

    func testHeadOnImpactWithoutInitialSpinDoesNotInventRotation() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 100, dy: 0))
        motion.advance(to: 2)
        XCTAssertEqual(motion.velocity.dx, -100)
        XCTAssertEqual(motion.velocity.dy, 0)
        XCTAssertEqual(motion.angularVelocity, 0)
        XCTAssertEqual(motion.rotation, 0)
    }

    func testObliqueImpactPreservesTangentialMotion() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 100, dy: 30))
        motion.advance(to: 1.3)
        XCTAssertEqual(motion.velocity.dx, -100, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 30, accuracy: 0.000_001)
        XCTAssertEqual(motion.angularVelocity, 0, accuracy: 0.000_001)
    }

    func testGlancingImpactDoesNotLoseTangentialSpeed() {
        var motion = makeMotion(position: CGPoint(x: 275, y: 250), velocity: CGVector(dx: 10, dy: 100))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.velocity.dx, -10, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 100, accuracy: 0.000_001)
        XCTAssertEqual(motion.angularVelocity, 0, accuracy: 0.000_001)
    }

    func testExistingSpinDoesNotDrainTranslationalMotion() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 100, dy: 30),
            angularVelocity: -3,
        )
        motion.advance(to: 1.3)
        XCTAssertEqual(motion.velocity.dx, -100, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 30, accuracy: 0.000_001)
        XCTAssertEqual(motion.angularVelocity, -3, accuracy: 0.000_001)
    }

    func testContactQuadrantUsesRotatedFaceCoordinates() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 100, dy: 0),
            rotation: .pi / 4,
        )
        motion.advance(to: 1.3)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertFalse(motion.leftEyeWinking)
        var left = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 100, dy: 0),
            rotation: .pi * 3 / 4,
        )
        left.advance(to: 1.3)
        XCTAssertTrue(left.leftEyeWinking)
        XCTAssertFalse(left.rightEyeWinking)
    }

    func testContactUsesRotationReachedAtImpact() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 230, y: 250),
            velocity: CGVector(dx: 100, dy: 0),
            angularVelocity: .pi / 2,
        )
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.rotation, .pi / 4, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertFalse(motion.leftEyeWinking)
    }

    func testZeroRadiusReflectsWithoutUndefinedRotationalImpulse() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 0,
            screenCornerRadius: 60,
            position: CGPoint(x: 250, y: 250),
            velocity: CGVector(dx: 100, dy: 30),
            angularVelocity: 2,
        )
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.velocity.dx, -100)
        XCTAssertEqual(motion.velocity.dy, 30)
        XCTAssertEqual(motion.angularVelocity, 0)
        XCTAssertEqual(motion.rotation, 0)
    }

    func testFlickReplacesVelocityInScreenPointsPerSecond() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 10, dy: 20))
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: -60, dy: 80)))
        XCTAssertEqual(motion.velocity.dx, -60)
        XCTAssertEqual(motion.velocity.dy, 80)
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position, CGPoint(x: 120, y: 290))
    }

    func testFasterFlickTravelsFartherInSameTime() {
        var slow = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        var fast = slow
        XCTAssertTrue(slow.flick(velocity: CGVector(dx: 30, dy: -40)))
        XCTAssertTrue(fast.flick(velocity: CGVector(dx: 90, dy: -120)))
        slow.advance(to: 0.5)
        fast.advance(to: 0.5)
        XCTAssertEqual(fast.position.x - 150, (slow.position.x - 150) * 3)
        XCTAssertEqual(fast.position.y - 250, (slow.position.y - 250) * 3)
    }

    func testFlickReanchorsAtCurrentElapsedWithoutMovingTheFace() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 10, dy: 20))
        motion.advance(to: 3)
        let position = motion.position
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: -100, dy: 0)))
        XCTAssertEqual(motion.position, position)
        XCTAssertEqual(motion.elapsed, 3)
        motion.advance(to: 3)
        XCTAssertEqual(motion.position, position)
        motion.advance(to: 3.5)
        XCTAssertEqual(motion.position, CGPoint(x: position.x - 50, y: position.y))
    }

    func testRepeatedFlicksEachStartAtTheCurrentPositionAndTime() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        motion.flick(velocity: CGVector(dx: 100, dy: 0))
        motion.advance(to: 0.5)
        XCTAssertEqual(motion.position, CGPoint(x: 200, y: 250))
        motion.flick(velocity: CGVector(dx: 0, dy: -100))
        motion.advance(to: 1)
        XCTAssertEqual(motion.position, CGPoint(x: 200, y: 200))
        motion.flick(velocity: CGVector(dx: -60, dy: 80))
        motion.advance(to: 1.5)
        XCTAssertEqual(motion.position, CGPoint(x: 170, y: 240))
    }

    func testFlickPreservesRotationSpinAndExistingWinks() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 100, dy: 30),
            rotation: .pi / 4,
            angularVelocity: 0.1,
        )
        motion.advance(to: 1.4)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertNotEqual(motion.angularVelocity, 0)
        let before = motion
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: -20, dy: 0)))
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.angularVelocity, before.angularVelocity)
        XCTAssertEqual(motion.leftWinkUntil, before.leftWinkUntil)
        XCTAssertEqual(motion.rightWinkUntil, before.rightWinkUntil)
        XCTAssertEqual(motion.elapsed, before.elapsed)
        motion.advance(to: 1.6)
        XCTAssertEqual(motion.rotation, before.rotation + before.angularVelocity * 0.2, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
    }

    func testInvalidOrTinyFlicksLeaveStateAndFutureTrajectoryUnchanged() {
        var motion = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        motion.advance(to: 7)
        var baseline = motion
        let invalid = [
            CGVector(dx: 0, dy: 0),
            CGVector(dx: 19.9, dy: 0),
            CGVector(dx: -10, dy: 10),
            CGVector(dx: CGFloat.nan, dy: 100),
            CGVector(dx: 100, dy: CGFloat.nan),
            CGVector(dx: CGFloat.infinity, dy: 100),
            CGVector(dx: 100, dy: -CGFloat.infinity),
        ]
        for velocity in invalid {
            XCTAssertFalse(motion.flick(velocity: velocity))
            assertEqual(motion, baseline, accuracy: 0)
            XCTAssertEqual(motion.leftWinkUntil, baseline.leftWinkUntil)
            XCTAssertEqual(motion.rightWinkUntil, baseline.rightWinkUntil)
        }
        motion.advance(to: 300)
        baseline.advance(to: 300)
        assertEqual(motion, baseline, accuracy: 0)
    }

    func testFlickAcceptsTheMinimumSpeed() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: 12, dy: -16)))
        XCTAssertEqual(motion.velocity.dx, 12)
        XCTAssertEqual(motion.velocity.dy, -16)
    }

    func testFlickCapsSpeedWithoutChangingDirection() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: -3_000, dy: 4_000)))
        XCTAssertEqual(motion.velocity.dx, -300, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 400, accuracy: 0.000_001)
        XCTAssertEqual(hypot(motion.velocity.dx, motion.velocity.dy), 500, accuracy: 0.000_001)
    }

    func testFlickCapsExtremelyLargeFiniteVelocityWithoutOverflow() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: CGFloat.greatestFiniteMagnitude, dy: -CGFloat.greatestFiniteMagnitude)))
        XCTAssertEqual(motion.velocity.dx, 500 / sqrt(2), accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, -500 / sqrt(2), accuracy: 0.000_001)
        motion.advance(to: 10)
        XCTAssertTrue(motion.position.x.isFinite)
        XCTAssertTrue(motion.position.y.isFinite)
        XCTAssertTrue(motion.rotation.isFinite)
    }

    func testHighSpeedFlickStillReflectsAtCircleEdge() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 0, dy: 0))
        motion.flick(velocity: CGVector(dx: 10_000, dy: 0))
        motion.advance(to: 0.4)
        XCTAssertEqual(motion.position.x, 210, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 250)
        XCTAssertEqual(motion.velocity.dx, -500)
    }

    func testHighSpeedFlickStaysInsideRoundedCornersAcrossLargeSteps() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 60), velocity: CGVector(dx: 0, dy: 0))
        motion.flick(velocity: CGVector(dx: 720, dy: -960))
        let initialEnergy = energy(motion)
        motion.advance(to: 0.08)
        XCTAssertEqual(motion.position.x, 264, accuracy: 0.000_001)
        XCTAssertEqual(motion.position.y, 28, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dx, -300, accuracy: 0.000_001)
        XCTAssertEqual(motion.velocity.dy, 400, accuracy: 0.000_001)
        XCTAssertTrue(motion.rightEyeWinking)
        for step in 1...100 {
            motion.advance(to: Double(step) * 3)
            let x = min(240, max(60, motion.position.x))
            let y = min(440, max(60, motion.position.y))
            XCTAssertLessThanOrEqual(hypot(motion.position.x - x, motion.position.y - y), 40 + 0.000_001)
            XCTAssertLessThanOrEqual(energy(motion), initialEnergy + 0.000_001)
        }
    }

    func testFlickOnlyUsesAxesWithSpaceForMotion() {
        var motion = MrSmilesMotion(
            size: CGSize(width: 100, height: 300),
            faceRadius: 50,
            screenCornerRadius: 50,
            position: CGPoint(x: 50, y: 150),
            velocity: CGVector(dx: 0, dy: 0),
        )
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: 500, dy: 100)))
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, 100)
        let before = motion
        XCTAssertFalse(motion.flick(velocity: CGVector(dx: 500, dy: 10)))
        assertEqual(motion, before, accuracy: 0)
        motion.advance(to: 2)
        XCTAssertEqual(motion.position, CGPoint(x: 50, y: 150))
    }

    func testFlickRejectsMotionWhenFaceFillsBothAxes() {
        var motion = MrSmilesMotion(
            size: CGSize(width: 100, height: 100),
            faceRadius: 50,
            screenCornerRadius: 50,
            position: CGPoint(x: 50, y: 50),
            velocity: CGVector(dx: 0, dy: 0),
        )
        let before = motion
        XCTAssertFalse(motion.flick(velocity: CGVector(dx: 500, dy: 100)))
        assertEqual(motion, before, accuracy: 0)
    }

    func testFlickAndStopReplayExactlyMatchLiveFrameTiming() {
        var replay = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 80)
        var live = replay
        let impulses: [(TimeInterval, CGVector?)] = [
            (2.75, CGVector(dx: -300, dy: 200)),
            (4.2, nil),
            (7.12, CGVector(dx: 100, dy: -400)),
            (13.4, nil),
            (18.31, CGVector(dx: 2_000, dy: 1_000)),
        ]
        for (time, velocity) in impulses {
            replay.advance(to: time)
            if let velocity {
                replay.flick(velocity: velocity)
            } else {
                replay.stop()
            }
            let start = live.elapsed
            for frame in 1..<100 {
                live.advance(to: start + (time - start) * Double(frame) / 100)
            }
            live.advance(to: time)
            if let velocity {
                live.flick(velocity: velocity)
            } else {
                live.stop()
            }
        }
        replay.advance(to: 7_200)
        for frame in 1..<10_000 {
            live.advance(to: 18.31 + (7_200 - 18.31) * Double(frame) / 10_000)
        }
        live.advance(to: 7_200)
        assertEqual(replay, live, accuracy: 0)
        XCTAssertEqual(replay.leftWinkUntil, live.leftWinkUntil)
        XCTAssertEqual(replay.rightWinkUntil, live.rightWinkUntil)
    }

    func testStopReanchorsFreeFlightWithoutMovingOrRotating() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 10, dy: -20),
            rotation: 0.4,
            angularVelocity: 0.5,
        )
        motion.advance(to: 2)
        let before = motion
        motion.stop()
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.elapsed, before.elapsed)
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, 0)
        XCTAssertEqual(motion.angularVelocity, 0)
        motion.advance(to: 100)
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.elapsed, 100)
    }

    func testStopAfterImpactPreservesWinksAndStopsSpin() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 100, dy: 30),
            rotation: .pi / 4,
            angularVelocity: 0.1,
        )
        motion.advance(to: 1.4)
        let before = motion
        XCTAssertTrue(before.rightEyeWinking)
        XCTAssertNotEqual(before.angularVelocity, 0)
        motion.stop()
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.leftWinkUntil, before.leftWinkUntil)
        XCTAssertEqual(motion.rightWinkUntil, before.rightWinkUntil)
        XCTAssertEqual(motion.angularVelocity, 0)
        motion.advance(to: 1.5)
        XCTAssertTrue(motion.rightEyeWinking)
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
        motion.advance(to: 2.4)
        XCTAssertFalse(motion.rightEyeWinking)
        XCTAssertEqual(motion.position, before.position)
        XCTAssertEqual(motion.rotation, before.rotation)
    }

    func testStopAtExactBoundaryRemainsStill() {
        var motion = makeMotion(position: CGPoint(x: 240, y: 60), velocity: CGVector(dx: 30, dy: -40))
        motion.advance(to: 0.8)
        motion.stop()
        let stopped = motion
        motion.advance(to: 30)
        XCTAssertEqual(motion.position, stopped.position)
        XCTAssertEqual(motion.rotation, stopped.rotation)
        XCTAssertEqual(motion.velocity.dx, 0)
        XCTAssertEqual(motion.velocity.dy, 0)
        XCTAssertEqual(motion.angularVelocity, 0)
    }

    func testRepeatedStopsAtUnchangedElapsedTimeAreIdempotent() {
        var motion = MrSmilesMotion(seed: seed, size: size, faceRadius: 20, screenCornerRadius: 60)
        motion.stop()
        let stopped = motion
        motion.advance(to: 0)
        motion.stop()
        assertEqual(motion, stopped, accuracy: 0)
        XCTAssertEqual(motion.elapsed, 0)
        XCTAssertEqual(motion.position, CGPoint(x: 150, y: 250))
    }

    func testFlickAfterStopResumesFromStoppedPositionWithNoSpin() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 10, dy: 20),
            rotation: 0.3,
            angularVelocity: 0.5,
        )
        motion.advance(to: 1)
        motion.stop()
        let stopped = motion
        motion.advance(to: 50)
        XCTAssertTrue(motion.flick(velocity: CGVector(dx: 100, dy: -50)))
        XCTAssertEqual(motion.position, stopped.position)
        XCTAssertEqual(motion.angularVelocity, 0)
        motion.advance(to: 50.5)
        XCTAssertEqual(motion.position, CGPoint(x: stopped.position.x + 50, y: stopped.position.y - 25))
        XCTAssertEqual(motion.rotation, stopped.rotation)
        XCTAssertEqual(motion.angularVelocity, 0)
    }

    func testMoveFollowsAValidTargetAndStopsAtThatLocation() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 250),
            velocity: CGVector(dx: 90, dy: -40),
            rotation: 0.3,
            angularVelocity: 0.5,
        )
        motion.advance(to: 2)
        let before = motion
        let target = CGPoint(x: 190, y: 300)

        XCTAssertTrue(motion.move(to: target))
        XCTAssertEqual(motion.position, target)
        XCTAssertEqual(motion.elapsed, before.elapsed)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.velocity, .zero)
        XCTAssertEqual(motion.angularVelocity, 0)
        motion.advance(to: 100)
        XCTAssertEqual(motion.position, target)
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.elapsed, 100)
    }

    func testMoveConfinesTheCircleToTheRoundedScreen() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 90, dy: -40))

        XCTAssertTrue(motion.move(to: CGPoint(x: -500, y: -500)))
        XCTAssertGreaterThanOrEqual(motion.position.x, 20)
        XCTAssertGreaterThanOrEqual(motion.position.y, 20)
        XCTAssertEqual(hypot(motion.position.x - 60, motion.position.y - 60), 40, accuracy: 0.000_001)

        XCTAssertTrue(motion.move(to: CGPoint(x: 1_000, y: 1_000)))
        XCTAssertLessThanOrEqual(motion.position.x, 280)
        XCTAssertLessThanOrEqual(motion.position.y, 480)
        XCTAssertEqual(hypot(motion.position.x - 240, motion.position.y - 440), 40, accuracy: 0.000_001)
    }

    func testMoveRejectsNonfiniteTargetsWithoutChangingState() {
        var motion = makeMotion(position: CGPoint(x: 150, y: 250), velocity: CGVector(dx: 90, dy: -40))
        motion.advance(to: 2)
        let before = motion

        XCTAssertFalse(motion.move(to: CGPoint(x: CGFloat.nan, y: 20)))
        assertEqual(motion, before, accuracy: 0)
        XCTAssertFalse(motion.move(to: CGPoint(x: 20, y: CGFloat.infinity)))
        assertEqual(motion, before, accuracy: 0)
    }

    func testMovePreservesOrientationAndWinksWhileClearingSpin() {
        var motion = MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: CGPoint(x: 150, y: 150),
            velocity: CGVector(dx: 10, dy: -100),
            rotation: -1,
            angularVelocity: 0.2,
        )
        motion.advance(to: 1.3)
        let before = motion
        XCTAssertTrue(before.rightEyeWinking)
        XCTAssertTrue(motion.move(to: CGPoint(x: 190, y: 300)))
        XCTAssertEqual(motion.rotation, before.rotation)
        XCTAssertEqual(motion.leftWinkUntil, before.leftWinkUntil)
        XCTAssertEqual(motion.rightWinkUntil, before.rightWinkUntil)
        XCTAssertEqual(motion.angularVelocity, 0)
        XCTAssertEqual(motion.velocity, .zero)
    }

    private func energy(_ motion: MrSmilesMotion) -> Double {
        (motion.velocity.dx * motion.velocity.dx + motion.velocity.dy * motion.velocity.dy) / 2 +
            100 * motion.angularVelocity * motion.angularVelocity
    }

    private func makeMotion(position: CGPoint, velocity: CGVector) -> MrSmilesMotion {
        MrSmilesMotion(
            size: size,
            faceRadius: 20,
            screenCornerRadius: 60,
            position: position,
            velocity: velocity,
        )
    }

    private func assertEqual(
        _ first: MrSmilesMotion,
        _ second: MrSmilesMotion,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(first.position.x, second.position.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.position.y, second.position.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.velocity.dx, second.velocity.dx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.velocity.dy, second.velocity.dy, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.elapsed, second.elapsed, file: file, line: line)
        XCTAssertEqual(first.rotation, second.rotation, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.angularVelocity, second.angularVelocity, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(first.leftEyeWinking, second.leftEyeWinking, file: file, line: line)
        XCTAssertEqual(first.rightEyeWinking, second.rightEyeWinking, file: file, line: line)
    }
}
