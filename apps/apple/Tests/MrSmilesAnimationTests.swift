import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class MrSmilesAnimationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)
    private let size = CGSize(width: 390, height: 844)
    private let faceRadius: CGFloat = 52
    private let screenCornerRadius: CGFloat = 55

    func testReadyFaceStaysAtTheCenterAsWallTimePasses() throws {
        let run = FocusRun(createdAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: snapshot, at: date)
        let initial = try XCTUnwrap(animation.motion)
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1_000))
        let later = try XCTUnwrap(animation.motion)

        XCTAssertEqual(initial.position, CGPoint(x: size.width / 2, y: size.height / 2))
        XCTAssertEqual(later.position, initial.position)
        XCTAssertEqual(later.rotation, initial.rotation)
        XCTAssertEqual(later.elapsed, 0)
    }

    func testRunningFramesAdvanceBetweenSnapshotSamples() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: snapshot, at: date)
        let initial = try XCTUnwrap(animation.motion)
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(0.25))
        let frame = try XCTUnwrap(animation.motion)

        XCTAssertEqual(frame.elapsed, 0.25, accuracy: 0.0001)
        XCTAssertEqual(frame.position.x, initial.position.x + initial.velocity.dx * 0.25, accuracy: 0.0001)
        XCTAssertEqual(frame.position.y, initial.position.y + initial.velocity.dy * 0.25, accuracy: 0.0001)
    }

    func testSnapshotRefreshDoesNotDoubleCountTimeAlreadyAnimated() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: TimerSnapshot(run: run, at: date), at: date.addingTimeInterval(20))
        let previous = try XCTUnwrap(animation.motion)
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(20)),
            at: date.addingTimeInterval(20),
        )
        let refreshed = try XCTUnwrap(animation.motion)

        XCTAssertEqual(refreshed.elapsed, 20)
        XCTAssertEqual(refreshed.position, previous.position)
        XCTAssertEqual(refreshed.velocity, previous.velocity)
        XCTAssertEqual(refreshed.rotation, previous.rotation)
        XCTAssertEqual(refreshed.angularVelocity, previous.angularVelocity)
    }

    func testFrameBeforeSnapshotDateDoesNotSubtractSavedProgress() throws {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 12, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(3))
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: snapshot, at: date)

        XCTAssertEqual(try XCTUnwrap(animation.motion).elapsed, 15)
    }

    func testPausedFaceFreezesAndResumeContinuesTheSamePath() throws {
        var run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 20)
        let paused = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: paused, at: date)
        let initial = try XCTUnwrap(animation.motion)
        update(&animation, snapshot: paused, at: date.addingTimeInterval(900))
        let frozen = try XCTUnwrap(animation.motion)

        XCTAssertEqual(frozen.elapsed, 20)
        XCTAssertEqual(frozen.position, initial.position)
        XCTAssertEqual(frozen.velocity, initial.velocity)
        XCTAssertEqual(frozen.rotation, initial.rotation)
        XCTAssertEqual(frozen.angularVelocity, initial.angularVelocity)

        run.resumedAt = date.addingTimeInterval(900)
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(900)),
            at: date.addingTimeInterval(901.5),
        )
        var expected = initial
        expected.advance(to: 21.5)

        assertMotion(animation, matches: expected)
    }

    func testPausingCorrectsAFrameThatExtrapolatedPastTheSavedPauseTime() throws {
        var run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: TimerSnapshot(run: run, at: date), at: date.addingTimeInterval(20.01))
        run.progressSeconds = 20
        run.resumedAt = nil
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(20)),
            at: date.addingTimeInterval(20.02),
        )
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 20)

        assertMotion(animation, matches: expected)
    }

    func testRunningExtrapolationStopsAtTheGoalBeforeACompletionSnapshotArrives() throws {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(60))
        let completed = try XCTUnwrap(animation.motion)
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1_000))
        let later = try XCTUnwrap(animation.motion)

        XCTAssertEqual(later.elapsed, 60)
        XCTAssertEqual(later.position, completed.position)
        XCTAssertEqual(later.velocity, completed.velocity)
        XCTAssertEqual(later.rotation, completed.rotation)
        XCTAssertEqual(later.angularVelocity, completed.angularVelocity)
    }

    func testCompletedSnapshotRestoresTheFinalPositionAndStaysStill() throws {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(60))
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1_000))
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 60)

        assertMotion(animation, matches: expected)
    }

    func testANewRunReturnsToCenterWithItsOwnSeed() throws {
        let first = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let second = FocusRun(createdAt: date)
        var animation = MrSmilesAnimation()

        update(&animation, snapshot: TimerSnapshot(run: first, at: date), at: date.addingTimeInterval(20))
        update(&animation, snapshot: TimerSnapshot(run: second, at: date), at: date)

        assertMotion(animation, matches: makeMotion(seed: second.id))
    }

    func testGeometryChangesRebuildTheSameRunAtItsCurrentElapsedTime() throws {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 20)
        let snapshot = TimerSnapshot(run: run, at: date)
        let layouts: [(CGSize, CGFloat, CGFloat)] = [
            (CGSize(width: 844, height: 390), 52, 55),
            (CGSize(width: 844, height: 390), 65, 55),
            (CGSize(width: 844, height: 390), 65, 80),
        ]
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)

        for (size, faceRadius, screenCornerRadius) in layouts {
            animation.update(
                snapshot: snapshot,
                at: date,
                size: size,
                faceRadius: faceRadius,
                screenCornerRadius: screenCornerRadius,
            )
            var expected = MrSmilesMotion(
                seed: run.id,
                size: size,
                faceRadius: faceRadius,
                screenCornerRadius: screenCornerRadius,
            )
            expected.advance(to: 20)

            assertMotion(animation, matches: expected)
        }
    }

    func testNonfiniteFrameDateDoesNotDamageSnapshotProgress() throws {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 20, resumedAt: date)
        var animation = MrSmilesAnimation()

        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date),
            at: Date(timeIntervalSinceReferenceDate: .infinity),
        )

        XCTAssertEqual(try XCTUnwrap(animation.motion).elapsed, 20)
    }

    func testRunningFlickChangesVelocityAndSurvivesTheNextFrameAndSnapshot() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let flickDate = date.addingTimeInterval(0.25)
        let velocity = CGVector(dx: 240, dy: -80)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: flickDate)
        let before = try XCTUnwrap(animation.motion)

        XCTAssertTrue(animation.flick(velocity: velocity, snapshot: snapshot, at: flickDate))
        let flicked = try XCTUnwrap(animation.motion)
        XCTAssertEqual(flicked.velocity, velocity)
        XCTAssertEqual(flicked.position, before.position)
        XCTAssertEqual(flicked.rotation, before.rotation)
        XCTAssertEqual(flicked.angularVelocity, before.angularVelocity)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(0.5))
        var expected = flicked
        expected.advance(to: 0.5)
        assertMotion(animation, matches: expected)

        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(1)),
            at: date.addingTimeInterval(1),
        )
        expected.advance(to: 1)
        assertMotion(animation, matches: expected)
    }

    func testPausedAndResumedRunPreservesTheFlickedTrajectory() throws {
        var run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let running = TimerSnapshot(run: run, at: date)
        let flickDate = date.addingTimeInterval(20)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: running, at: flickDate)
        XCTAssertTrue(animation.flick(velocity: CGVector(dx: 160, dy: 200), snapshot: running, at: flickDate))
        var expected = try XCTUnwrap(animation.motion)

        run.progressSeconds = 20
        run.resumedAt = nil
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: flickDate),
            at: date.addingTimeInterval(900),
        )
        assertMotion(animation, matches: expected)

        run.resumedAt = date.addingTimeInterval(900)
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(900)),
            at: date.addingTimeInterval(905),
        )
        expected.advance(to: 25)
        assertMotion(animation, matches: expected)
    }

    func testMultipleFlicksReplayInOrderWhenGeometryChanges() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let events: [(TimeInterval, CGVector)] = [
            (2, CGVector(dx: 200, dy: -150)),
            (4, CGVector(dx: -100, dy: 250)),
            (4, CGVector(dx: 2_400, dy: 1_800)),
        ]
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        for (elapsed, velocity) in events {
            XCTAssertTrue(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(elapsed)))
        }
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(80))

        let resized = CGSize(width: 844, height: 390)
        animation.update(
            snapshot: snapshot,
            at: date.addingTimeInterval(80),
            size: resized,
            faceRadius: 60,
            screenCornerRadius: 75,
        )
        var expected = MrSmilesMotion(seed: run.id, size: resized, faceRadius: 60, screenCornerRadius: 75)
        for (elapsed, velocity) in events {
            expected.advance(to: elapsed)
            XCTAssertTrue(expected.flick(velocity: velocity))
        }
        expected.advance(to: 80)
        assertMotion(animation, matches: expected)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(100))
        var originalLayout = makeMotion(seed: run.id)
        for (elapsed, velocity) in events {
            originalLayout.advance(to: elapsed)
            XCTAssertTrue(originalLayout.flick(velocity: velocity))
        }
        originalLayout.advance(to: 100)
        assertMotion(animation, matches: originalLayout)
    }

    func testStaleFrameBeforeFlickRetainsTheImpulseWhenTimeCatchesUp() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let velocity = CGVector(dx: 180, dy: -200)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        XCTAssertTrue(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(2)))

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1.99))
        var before = makeMotion(seed: run.id)
        before.advance(to: 1.99)
        assertMotion(animation, matches: before)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(2.1))
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 2)
        XCTAssertTrue(expected.flick(velocity: velocity))
        expected.advance(to: 2.1)
        assertMotion(animation, matches: expected)
    }

    func testPauseDiscardsInteractionsBeyondItsAuthoritativeSavedTime() {
        var run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let running = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: running, at: date)
        XCTAssertTrue(animation.flick(velocity: CGVector(dx: 180, dy: -200), snapshot: running, at: date.addingTimeInterval(2.01)))
        XCTAssertTrue(animation.stop(snapshot: running, at: date.addingTimeInterval(2.02)))

        run.progressSeconds = 2
        run.resumedAt = nil
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(2.02)),
            at: date.addingTimeInterval(2.02),
        )
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 2)
        assertMotion(animation, matches: expected)

        run.resumedAt = date.addingTimeInterval(900)
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(900)),
            at: date.addingTimeInterval(902),
        )
        expected.advance(to: 4)
        assertMotion(animation, matches: expected)
    }

    func testNewFlickAfterRewindReplacesFutureFlicks() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let replacement = CGVector(dx: -100, dy: 250)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        XCTAssertTrue(animation.flick(velocity: CGVector(dx: 180, dy: -200), snapshot: snapshot, at: date.addingTimeInterval(2)))
        XCTAssertTrue(animation.flick(velocity: replacement, snapshot: snapshot, at: date.addingTimeInterval(1.99)))

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(3))
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 1.99)
        XCTAssertTrue(expected.flick(velocity: replacement))
        expected.advance(to: 3)
        assertMotion(animation, matches: expected)
    }

    func testBackgroundCatchupContinuesFromTheLastFlickWithoutReapplyingIt() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        XCTAssertTrue(animation.flick(velocity: CGVector(dx: 320, dy: -150), snapshot: snapshot, at: date.addingTimeInterval(2)))
        var expected = try XCTUnwrap(animation.motion)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(10))
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1_000))
        expected.advance(to: 1_000)
        assertMotion(animation, matches: expected)
    }

    func testReadyPausedAndCompletedRunsRejectInteractions() throws {
        let runs = [
            FocusRun(createdAt: date),
            FocusRun(createdAt: date, startedAt: date, progressSeconds: 5),
            FocusRun(createdAt: date, startedAt: date, goalSeconds: 5, resumedAt: date),
        ]
        for run in runs {
            let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(10))
            var animation = MrSmilesAnimation()
            update(&animation, snapshot: snapshot, at: date.addingTimeInterval(10))
            let before = try XCTUnwrap(animation.motion)

            XCTAssertFalse(animation.flick(velocity: CGVector(dx: 240, dy: 100), snapshot: snapshot, at: date.addingTimeInterval(10)))
            XCTAssertFalse(animation.stop(snapshot: snapshot, at: date.addingTimeInterval(10)))
            assertMotion(animation, matches: before)
        }
    }

    func testInteractionsRejectUninitializedOrDifferentRunsAndAnExpiredRunningSnapshot() throws {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let velocity = CGVector(dx: 240, dy: 100)
        var animation = MrSmilesAnimation()
        XCTAssertFalse(animation.flick(velocity: velocity, snapshot: snapshot, at: date))
        XCTAssertFalse(animation.stop(snapshot: snapshot, at: date))
        update(&animation, snapshot: snapshot, at: date)
        let before = try XCTUnwrap(animation.motion)

        let other = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        XCTAssertFalse(animation.flick(velocity: velocity, snapshot: TimerSnapshot(run: other, at: date), at: date))
        XCTAssertFalse(animation.stop(snapshot: TimerSnapshot(run: other, at: date), at: date))
        XCTAssertFalse(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(60)))
        XCTAssertFalse(animation.stop(snapshot: snapshot, at: date.addingTimeInterval(60)))
        assertMotion(animation, matches: before)
    }

    func testOlderRunningSnapshotCannotReenableInteractionsAfterPause() throws {
        var run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let running = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: running, at: date)
        run.progressSeconds = 20
        run.resumedAt = nil
        update(
            &animation,
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(20)),
            at: date.addingTimeInterval(20),
        )
        let paused = try XCTUnwrap(animation.motion)

        update(&animation, snapshot: running, at: date.addingTimeInterval(21))
        XCTAssertFalse(animation.flick(velocity: CGVector(dx: 240, dy: 100), snapshot: running, at: date.addingTimeInterval(21)))
        XCTAssertFalse(animation.stop(snapshot: running, at: date.addingTimeInterval(21)))
        assertMotion(animation, matches: paused)
    }

    func testRejectedWeakOrInvalidFlicksDoNotEnterReplayHistory() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let velocities = [CGVector.zero, CGVector(dx: 10, dy: 10), CGVector(dx: CGFloat.nan, dy: 50)]
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        for velocity in velocities {
            XCTAssertFalse(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(2)))
        }
        XCTAssertFalse(animation.flick(
            velocity: CGVector(dx: 240, dy: 100),
            snapshot: snapshot,
            at: Date(timeIntervalSinceReferenceDate: .infinity),
        ))
        XCTAssertFalse(animation.stop(snapshot: snapshot, at: Date(timeIntervalSinceReferenceDate: .infinity)))

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(1))
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(10))
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 10)
        assertMotion(animation, matches: expected)
    }

    func testNewRunClearsThePreviousRunsInteractionHistory() {
        let first = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let second = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let firstSnapshot = TimerSnapshot(run: first, at: date)
        let secondSnapshot = TimerSnapshot(run: second, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: firstSnapshot, at: date)
        XCTAssertTrue(animation.flick(velocity: CGVector(dx: 240, dy: 100), snapshot: firstSnapshot, at: date.addingTimeInterval(2)))
        XCTAssertTrue(animation.stop(snapshot: firstSnapshot, at: date.addingTimeInterval(3)))

        update(&animation, snapshot: secondSnapshot, at: date.addingTimeInterval(10))
        update(&animation, snapshot: secondSnapshot, at: date.addingTimeInterval(1))
        update(&animation, snapshot: secondSnapshot, at: date.addingTimeInterval(10))
        var expected = makeMotion(seed: second.id)
        expected.advance(to: 10)
        assertMotion(animation, matches: expected)
    }

    func testRepeatedStopsKeepTheFaceStillWhileActiveTimeContinues() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(20))
        let moving = try XCTUnwrap(animation.motion)
        XCTAssertNotEqual(moving.velocity, .zero)

        for elapsed in [20.0, 20.2, 30, 60] {
            XCTAssertTrue(animation.stop(snapshot: snapshot, at: date.addingTimeInterval(elapsed)))
            let held = try XCTUnwrap(animation.motion)
            XCTAssertEqual(held.elapsed, elapsed, accuracy: 0.0001)
            XCTAssertEqual(held.position, moving.position)
            XCTAssertEqual(held.rotation, moving.rotation)
            XCTAssertEqual(held.velocity, .zero)
            XCTAssertEqual(held.angularVelocity, 0)
        }

        let refreshed = TimerSnapshot(run: run, at: date.addingTimeInterval(90))
        update(&animation, snapshot: refreshed, at: date.addingTimeInterval(90))
        let held = try XCTUnwrap(animation.motion)
        XCTAssertEqual(held.elapsed, 90)
        XCTAssertEqual(held.position, moving.position)
        XCTAssertEqual(held.rotation, moving.rotation)
        XCTAssertEqual(refreshed.elapsedSeconds, 90)
        XCTAssertEqual(refreshed.status, .running)
    }

    func testFlickAfterHoldingStartsFromTheHeldPositionAndOrientation() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        XCTAssertTrue(animation.stop(snapshot: snapshot, at: date.addingTimeInterval(20)))
        var expected = try XCTUnwrap(animation.motion)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(24))
        let held = try XCTUnwrap(animation.motion)
        XCTAssertEqual(held.position, expected.position)
        XCTAssertEqual(held.rotation, expected.rotation)

        let velocity = CGVector(dx: -120, dy: 100)
        XCTAssertTrue(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(24.5)))
        expected.advance(to: 24.5)
        XCTAssertTrue(expected.flick(velocity: velocity))
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(25))
        expected.advance(to: 25)
        assertMotion(animation, matches: expected)
    }

    func testMoveFollowsTheFingerAndReplaysAfterAResize() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let target = CGPoint(x: 190, y: 300)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)

        XCTAssertTrue(animation.move(to: target, snapshot: snapshot, at: date.addingTimeInterval(2)))
        let moved = try XCTUnwrap(animation.motion)
        XCTAssertEqual(moved.position, target)
        XCTAssertEqual(moved.velocity, .zero)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(10))
        XCTAssertEqual(try XCTUnwrap(animation.motion).position, target)

        let resized = CGSize(width: 844, height: 390)
        animation.update(
            snapshot: snapshot,
            at: date.addingTimeInterval(10),
            size: resized,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
        var expected = MrSmilesMotion(seed: run.id, size: resized, faceRadius: faceRadius, screenCornerRadius: screenCornerRadius)
        expected.advance(to: 2)
        XCTAssertTrue(expected.move(to: target))
        expected.advance(to: 10)
        assertMotion(animation, matches: expected)
    }

    func testMoveThenFlickStartsFromThePlacedPosition() throws {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        let target = CGPoint(x: 200, y: 280)
        let velocity = CGVector(dx: -120, dy: 100)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)

        XCTAssertTrue(animation.move(to: target, snapshot: snapshot, at: date.addingTimeInterval(2)))
        XCTAssertTrue(animation.flick(velocity: velocity, snapshot: snapshot, at: date.addingTimeInterval(5)))
        let flicked = try XCTUnwrap(animation.motion)
        XCTAssertEqual(flicked.position, target)
        XCTAssertEqual(flicked.velocity, velocity)

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(5.5))
        XCTAssertEqual(try XCTUnwrap(animation.motion).position, CGPoint(x: 140, y: 330))
    }

    func testMoveRejectsPausedOrCompletedRuns() throws {
        let pausedRun = FocusRun(createdAt: date, startedAt: date, progressSeconds: 2)
        let completeRun = FocusRun(createdAt: date, startedAt: date, goalSeconds: 2, resumedAt: date)
        for run in [pausedRun, completeRun] {
            let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(2))
            var animation = MrSmilesAnimation()
            update(&animation, snapshot: snapshot, at: date.addingTimeInterval(2))
            let before = try XCTUnwrap(animation.motion)
            XCTAssertFalse(animation.move(to: CGPoint(x: 200, y: 280), snapshot: snapshot, at: date.addingTimeInterval(2)))
            assertMotion(animation, matches: before)
        }
    }

    func testMixedStopsAndFlicksReplayAfterResizeAndStayStoppedAcrossPauseAndResume() {
        var run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let running = TimerSnapshot(run: run, at: date)
        let firstVelocity = CGVector(dx: 240, dy: -100)
        let secondVelocity = CGVector(dx: -160, dy: 210)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: running, at: date)
        XCTAssertTrue(animation.flick(velocity: firstVelocity, snapshot: running, at: date.addingTimeInterval(2)))
        XCTAssertTrue(animation.stop(snapshot: running, at: date.addingTimeInterval(3)))
        XCTAssertTrue(animation.flick(velocity: secondVelocity, snapshot: running, at: date.addingTimeInterval(6)))
        XCTAssertTrue(animation.stop(snapshot: running, at: date.addingTimeInterval(7)))

        let resized = CGSize(width: 844, height: 390)
        animation.update(
            snapshot: running,
            at: date.addingTimeInterval(80),
            size: resized,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
        var expected = MrSmilesMotion(seed: run.id, size: resized, faceRadius: faceRadius, screenCornerRadius: screenCornerRadius)
        expected.advance(to: 2)
        XCTAssertTrue(expected.flick(velocity: firstVelocity))
        expected.advance(to: 3)
        expected.stop()
        expected.advance(to: 6)
        XCTAssertTrue(expected.flick(velocity: secondVelocity))
        expected.advance(to: 7)
        expected.stop()
        expected.advance(to: 80)
        assertMotion(animation, matches: expected)

        run.progressSeconds = 80
        run.resumedAt = nil
        animation.update(
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(80)),
            at: date.addingTimeInterval(900),
            size: resized,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
        assertMotion(animation, matches: expected)

        run.resumedAt = date.addingTimeInterval(900)
        animation.update(
            snapshot: TimerSnapshot(run: run, at: date.addingTimeInterval(900)),
            at: date.addingTimeInterval(905),
            size: resized,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
        expected.advance(to: 85)
        assertMotion(animation, matches: expected)
    }

    func testStaleFrameBeforeHoldRetainsTheStopWhenTimeCatchesUp() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        var animation = MrSmilesAnimation()
        update(&animation, snapshot: snapshot, at: date)
        XCTAssertTrue(animation.stop(snapshot: snapshot, at: date.addingTimeInterval(20)))

        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(19.99))
        update(&animation, snapshot: snapshot, at: date.addingTimeInterval(21))
        var expected = makeMotion(seed: run.id)
        expected.advance(to: 20)
        expected.stop()
        expected.advance(to: 21)
        assertMotion(animation, matches: expected)
    }

    private func update(_ animation: inout MrSmilesAnimation, snapshot: TimerSnapshot, at date: Date) {
        animation.update(
            snapshot: snapshot,
            at: date,
            size: size,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
    }

    private func makeMotion(seed: UUID) -> MrSmilesMotion {
        MrSmilesMotion(
            seed: seed,
            size: size,
            faceRadius: faceRadius,
            screenCornerRadius: screenCornerRadius,
        )
    }

    private func assertMotion(
        _ animation: MrSmilesAnimation,
        matches expected: MrSmilesMotion,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard let motion = animation.motion else {
            XCTFail("Expected an initialized motion", file: file, line: line)
            return
        }
        XCTAssertEqual(motion.elapsed, expected.elapsed, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.position.x, expected.position.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.position.y, expected.position.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.velocity.dx, expected.velocity.dx, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.velocity.dy, expected.velocity.dy, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.rotation, expected.rotation, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.angularVelocity, expected.angularVelocity, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(motion.leftEyeWinking, expected.leftEyeWinking, file: file, line: line)
        XCTAssertEqual(motion.rightEyeWinking, expected.rightEyeWinking, file: file, line: line)
    }
}
