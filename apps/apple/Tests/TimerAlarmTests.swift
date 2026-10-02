import XCTest
@testable import App

final class TimerAlarmTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testUnavailableAlarmSupportReportsUnavailable() async {
        let alarm = TimerAlarm(manager: nil, now: { self.date })

        let covered = await alarm.synchronize(
            run: FocusRun(startedAt: date, resumedAt: date),
            requestPermission: true,
        )

        XCTAssertEqual(covered, .unavailable)
    }

    @MainActor
    func testSchedulesTheRunIdentifierAndAbsoluteRemainingDeadline() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(
            startedAt: date.addingTimeInterval(-60),
            progressSeconds: 30,
            goalSeconds: 300,
            resumedAt: date.addingTimeInterval(-10),
        )

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.schedules.count, 1)
        XCTAssertEqual(manager.schedules.first?.id, run.id)
        XCTAssertEqual(manager.schedules.first?.deadline, date.addingTimeInterval(260))
        XCTAssertEqual(manager.authorizationRequests, 0)
    }

    @MainActor
    func testSchedulesFocusAndRestAlarmsUpfront() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date)

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.schedules.map(\.id), [run.id, run.restAlarmID])
        XCTAssertEqual(manager.schedules.map(\.deadline), [date.addingTimeInterval(300), date.addingTimeInterval(360)])
        XCTAssertEqual(Set(manager.records.map(\.id)), [run.id, run.restAlarmID])
    }

    @MainActor
    func testLoopingRunSchedulesTheNextCycleUpfront() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.schedules.map(\.id), [
            run.id,
            run.restAlarmID,
            run.alarmID(cycle: 1, resting: false),
            run.alarmID(cycle: 1, resting: true),
        ])
        XCTAssertEqual(manager.schedules.map(\.deadline), [
            date.addingTimeInterval(300),
            date.addingTimeInterval(360),
            date.addingTimeInterval(660),
            date.addingTimeInterval(720),
        ])
    }

    @MainActor
    func testLoopingRunKeepsTheRingingPriorCycleAlarmAndSchedulesAhead() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, progressSeconds: 370, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)
        let stale = UUID()
        manager.records = [
            TimerAlarmRecord(id: run.restAlarmID, deadline: date.addingTimeInterval(-10), state: .alerting),
            TimerAlarmRecord(id: run.alarmID(cycle: 1, resting: false), deadline: date.addingTimeInterval(290), state: .scheduled),
            TimerAlarmRecord(id: run.alarmID(cycle: 1, resting: true), deadline: date.addingTimeInterval(350), state: .scheduled),
            TimerAlarmRecord(id: stale, deadline: date.addingTimeInterval(100), state: .scheduled),
        ]

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.cancellations, [stale])
        XCTAssertEqual(manager.schedules.map(\.id), [run.alarmID(cycle: 2, resting: false), run.alarmID(cycle: 2, resting: true)])
        XCTAssertEqual(manager.schedules.map(\.deadline), [date.addingTimeInterval(650), date.addingTimeInterval(710)])
        XCTAssertTrue(manager.records.contains { $0.id == run.restAlarmID && $0.state == .alerting })
    }

    @MainActor
    func testStoppingALoopCancelsUpcomingAlarms() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)
        _ = await alarm.synchronize(run: run)
        run.progressSeconds = 30
        run.resumedAt = nil
        run.stoppedAt = date

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .unavailable)
        XCTAssertTrue(manager.records.isEmpty)
    }

    @MainActor
    func testPauseCancelsFocusAndRestAlarmsAndResumeReschedulesRemainingTime() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date)
        _ = await alarm.synchronize(run: run)
        run.progressSeconds = 40
        run.resumedAt = nil

        let paused = await alarm.synchronize(run: run)
        XCTAssertEqual(paused, .unavailable)
        XCTAssertEqual(Set(manager.cancellations), [run.id, run.restAlarmID])
        XCTAssertTrue(manager.records.isEmpty)

        manager.schedules.removeAll()
        manager.cancellations.removeAll()
        run.resumedAt = date
        let resumed = await alarm.synchronize(run: run)
        XCTAssertEqual(resumed, .scheduled)
        XCTAssertEqual(manager.schedules.map(\.id), [run.id, run.restAlarmID])
        XCTAssertEqual(manager.schedules.map(\.deadline), [date.addingTimeInterval(260), date.addingTimeInterval(320)])
    }

    @MainActor
    func testResumingDuringRestOnlySchedulesTheRestAlarm() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, progressSeconds: 320, goalSeconds: 300, restSeconds: 60, resumedAt: date)

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.schedules.map(\.id), [run.restAlarmID])
        XCTAssertEqual(manager.schedules.first?.deadline, date.addingTimeInterval(40))
        XCTAssertEqual(manager.records.map(\.id), [run.restAlarmID])
    }

    @MainActor
    func testForegroundRefreshKeepsTheExistingDeadline() async {
        let manager = AlarmManagerBoundary()
        var now = date
        let alarm = TimerAlarm(manager: manager, now: { now })
        let run = FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date)
        _ = await alarm.synchronize(run: run)
        now = date.addingTimeInterval(40)
        var refreshed = run
        refreshed.progressSeconds = 40
        refreshed.resumedAt = now

        let covered = await alarm.synchronize(run: refreshed)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.schedules.count, 1)
        XCTAssertTrue(manager.cancellations.isEmpty)
    }

    @MainActor
    func testExistingCountdownWithoutDeadlineIsKept() async {
        let manager = AlarmManagerBoundary()
        let run = FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date)
        manager.records = [TimerAlarmRecord(id: run.id, deadline: nil, state: .scheduled)]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertTrue(manager.schedules.isEmpty)
        XCTAssertTrue(manager.cancellations.isEmpty)
    }

    @MainActor
    func testRelaunchRecognizesTheExistingSystemAlarm() async {
        let manager = AlarmManagerBoundary()
        let run = FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date)
        manager.records = [TimerAlarmRecord(id: run.id, deadline: date.addingTimeInterval(300.001), state: .scheduled)]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertTrue(manager.schedules.isEmpty)
        XCTAssertTrue(manager.cancellations.isEmpty)
    }

    @MainActor
    func testChangedDeadlineReplacesTheSameRunAlarm() async {
        let manager = AlarmManagerBoundary()
        let run = FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date)
        manager.records = [TimerAlarmRecord(id: run.id, deadline: date.addingTimeInterval(200), state: .scheduled)]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.cancellations, [run.id])
        XCTAssertEqual(manager.records.first?.deadline, date.addingTimeInterval(300))
    }

    @MainActor
    func testReplacingRunCancelsOlderScheduledAndRingingAlarms() async {
        let manager = AlarmManagerBoundary()
        let oldIDs = [UUID(), UUID()]
        manager.records = [
            TimerAlarmRecord(id: oldIDs[0], deadline: date.addingTimeInterval(300), state: .scheduled),
            TimerAlarmRecord(id: oldIDs[1], deadline: date, state: .alerting),
        ]
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.cancellations, oldIDs)
        XCTAssertEqual(manager.records.map(\.id), [run.id])
    }

    @MainActor
    func testPauseAndResetRemovePendingAlarms() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, resumedAt: date)
        _ = await alarm.synchronize(run: run)
        run.resumedAt = nil

        let pausedCovered = await alarm.synchronize(run: run)

        XCTAssertEqual(pausedCovered, .unavailable)
        XCTAssertEqual(manager.cancellations, [run.id])
        XCTAssertTrue(manager.records.isEmpty)

        run.resumedAt = date
        _ = await alarm.synchronize(run: run)
        let resetCovered = await alarm.synchronize(run: FocusRun())

        XCTAssertEqual(resetCovered, .unavailable)
        XCTAssertTrue(manager.records.isEmpty)
        XCTAssertEqual(manager.cancellations, [run.id, run.id])
    }

    @MainActor
    func testCompletingRunPreservesCurrentRingingAndJustDueAlarms() async {
        for state in [TimerAlarmRecord.State.alerting, .scheduled] {
            let manager = AlarmManagerBoundary()
            let run = FocusRun(startedAt: date, progressSeconds: 60, goalSeconds: 60)
            manager.records = [TimerAlarmRecord(id: run.id, deadline: date, state: state)]
            let alarm = TimerAlarm(manager: manager, now: { self.date })

            let covered = await alarm.synchronize(run: run)

            XCTAssertEqual(covered, .scheduled)
            XCTAssertTrue(manager.cancellations.isEmpty)
            XCTAssertTrue(manager.schedules.isEmpty)
        }
    }

    @MainActor
    func testDismissedCompletedAlarmIsNeverRescheduled() async {
        let manager = AlarmManagerBoundary()
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: FocusRun(startedAt: date, progressSeconds: 60, goalSeconds: 60))

        XCTAssertEqual(covered, .unavailable)
        XCTAssertTrue(manager.schedules.isEmpty)
    }

    @MainActor
    func testCompletedRunCancelsAnIncorrectFutureAlarm() async {
        let manager = AlarmManagerBoundary()
        let run = FocusRun(startedAt: date, progressSeconds: 60, goalSeconds: 60)
        manager.records = [TimerAlarmRecord(id: run.id, deadline: date.addingTimeInterval(30), state: .scheduled)]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .unavailable)
        XCTAssertEqual(manager.cancellations, [run.id])
    }

    @MainActor
    func testPermissionIsOnlyRequestedOnExplicitPlayAndOnlyOnce() async {
        let manager = AlarmManagerBoundary()
        manager.authorizationState = .notDetermined
        manager.requiresAuthorizationForListing = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        let initialCovered = await alarm.synchronize(run: run)
        XCTAssertEqual(initialCovered, .uncertain)
        XCTAssertEqual(manager.authorizationRequests, 0)

        let playCovered = await alarm.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(playCovered, .scheduled)
        XCTAssertEqual(manager.authorizationRequests, 1)

        _ = await alarm.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(manager.authorizationRequests, 1)
    }

    @MainActor
    func testDeniedPermissionAndSystemErrorsReportCoverage() async {
        let manager = AlarmManagerBoundary()
        manager.authorizationState = .notDetermined
        manager.permissionResult = .denied
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        let denied = await alarm.synchronize(run: run, requestPermission: true)
        let deniedAgain = await alarm.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(denied, .unavailable)
        XCTAssertEqual(deniedAgain, .unavailable)
        XCTAssertEqual(manager.authorizationRequests, 1)
        XCTAssertTrue(manager.schedules.isEmpty)

        manager.authorizationState = .notDetermined
        manager.permissionError = true
        let permissionFailed = await alarm.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(permissionFailed, .unavailable)

        manager.authorizationState = .authorized
        manager.listingError = true
        let listingFailed = await alarm.synchronize(run: run)
        XCTAssertEqual(listingFailed, .uncertain)

        manager.listingError = false
        manager.scheduleError = true
        let scheduleFailed = await alarm.synchronize(run: run)
        XCTAssertEqual(scheduleFailed, .unavailable)

        manager.scheduleError = false
        let recovered = await alarm.synchronize(run: run)
        XCTAssertEqual(recovered, .scheduled)
    }

    @MainActor
    func testCancellationFailureDoesNotAddAnotherAlarm() async {
        let manager = AlarmManagerBoundary()
        let oldID = UUID()
        manager.records = [TimerAlarmRecord(id: oldID, deadline: date, state: .alerting)]
        manager.cancellationErrors = [oldID]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: FocusRun(startedAt: date, resumedAt: date))

        XCTAssertEqual(covered, .uncertain)
        XCTAssertTrue(manager.schedules.isEmpty)
    }

    @MainActor
    func testFailedScheduleWithUnknownInventoryReportsUncertainty() async {
        let manager = AlarmManagerBoundary()
        manager.scheduleError = true
        manager.listingFailsAfterSchedule = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: FocusRun(startedAt: date, resumedAt: date))

        XCTAssertEqual(covered, .uncertain)
        XCTAssertEqual(manager.schedules.count, 1)
    }

    @MainActor
    func testScheduleErrorWithVerifiedMatchingAlarmReportsCoverage() async {
        let manager = AlarmManagerBoundary()
        manager.scheduleErrorAfterCreation = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.records.map(\.id), [run.id])
    }

    @MainActor
    func testScheduleErrorWithUnexpectedAlarmReportsUncertainty() async {
        let manager = AlarmManagerBoundary()
        manager.scheduleErrorAfterCreation = true
        manager.createdDeadlineOffset = 10
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: FocusRun(startedAt: date, resumedAt: date))

        XCTAssertEqual(covered, .uncertain)
    }

    @MainActor
    func testPauseCancellationFailureReportsUncertainty() async {
        let manager = AlarmManagerBoundary()
        let run = FocusRun(startedAt: date, progressSeconds: 10)
        manager.records = [TimerAlarmRecord(id: run.id, deadline: date.addingTimeInterval(300), state: .scheduled)]
        manager.cancellationErrors = [run.id]
        let alarm = TimerAlarm(manager: manager, now: { self.date })

        let covered = await alarm.synchronize(run: run)

        XCTAssertEqual(covered, .uncertain)
        XCTAssertEqual(manager.records.map(\.id), [run.id])
    }

    @MainActor
    func testPermissionPromptDoesNotExtendTheDeadline() async {
        let manager = AlarmManagerBoundary()
        manager.authorizationState = .notDetermined
        var now = date
        manager.onPermission = { now = now.addingTimeInterval(20) }
        let alarm = TimerAlarm(manager: manager, now: { now })

        let covered = await alarm.synchronize(
            run: FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date),
            requestPermission: true,
        )

        XCTAssertEqual(covered, .scheduled)
        XCTAssertEqual(manager.records.first?.deadline, date.addingTimeInterval(300))
    }

    @MainActor
    func testPauseDuringPermissionPromptPreventsScheduling() async {
        let manager = AlarmManagerBoundary()
        manager.authorizationState = .notDetermined
        manager.deferPermission = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, resumedAt: date)
        let started = AsyncStream<Void>.makeStream()
        manager.onPermission = { started.continuation.yield(()) }
        let first = Task { await alarm.synchronize(run: run, requestPermission: true) }
        for await _ in started.stream { break }

        run.resumedAt = nil
        let queued = AsyncStream<Void>.makeStream()
        let pause = Task {
            queued.continuation.yield(())
            return await alarm.synchronize(run: run)
        }
        for await _ in queued.stream { break }
        manager.permissionContinuation?.resume(returning: .authorized)

        let firstCovered = await first.value
        let pauseCovered = await pause.value
        XCTAssertEqual(firstCovered, .unavailable)
        XCTAssertEqual(pauseCovered, .unavailable)
        XCTAssertTrue(manager.schedules.isEmpty)
    }

    @MainActor
    func testPauseDuringSchedulingCancelsTheLateAlarm() async {
        let manager = AlarmManagerBoundary()
        manager.deferSchedule = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        var run = FocusRun(startedAt: date, resumedAt: date)
        let started = AsyncStream<Void>.makeStream()
        manager.onSchedule = { started.continuation.yield(()) }
        let first = Task { await alarm.synchronize(run: run) }
        for await _ in started.stream { break }

        run.resumedAt = nil
        let queued = AsyncStream<Void>.makeStream()
        let pause = Task {
            queued.continuation.yield(())
            return await alarm.synchronize(run: run)
        }
        for await _ in queued.stream { break }
        manager.scheduleContinuation?.resume()

        let firstCovered = await first.value
        let pauseCovered = await pause.value
        XCTAssertEqual(firstCovered, .unavailable)
        XCTAssertEqual(pauseCovered, .unavailable)
        XCTAssertEqual(manager.cancellations, [run.id])
        XCTAssertTrue(manager.records.isEmpty)
    }

    @MainActor
    func testQueuedReplacementWaitsForItsAlarmAndReportsCoverage() async {
        let manager = AlarmManagerBoundary()
        manager.deferSchedule = true
        let alarm = TimerAlarm(manager: manager, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date)
        let replacement = FocusRun(startedAt: date, goalSeconds: 600, resumedAt: date)
        let started = AsyncStream<Void>.makeStream()
        manager.onSchedule = { started.continuation.yield(()) }
        let first = Task { await alarm.synchronize(run: run) }
        for await _ in started.stream { break }

        let queued = AsyncStream<Void>.makeStream()
        var replacementReturned = false
        let next = Task {
            queued.continuation.yield(())
            let result = await alarm.synchronize(run: replacement)
            replacementReturned = true
            return result
        }
        for await _ in queued.stream { break }
        XCTAssertFalse(replacementReturned)
        manager.deferSchedule = false
        manager.scheduleContinuation?.resume()

        let firstCovered = await first.value
        let nextCovered = await next.value
        XCTAssertEqual(firstCovered, .unavailable)
        XCTAssertEqual(nextCovered, .scheduled)
        XCTAssertEqual(manager.cancellations, [run.id])
        XCTAssertEqual(manager.records.map(\.id), [replacement.id])
        XCTAssertEqual(manager.records.first?.deadline, date.addingTimeInterval(600))
    }
}

