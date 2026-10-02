import XCTest
@testable import App

final class TimerSnapshotTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)

    func testReadyRunPresentsDurationAndStartControl() {
        let run = FocusRun(createdAt: date)
        let snapshot = TimerSnapshot(run: run, at: date)
        XCTAssertEqual(snapshot.runID, run.id)
        XCTAssertEqual(snapshot.sampledAt, date)
        XCTAssertEqual(snapshot.goalSeconds, 1500)
        XCTAssertEqual(snapshot.elapsedSeconds, 0)
        XCTAssertEqual(snapshot.remainingSeconds, 1500)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.clockText, "25:00")
        XCTAssertEqual(snapshot.controlSymbol, "play.fill")
        XCTAssertEqual(snapshot.controlLabel, "Start timer")
    }

    func testLoopingSnapshotShowsCurrentCycleAndStopControl() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(370))
        XCTAssertEqual(snapshot.status, .running)
        XCTAssertTrue(snapshot.loops)
        XCTAssertEqual(snapshot.cycle, 1)
        XCTAssertEqual(snapshot.elapsedSeconds, 10)
        XCTAssertFalse(snapshot.isResting)
        XCTAssertEqual(snapshot.clockText, "04:50")
        XCTAssertTrue(snapshot.canStop)
        XCTAssertEqual(snapshot.stopLabel, "Stop loop")
    }

    func testStopControlOnlyAppliesToActiveRuns() {
        XCTAssertFalse(TimerSnapshot(run: FocusRun(createdAt: date), at: date).canStop)
        let paused = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 10), at: date)
        XCTAssertTrue(paused.canStop)
        XCTAssertEqual(paused.stopLabel, "Stop timer")
        XCTAssertEqual(paused.cycle, 0)
        let complete = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 1_500), at: date)
        XCTAssertEqual(complete.status, .complete)
        XCTAssertFalse(complete.canStop)
    }

    func testRunningSnapshotRoundsRemainingTimeUp() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(60.2))
        XCTAssertEqual(snapshot.sampledAt, date.addingTimeInterval(60.2))
        XCTAssertEqual(snapshot.status, .running)
        XCTAssertEqual(snapshot.clockText, "24:00")
        XCTAssertEqual(snapshot.elapsedSeconds, 60.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.progress, 60.2 / 1500, accuracy: 0.001)
        XCTAssertEqual(snapshot.controlSymbol, "pause.fill")
        XCTAssertEqual(snapshot.controlLabel, "Pause timer")
    }

    func testPausedSnapshotDoesNotAdvance() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 70)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(900))
        XCTAssertEqual(snapshot.status, .paused)
        XCTAssertEqual(snapshot.clockText, "23:50")
        XCTAssertEqual(snapshot.controlSymbol, "play.fill")
        XCTAssertEqual(snapshot.controlLabel, "Resume timer")
    }

    func testCompletionWinsOverRunningUntilStoreRefreshes() {
        let run = FocusRun(createdAt: date, startedAt: date, resumedAt: date)
        let snapshot = TimerSnapshot(run: run, at: date.addingTimeInterval(1800))
        XCTAssertEqual(snapshot.status, .complete)
        XCTAssertEqual(snapshot.clockText, "00:00")
        XCTAssertEqual(snapshot.progress, 1)
        XCTAssertEqual(snapshot.controlSymbol, "arrow.counterclockwise")
        XCTAssertEqual(snapshot.controlLabel, "New run with the same settings")
    }

    func testLongDurationsKeepMinutesRatherThanSwitchingToHours() {
        let run = FocusRun(createdAt: date, goalSeconds: 7200)
        XCTAssertEqual(TimerSnapshot(run: run, at: date).clockText, "120:00")
    }

    func testRestResetsClockAndProgressUntilTheBreakCompletes() {
        let run = FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 30, resumedAt: date)
        let focusing = TimerSnapshot(run: run, at: date.addingTimeInterval(20))
        XCTAssertFalse(focusing.isResting)
        XCTAssertEqual(focusing.status, .running)
        XCTAssertEqual(focusing.clockText, "00:40")
        XCTAssertEqual(focusing.progress, 20.0 / 60, accuracy: 0.0001)

        let resting = TimerSnapshot(run: run, at: date.addingTimeInterval(75))
        XCTAssertTrue(resting.isResting)
        XCTAssertEqual(resting.status, .running)
        XCTAssertEqual(resting.clockText, "00:15")
        XCTAssertEqual(resting.progress, 0.5, accuracy: 0.0001)

        let complete = TimerSnapshot(run: run, at: date.addingTimeInterval(90))
        XCTAssertFalse(complete.isResting)
        XCTAssertEqual(complete.status, .complete)
        XCTAssertEqual(complete.clockText, "00:00")
        XCTAssertEqual(complete.progress, 1)
    }

    func testPauseWindowShowsCountdownThenResumes() {
        let run = FocusRun(createdAt: date, startedAt: date, progressSeconds: 100, goalSeconds: 600, pausedAt: date)

        let paused = TimerSnapshot(run: run, at: date.addingTimeInterval(20))
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(paused.pauseRemainingSeconds, 40)
        XCTAssertEqual(paused.pauseWindowSeconds, 60)

        let resumed = TimerSnapshot(run: run, at: date.addingTimeInterval(70))
        XCTAssertEqual(resumed.status, .running)
        XCTAssertNil(resumed.pauseRemainingSeconds)
        XCTAssertEqual(resumed.elapsedSeconds, 110)
    }
}
