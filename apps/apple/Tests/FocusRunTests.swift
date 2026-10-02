import XCTest
@testable import App

final class FocusRunTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewRunIsReadyWithTwentyFiveMinuteGoal() {
        let run = FocusRun(createdAt: date)

        XCTAssertEqual(run.createdAt, date)
        XCTAssertEqual(run.goalSeconds, 1_500)
        XCTAssertEqual(run.restSeconds, 0)
        XCTAssertEqual(run.theme, "boring")
        XCTAssertEqual(run.elapsed(at: date), 0)
        XCTAssertEqual(run.remaining(at: date), 1_500)
        XCTAssertEqual(run.fraction(at: date), 0)
        XCTAssertFalse(run.hasStarted)
        XCTAssertFalse(run.isRunning)
        XCTAssertFalse(run.isComplete(at: date))
    }

    func testRunningAddsFractionalTimeToSavedProgress() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 12.25, resumedAt: date)
        let later = date.addingTimeInterval(5.5)

        XCTAssertEqual(run.elapsed(at: later), 17.75)
        XCTAssertEqual(run.remaining(at: later), 1_482.25)
        XCTAssertEqual(run.fraction(at: later), 17.75 / 1_500)
        XCTAssertTrue(run.hasStarted)
        XCTAssertTrue(run.isRunning)
    }

    func testPausedRunKeepsSavedProgressAsTimePasses() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 300)

        XCTAssertEqual(run.elapsed(at: date.addingTimeInterval(100_000)), 300)
        XCTAssertEqual(run.remaining(at: date), 1_200)
        XCTAssertEqual(run.fraction(at: date), 0.2)
        XCTAssertTrue(run.hasStarted)
        XCTAssertFalse(run.isRunning)
    }

    func testCompletionClampsToGoalAtAndBeyondDeadline() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date)

        XCTAssertFalse(run.isComplete(at: date.addingTimeInterval(59.999)))
        XCTAssertTrue(run.isComplete(at: date.addingTimeInterval(60)))
        XCTAssertEqual(run.elapsed(at: date.addingTimeInterval(1_000)), 60)
        XCTAssertEqual(run.remaining(at: date.addingTimeInterval(1_000)), 0)
        XCTAssertEqual(run.fraction(at: date.addingTimeInterval(1_000)), 1)
    }

    func testClockMovingBackwardsDoesNotSubtractProgress() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 30.75, resumedAt: date)

        XCTAssertEqual(run.elapsed(at: date.addingTimeInterval(-100)), 30.75)
    }

    func testNegativeProgressCannotProduceNegativeElapsedTime() {
        let run = FocusRun(createdAt: date, progressSeconds: -100)

        XCTAssertEqual(run.elapsed(at: date), 0)
        XCTAssertEqual(run.remaining(at: date), 1_500)
        XCTAssertEqual(run.fraction(at: date), 0)
    }

    func testExcessiveSavedProgressCannotExceedGoal() {
        let run = FocusRun(createdAt: date, progressSeconds: 5_000, goalSeconds: 60)

        XCTAssertEqual(run.elapsed(at: date), 60)
        XCTAssertEqual(run.remaining(at: date), 0)
        XCTAssertEqual(run.fraction(at: date), 1)
        XCTAssertTrue(run.isComplete(at: date))
    }

    func testInvalidProgressIsTreatedAsZero() {
        for progress in [TimeInterval.nan, .infinity, -.infinity] {
            let run = FocusRun(createdAt: date, progressSeconds: progress)

            XCTAssertEqual(run.elapsed(at: date), 0)
            XCTAssertEqual(run.fraction(at: date), 0)
        }
    }

    func testInvalidClockIntervalDoesNotDamageSavedProgress() {
        let run = FocusRun(createdAt: date, progressSeconds: 20, resumedAt: date)

        XCTAssertEqual(run.elapsed(at: Date(timeIntervalSinceReferenceDate: .infinity)), 20)
    }

    func testInvalidGoalsRemainSafeForRendering() {
        for goal in [0, -60] {
            let run = FocusRun(createdAt: date, goalSeconds: goal)

            XCTAssertEqual(run.elapsed(at: date), 0)
            XCTAssertEqual(run.remaining(at: date), 0)
            XCTAssertEqual(run.fraction(at: date), 1)
            XCTAssertTrue(run.isComplete(at: date))
        }
    }

    func testRunRoundTripsAllFieldsIncludingFractionalProgressAndTheme() throws {
        let run = FocusRun(
            createdAt: date,
            startedAt: date.addingTimeInterval(30),
            progressSeconds: 24.125,
            goalSeconds: 900,
            restSeconds: 180,
            theme: "future-theme",
            resumedAt: date.addingTimeInterval(100),
        )

        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONEncoder().encode(run))

        XCTAssertEqual(decoded, run)
    }

    func testReadyRunRoundTripsOptionalTimestamps() throws {
        let run = FocusRun(createdAt: date)

        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONEncoder().encode(run))

        XCTAssertEqual(decoded, run)
        XCTAssertNil(decoded.startedAt)
        XCTAssertNil(decoded.resumedAt)
    }

    func testMissingRestSecondsDecodesAsZero() throws {
        let run = FocusRun(createdAt: date, goalSeconds: 600, theme: "boring")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        object.removeValue(forKey: "restSeconds")

        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertEqual(decoded.restSeconds, 0)
        XCTAssertEqual(decoded.goalSeconds, 600)
    }

    func testRestPeriodStartsAfterFocusAndCompletesAtTotal() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 30, resumedAt: date)

        XCTAssertFalse(run.isResting(at: date.addingTimeInterval(59)))
        XCTAssertEqual(run.periodRemaining(at: date.addingTimeInterval(20)), 40)
        XCTAssertEqual(run.periodProgress(at: date.addingTimeInterval(20)), 20.0 / 60, accuracy: 0.0001)
        XCTAssertTrue(run.isResting(at: date.addingTimeInterval(60)))
        XCTAssertEqual(run.periodRemaining(at: date.addingTimeInterval(75)), 15)
        XCTAssertEqual(run.periodProgress(at: date.addingTimeInterval(75)), 0.5, accuracy: 0.0001)
        XCTAssertFalse(run.isComplete(at: date.addingTimeInterval(89.999)))
        XCTAssertTrue(run.isComplete(at: date.addingTimeInterval(90)))
        XCTAssertEqual(run.remaining(at: date), 90)
        XCTAssertEqual(run.focusRemaining(at: date.addingTimeInterval(75)), 0)
        XCTAssertNotEqual(run.restAlarmID, run.id)
        XCTAssertEqual(run.restAlarmID, run.restAlarmID)
    }

    func testZeroRestNeverEntersRestAndCompletesAtFocus() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 0, resumedAt: date)

        XCTAssertFalse(run.isResting(at: date.addingTimeInterval(60)))
        XCTAssertTrue(run.isComplete(at: date.addingTimeInterval(60)))
        XCTAssertEqual(run.periodProgress(at: date.addingTimeInterval(60)), 1)
    }

    func testPauseWindowCountsDownThenAutoResumesFromDeadline() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 100, goalSeconds: 600, pausedAt: date)

        XCTAssertEqual(run.pauseDeadline, date.addingTimeInterval(60))
        XCTAssertEqual(run.pauseRemaining(at: date.addingTimeInterval(15)), 45)
        XCTAssertNil(run.pauseRemaining(at: date.addingTimeInterval(60)))
        XCTAssertEqual(run.autoResumed(at: date.addingTimeInterval(30)), run)

        let resumed = run.autoResumed(at: date.addingTimeInterval(90))
        XCTAssertTrue(resumed.isRunning)
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.elapsed(at: date.addingTimeInterval(90)), 130)
    }

    func testResumingAtPauseDeadlineFreezesProgressUntilDeadline() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 100, goalSeconds: 600, pausedAt: date)
        let forecast = run.resumingAtPauseDeadline()

        XCTAssertEqual(forecast.elapsed(at: date.addingTimeInterval(30)), 100)
        XCTAssertEqual(forecast.resumeDelay(at: date.addingTimeInterval(30)), 30)
        XCTAssertEqual(forecast.resumeDelay(at: date.addingTimeInterval(90)), 0)
        let idle = FocusRun(createdAt: date)
        XCTAssertEqual(idle.resumingAtPauseDeadline(), idle)
    }

    func testRunningRunHasNoPauseDeadline() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date, pausedAt: date)

        XCTAssertNil(run.pauseDeadline)
    }

    func testPausedAtRoundTripsThroughCodable() throws {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 5, pausedAt: date)
        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONEncoder().encode(run))

        XCTAssertEqual(decoded, run)
    }

    func testLoopingRunRestartsCycleAfterRestAndNeverCompletes() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)

        XCTAssertEqual(run.completedCycles(at: date.addingTimeInterval(359)), 0)
        XCTAssertTrue(run.isResting(at: date.addingTimeInterval(359)))
        XCTAssertEqual(run.completedCycles(at: date.addingTimeInterval(360)), 1)
        XCTAssertFalse(run.isResting(at: date.addingTimeInterval(360)))
        XCTAssertEqual(run.cycleElapsed(at: date.addingTimeInterval(370)), 10)
        XCTAssertEqual(run.focusRemaining(at: date.addingTimeInterval(370)), 290)
        XCTAssertEqual(run.remaining(at: date.addingTimeInterval(370)), 350)
        XCTAssertEqual(run.periodRemaining(at: date.addingTimeInterval(370)), 290)
        XCTAssertEqual(run.elapsed(at: date.addingTimeInterval(1_000)), 1_000)
        XCTAssertEqual(run.completedCycles(at: date.addingTimeInterval(1_000)), 2)
        XCTAssertTrue(run.isResting(at: date.addingTimeInterval(1_020)))
        XCTAssertEqual(run.fraction(at: date.addingTimeInterval(1_000)), 1)
        XCTAssertFalse(run.isComplete(at: date.addingTimeInterval(100_000)))
    }

    func testLoopingRunCountsFocusAcrossCycles() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 800, goalSeconds: 300, restSeconds: 60, loops: true)

        XCTAssertEqual(run.focusElapsed(at: date), 680)
        XCTAssertEqual(run.didFinishCycle(at: date), true)
        let oneShot = FocusRun(createdAt: date, startedAt: date, progressSeconds: 800, goalSeconds: 300, restSeconds: 60)
        XCTAssertEqual(oneShot.focusElapsed(at: date), 300)
        XCTAssertEqual(oneShot.completedCycles(at: date), 1)
        XCTAssertEqual(oneShot.cycleElapsed(at: date), 360)
        XCTAssertEqual(FocusRun(createdAt: date, progressSeconds: 100).completedCycles(at: date), 0)
        XCTAssertFalse(FocusRun(createdAt: date, progressSeconds: 100).didFinishCycle(at: date))
    }

    func testLoopingRunWithoutRestRepeatsFocus() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date, loops: true)

        XCTAssertEqual(run.completedCycles(at: date.addingTimeInterval(150)), 2)
        XCTAssertEqual(run.periodRemaining(at: date.addingTimeInterval(150)), 30)
        XCTAssertFalse(run.isResting(at: date.addingTimeInterval(150)))
    }

    func testAlarmIdentifiersAreStableAndDistinctPerCycle() {
        let run = FocusRun(createdAt: date)

        XCTAssertEqual(run.alarmID(cycle: 0, resting: false), run.id)
        XCTAssertEqual(run.alarmID(cycle: 0, resting: true), run.restAlarmID)
        XCTAssertEqual(run.alarmID(cycle: 3, resting: false), run.alarmID(cycle: 3, resting: false))
        let identifiers = (0..<4).flatMap { [run.alarmID(cycle: $0, resting: false), run.alarmID(cycle: $0, resting: true)] }
        XCTAssertEqual(Set(identifiers).count, 8)
    }

    func testLoopRoundTripsAndDefaultsWhenMissing() throws {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 5, loops: true)
        let decoded = try JSONDecoder().decode(FocusRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded, run)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        object.removeValue(forKey: "loops")
        let legacy = try JSONDecoder().decode(FocusRun.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(legacy.loops)
    }
}