@MainActor
private final class AlarmManagerBoundary: TimerAlarmManager {
    var authorizationState = TimerAlarmAuthorization.authorized
    var permissionResult = TimerAlarmAuthorization.authorized
    var permissionError = false
    var listingError = false
    var requiresAuthorizationForListing = false
    var listingFailsAfterSchedule = false
    var scheduleError = false
    var scheduleErrorAfterCreation = false
    var createdDeadlineOffset: TimeInterval = 0
    var cancellationErrors: Set<UUID> = []
    var authorizationRequests = 0
    var records: [TimerAlarmRecord] = []
    var schedules: [(id: UUID, deadline: Date)] = []
    var cancellations: [UUID] = []
    var onPermission: (() -> Void)?
    var onSchedule: (() -> Void)?
    var deferPermission = false
    var deferSchedule = false
    var permissionContinuation: CheckedContinuation<TimerAlarmAuthorization, Never>?
    var scheduleContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> TimerAlarmAuthorization {
        authorizationRequests += 1
        if deferPermission {
            authorizationState = await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                onPermission?()
            }
            return authorizationState
        }
        onPermission?()
        if permissionError { throw BoundaryError.failed }
        authorizationState = permissionResult
        return authorizationState
    }

    func alarms() throws -> [TimerAlarmRecord] {
        if listingError || (requiresAuthorizationForListing && authorizationState != .authorized) {
            throw BoundaryError.failed
        }
        return records
    }

    func schedule(id: UUID, deadline: Date, runID: UUID, phase: TimerAlarmPhase) async throws {
        schedules.append((id, deadline))
        if deferSchedule {
            await withCheckedContinuation { continuation in
                scheduleContinuation = continuation
                onSchedule?()
            }
        }
        if listingFailsAfterSchedule { listingError = true }
        if scheduleError { throw BoundaryError.failed }
        records.removeAll { $0.id == id }
        records.append(TimerAlarmRecord(id: id, deadline: deadline.addingTimeInterval(createdDeadlineOffset), state: .scheduled))
        if scheduleErrorAfterCreation { throw BoundaryError.failed }
    }

    func cancel(id: UUID) throws {
        cancellations.append(id)
        if cancellationErrors.contains(id) { throw BoundaryError.failed }
        records.removeAll { $0.id == id }
    }

    private enum BoundaryError: Error {
        case failed
    }
}
