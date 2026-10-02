import XCTest
@testable import App

@MainActor
final class TimerLiveActivityTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testExplicitStartCreatesActivityWithStableIdentityAndExactDeadline() async throws {
        let client = ActivityBoundary()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let run = FocusRun(
            createdAt: date.addingTimeInterval(-100),
            startedAt: date.addingTimeInterval(-60),
            progressSeconds: 12.25,
            goalSeconds: 300,
            resumedAt: date.addingTimeInterval(-10),
        )

        await coordinator.synchronize(run: run, userInitiated: true)

        let activity = try XCTUnwrap(client.activities.first)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(activity.attributes.runID, run.id)
        XCTAssertEqual(activity.attributes.goalSeconds, 300)
        XCTAssertEqual(activity.state.remainingSeconds, 277.75)
        XCTAssertEqual(activity.state.deadline, date.addingTimeInterval(277.75))
        XCTAssertFalse(activity.state.isPaused)
        XCTAssertFalse(activity.state.isComplete)
    }

    func testLoopingRunCreatesLoopingActivityWithCurrentCycleDeadline() async throws {
        let client = ActivityBoundary()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let run = FocusRun(startedAt: date, progressSeconds: 400, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)

        await coordinator.synchronize(run: run, userInitiated: true)

        let activity = try XCTUnwrap(client.activities.first)
        XCTAssertTrue(activity.attributes.loops)
        XCTAssertEqual(activity.attributes.restSeconds, 60)
        XCTAssertEqual(activity.state.remainingSeconds, 320)
        XCTAssertEqual(activity.state.deadline, date.addingTimeInterval(320))
        XCTAssertFalse(activity.state.isComplete)
    }

    func testStoppingALoopEndsItsActivity() async throws {
        let client = ActivityBoundary()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)
        await coordinator.synchronize(run: run, userInitiated: true)

        await coordinator.synchronize(run: FocusRun(createdAt: date, goalSeconds: 300, restSeconds: 60, loops: true))

        XCTAssertEqual(client.endings.count, 1)
        XCTAssertTrue(client.activities.isEmpty)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testUnstartedPausedAndCompletedRunsDoNotCreateActivities() async {
        for run in [
            FocusRun(createdAt: date),
            FocusRun(createdAt: date, startedAt: date, progressSeconds: 20),
            FocusRun(createdAt: date, startedAt: date, progressSeconds: 1_500),
        ] {
            let client = ActivityBoundary()
            let coordinator = TimerLiveActivity(client: client, now: { self.date })

            await coordinator.synchronize(run: run, userInitiated: true)

            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertTrue(client.activities.isEmpty)
        }
    }

    func testForegroundReconciliationDoesNotRecreateAnAbsentActivity() async {
        let client = ActivityBoundary()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let run = runningRun()

        await coordinator.synchronize(run: run)
        await coordinator.synchronize(run: run)

        XCTAssertTrue(client.requests.isEmpty)
    }

    func testExistingActivityIsRecoveredAfterRelaunchWithoutRequestingAnother() async throws {
        let client = ActivityBoundary()
        let run = runningRun()
        let original = record(run: run)
        client.activities = [original]
        let coordinator = TimerLiveActivity(client: client, now: { self.date.addingTimeInterval(45.25) })

        await coordinator.synchronize(run: run)

        let activity = try XCTUnwrap(client.activities.first)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(client.updates.count, 1)
        XCTAssertEqual(activity.id, original.id)
        XCTAssertEqual(activity.state.remainingSeconds, 1_454.75)
        XCTAssertEqual(activity.state.deadline, date.addingTimeInterval(1_500))
    }

    func testPauseFreezesExistingActivityWithoutADeadline() async throws {
        let client = ActivityBoundary()
        let run = runningRun()
        client.activities = [record(run: run)]
        let coordinator = TimerLiveActivity(client: client, now: { self.date.addingTimeInterval(50) })
        var paused = run
        paused.progressSeconds = 17.125
        paused.resumedAt = nil

        await coordinator.synchronize(run: paused)

        let state = try XCTUnwrap(client.activities.first?.state)
        XCTAssertEqual(state.remainingSeconds, 1_482.875)
        XCTAssertNil(state.deadline)
        XCTAssertTrue(state.isPaused)
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testResumeUpdatesSameActivityWithNewDeadline() async throws {
        let client = ActivityBoundary()
        let run = runningRun()
        client.activities = [record(run: run)]
        let identifier = client.activities[0].id
        let coordinator = TimerLiveActivity(client: client, now: { self.date.addingTimeInterval(100) })
        var resumed = run
        resumed.progressSeconds = 30.5
        resumed.resumedAt = date.addingTimeInterval(100)

        await coordinator.synchronize(run: resumed, userInitiated: true)

        let activity = try XCTUnwrap(client.activities.first)
        XCTAssertEqual(activity.id, identifier)
        XCTAssertEqual(activity.state.deadline, date.addingTimeInterval(1_569.5))
        XCTAssertFalse(activity.state.isPaused)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testCompletionEndsActivityImmediatelyWithFinalState() async throws {
        let client = ActivityBoundary()
        let run = runningRun()
        client.activities = [record(run: run)]
        let completeAt = date.addingTimeInterval(1_600)
        let coordinator = TimerLiveActivity(client: client, now: { completeAt })

        await coordinator.synchronize(run: run)

        let ending = try XCTUnwrap(client.endings.first)
        XCTAssertTrue(ending.state.isComplete)
        XCTAssertFalse(ending.state.isPaused)
        XCTAssertEqual(ending.state.remainingSeconds, 0)
        XCTAssertNil(ending.state.deadline)
        XCTAssertNil(ending.dismissalDate)
        XCTAssertTrue(client.activities.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testRepeatedCompletedReconciliationDoesNotEndAgain() async {
        let client = ActivityBoundary()
        let run = runningRun()
        client.activities = [record(run: run)]
        var now = date.addingTimeInterval(1_500)
        let coordinator = TimerLiveActivity(client: client, now: { now })

        await coordinator.synchronize(run: run)
        now = now.addingTimeInterval(30)
        await coordinator.synchronize(run: run)

        XCTAssertEqual(client.endings.count, 1)
        XCTAssertNil(client.endings[0].dismissalDate)
    }

    func testNewReadyRunImmediatelyEndsPriorActivity() async throws {
        let client = ActivityBoundary()
        let oldRun = runningRun()
        let oldActivity = record(run: oldRun)
        client.activities = [oldActivity]
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.synchronize(run: FocusRun(createdAt: date))

        XCTAssertEqual(client.endings.count, 1)
        XCTAssertEqual(client.endings[0].id, oldActivity.id)
        XCTAssertNil(client.endings[0].dismissalDate)
        XCTAssertTrue(client.activities.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testNewRunRemovesCompletedActivityStillOnLockScreen() async {
        let client = ActivityBoundary()
        let oldRun = runningRun()
        client.activities = [record(run: oldRun, isActive: false)]
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.synchronize(run: runningRun(), userInitiated: true)

        XCTAssertEqual(client.endings.count, 1)
        XCTAssertNil(client.endings[0].dismissalDate)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.activities.count, 1)
    }

    func testReconciliationEndsDuplicateAndUnrelatedActivities() async {
        let client = ActivityBoundary()
        let run = runningRun()
        let kept = record(run: run)
        client.activities = [kept, record(run: run), record(run: runningRun())]
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.synchronize(run: run)

        XCTAssertEqual(client.activities.count, 1)
        XCTAssertEqual(client.activities[0].id, kept.id)
        XCTAssertEqual(client.endings.count, 2)
        XCTAssertTrue(client.endings.allSatisfy { $0.dismissalDate == nil })
    }

    func testSystemDismissalIsRespectedUntilExplicitResume() async {
        let client = ActivityBoundary()
        let run = runningRun()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        await coordinator.synchronize(run: run, userInitiated: true)
        await coordinator.synchronize(run: run, userInitiated: true)
        client.activities = []

        await coordinator.synchronize(run: run)
        XCTAssertEqual(client.requests.count, 1)

        await coordinator.synchronize(run: run, userInitiated: true)
        XCTAssertEqual(client.requests.count, 2)
    }

    func testCreationWaitsUntilForegroundAndAuthorizationAllowIt() async {
        let client = ActivityBoundary()
        client.canRequest = false
        let run = runningRun()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.synchronize(run: run, userInitiated: true)
        XCTAssertTrue(client.requests.isEmpty)

        client.canRequest = true
        await coordinator.synchronize(run: run)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testPauseClearsDeferredCreationIntent() async {
        let client = ActivityBoundary()
        client.canRequest = false
        let run = runningRun()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        await coordinator.synchronize(run: run, userInitiated: true)
        var paused = run
        paused.resumedAt = nil
        await coordinator.synchronize(run: paused)
        client.canRequest = true

        await coordinator.synchronize(run: run)

        XCTAssertTrue(client.requests.isEmpty)
    }

    func testRequestFailureDoesNotRetryUntilAnotherExplicitStart() async {
        let client = ActivityBoundary()
        client.requestFails = true
        let run = runningRun()
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.synchronize(run: run, userInitiated: true)
        client.requestFails = false
        await coordinator.synchronize(run: run)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.activities.isEmpty)

        await coordinator.synchronize(run: run, userInitiated: true)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.activities.count, 1)
    }

    func testFinishImmediatelyEndsOnlyMatchingRunWithCompleteState() async throws {
        let client = ActivityBoundary()
        let run = runningRun()
        let unrelated = record(run: runningRun())
        client.activities = [record(run: run), unrelated]
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.finish(runID: run.id)

        let ending = try XCTUnwrap(client.endings.first)
        XCTAssertNil(ending.dismissalDate)
        XCTAssertTrue(ending.state.isComplete)
        XCTAssertFalse(ending.state.isPaused)
        XCTAssertEqual(ending.state.remainingSeconds, 0)
        XCTAssertNil(ending.state.deadline)
        XCTAssertEqual(client.activities, [unrelated])
    }

    func testFinishWithUnknownRunDoesNotChangeOtherActivities() async {
        let client = ActivityBoundary()
        client.activities = [record(run: runningRun())]
        let original = client.activities
        let coordinator = TimerLiveActivity(client: client, now: { self.date })

        await coordinator.finish(runID: UUID())

        XCTAssertEqual(client.activities, original)
        XCTAssertTrue(client.endings.isEmpty)
    }

    func testNewRunSupersedesAnInFlightPauseUpdate() async {
        let client = ActivityBoundary()
        let oldRun = runningRun()
        client.activities = [record(run: oldRun)]
        client.deferUpdate = true
        let started = AsyncStream<Void>.makeStream()
        client.onUpdate = { started.continuation.yield(()) }
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        var paused = oldRun
        paused.resumedAt = nil
        paused.progressSeconds = 20
        let synchronization = Task { await coordinator.synchronize(run: paused) }
        for await _ in started.stream { break }
        let newRun = runningRun()

        await coordinator.synchronize(run: newRun, userInitiated: true)
        client.deferredUpdate?.resume()
        await synchronization.value

        XCTAssertEqual(client.activities.count, 1)
        XCTAssertEqual(client.activities[0].attributes.runID, newRun.id)
        XCTAssertFalse(client.activities[0].state.isPaused)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testNewestRunWinsWhilePriorActivityIsEnding() async {
        let client = ActivityBoundary()
        client.activities = [record(run: runningRun())]
        client.deferEnd = true
        let started = AsyncStream<Void>.makeStream()
        client.onEnd = { started.continuation.yield(()) }
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let intermediate = runningRun()
        let synchronization = Task { await coordinator.synchronize(run: intermediate, userInitiated: true) }
        for await _ in started.stream { break }
        let newest = runningRun()

        await coordinator.synchronize(run: newest, userInitiated: true)
        client.deferredEnd?.resume()
        await synchronization.value

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.activities.count, 1)
        XCTAssertEqual(client.activities[0].attributes.runID, newest.id)
    }

    func testForegroundSynchronizationPreservesInFlightExplicitCreationIntent() async {
        let client = ActivityBoundary()
        client.activities = [record(run: runningRun())]
        client.deferEnd = true
        let started = AsyncStream<Void>.makeStream()
        client.onEnd = { started.continuation.yield(()) }
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let newRun = runningRun()
        let synchronization = Task { await coordinator.synchronize(run: newRun, userInitiated: true) }
        for await _ in started.stream { break }

        await coordinator.synchronize(run: newRun)
        client.deferredEnd?.resume()
        await synchronization.value

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.activities[0].attributes.runID, newRun.id)
    }

    func testFinishDuringAnInFlightUpdateCannotReactivateRun() async {
        let client = ActivityBoundary()
        let run = runningRun()
        client.activities = [record(run: run)]
        client.deferUpdate = true
        let started = AsyncStream<Void>.makeStream()
        client.onUpdate = { started.continuation.yield(()) }
        let coordinator = TimerLiveActivity(client: client, now: { self.date })
        let synchronization = Task { await coordinator.synchronize(run: run) }
        for await _ in started.stream { break }

        await coordinator.finish(runID: run.id)
        client.deferredUpdate?.resume()
        await synchronization.value
        await coordinator.synchronize(run: run, userInitiated: true)

        XCTAssertTrue(client.activities.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    private func runningRun() -> FocusRun {
        FocusRun(createdAt: date, startedAt: date, resumedAt: date)
    }

    private func record(run: FocusRun, isActive: Bool = true) -> TimerActivityRecord {
        TimerActivityRecord(
            id: UUID().uuidString,
            attributes: TimerActivityAttributes(runID: run.id, goalSeconds: run.goalSeconds),
            state: TimerActivityAttributes.ContentState(
                deadline: date.addingTimeInterval(run.remaining(at: date)),
                remainingSeconds: run.remaining(at: date),
                isPaused: false,
                isComplete: false,
            ),
            isActive: isActive,
        )
    }
}

@MainActor
private final class ActivityBoundary: TimerActivityClient {
    var activities: [TimerActivityRecord] = []
    var canRequest = true
    var requestFails = false
    var requests: [(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState)] = []
    var updates: [(id: String, state: TimerActivityAttributes.ContentState)] = []
    var endings: [(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?)] = []
    var deferUpdate = false
    var deferEnd = false
    var onUpdate: (() -> Void)?
    var onEnd: (() -> Void)?
    var deferredUpdate: CheckedContinuation<Void, Never>?
    var deferredEnd: CheckedContinuation<Void, Never>?

    func request(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState) throws {
        requests.append((attributes, state))
        if requestFails { throw BoundaryError.failed }
        activities.append(TimerActivityRecord(id: UUID().uuidString, attributes: attributes, state: state, isActive: true))
    }

    func update(id: String, state: TimerActivityAttributes.ContentState) async {
        updates.append((id, state))
        if deferUpdate {
            await withCheckedContinuation { continuation in
                deferredUpdate = continuation
                onUpdate?()
            }
        }
        guard let index = activities.firstIndex(where: { $0.id == id && $0.isActive }) else { return }
        let existing = activities[index]
        activities[index] = TimerActivityRecord(id: id, attributes: existing.attributes, state: state, isActive: true)
    }

    func end(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?) async {
        endings.append((id, state, dismissalDate))
        if deferEnd {
            await withCheckedContinuation { continuation in
                deferredEnd = continuation
                onEnd?()
            }
        }
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        let existing = activities[index]
        if dismissalDate == nil {
            activities.remove(at: index)
        } else {
            activities[index] = TimerActivityRecord(id: id, attributes: existing.attributes, state: state, isActive: false)
        }
    }

    private enum BoundaryError: Error {
        case failed
    }
}
