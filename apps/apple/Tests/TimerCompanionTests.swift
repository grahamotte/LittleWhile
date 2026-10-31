import UserNotifications
import XCTest
@testable import LittleWhileCore

@MainActor
final class TimerCompanionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testPrefersSystemAlarmWithoutRequestingNotifications() async {
        let alarm = CompanionAlarmBoundary()
        alarm.authorizationState = .notDetermined
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        let run = FocusRun(startedAt: date, resumedAt: date)

        await companion.synchronize(run: run, userInitiated: true)

        XCTAssertEqual(alarm.permissionRequests, 1)
        XCTAssertEqual(alarm.records.first?.deadline, date.addingTimeInterval(1500))
        XCTAssertEqual(activity.activities.first?.attributes.runID, run.id)
        XCTAssertEqual(notification.permissionRequests, 0)
        XCTAssertNil(notification.pending)
    }

    func testDeniedAlarmFallsBackToNotificationAndKeepsLiveStatus() async {
        let alarm = CompanionAlarmBoundary()
        alarm.authorizationState = .denied
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        let run = FocusRun(startedAt: date, resumedAt: date)

        await companion.synchronize(run: run, userInitiated: true)

        XCTAssertTrue(alarm.records.isEmpty)
        XCTAssertEqual(notification.permissionRequests, 1)
        XCTAssertNotNil(notification.pending)
        XCTAssertEqual(activity.activities.count, 1)
    }

    func testRelaunchDoesNotPromptOrRecreateDismissedLiveActivity() async {
        let alarm = CompanionAlarmBoundary()
        alarm.authorizationState = .notDetermined
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)

        await companion.synchronize(run: FocusRun(startedAt: date, resumedAt: date))

        XCTAssertEqual(alarm.permissionRequests, 0)
        XCTAssertEqual(notification.permissionRequests, 0)
        XCTAssertTrue(activity.activities.isEmpty)
        XCTAssertNil(notification.pending)
    }

    func testPauseCancelsAlarmAndFreezesLiveActivity() async {
        let alarm = CompanionAlarmBoundary()
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        var run = FocusRun(startedAt: date, resumedAt: date)
        await companion.synchronize(run: run, userInitiated: true)
        run.progressSeconds = 30
        run.resumedAt = nil

        await companion.synchronize(run: run)

        XCTAssertTrue(alarm.records.isEmpty)
        XCTAssertNil(notification.pending)
        XCTAssertEqual(activity.activities.first?.state.isPaused, true)
        XCTAssertEqual(activity.activities.first?.state.remainingSeconds, 1470)
    }

    func testCompletionUpdatesLiveActivityWithoutSilencingAlarm() async {
        let alarm = CompanionAlarmBoundary()
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        var run = FocusRun(startedAt: date, resumedAt: date)
        await companion.synchronize(run: run, userInitiated: true)
        run.progressSeconds = 1500
        run.resumedAt = nil

        await companion.complete(run: run)

        XCTAssertEqual(alarm.records.count, 1)
        XCTAssertEqual(activity.ended.last?.state.isComplete, true)
        XCTAssertNil(notification.pending)
    }

    func testReplacingRunRemovesOldAlarmAndActivity() async {
        let alarm = CompanionAlarmBoundary()
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        await companion.synchronize(run: FocusRun(startedAt: date, resumedAt: date), userInitiated: true)

        await companion.synchronize(run: FocusRun())

        XCTAssertTrue(alarm.records.isEmpty)
        XCTAssertTrue(activity.activities.isEmpty)
        XCTAssertNil(notification.pending)
    }

    func testPauseDuringAlarmSchedulingCannotLeaveAlarmOrFallback() async {
        let alarm = CompanionAlarmBoundary()
        alarm.deferSchedule = true
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        let started = AsyncStream<Void>.makeStream()
        alarm.onSchedule = { started.continuation.yield(()) }
        var run = FocusRun(startedAt: date, resumedAt: date)
        let running = run
        let first = Task { await companion.synchronize(run: running, userInitiated: true) }
        for await _ in started.stream { break }
        run.progressSeconds = 10
        run.resumedAt = nil
        let paused = run
        let pauseProcessed = AsyncStream<Void>.makeStream()
        activity.onUpdate = { pauseProcessed.continuation.yield(()) }
        let second = Task { await companion.synchronize(run: paused) }
        for await _ in pauseProcessed.stream { break }
        alarm.continuation?.resume()
        await first.value
        await second.value

        XCTAssertTrue(alarm.records.isEmpty)
        XCTAssertNil(notification.pending)
        XCTAssertEqual(activity.activities.first?.state.isPaused, true)
    }

    func testAlarmCancellationDoesNotWaitForLiveActivityUpdate() async {
        let alarm = CompanionAlarmBoundary()
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)
        var run = FocusRun(startedAt: date, resumedAt: date)
        await companion.synchronize(run: run, userInitiated: true)
        run.resumedAt = nil
        run.progressSeconds = 20
        let paused = run
        activity.deferUpdate = true
        let canceled = AsyncStream<Void>.makeStream()
        alarm.onCancel = { canceled.continuation.yield(()) }
        let updating = AsyncStream<Void>.makeStream()
        activity.onUpdate = { updating.continuation.yield(()) }

        let pause = Task { await companion.synchronize(run: paused) }
        for await _ in updating.stream { break }
        for await _ in canceled.stream { break }

        XCTAssertTrue(alarm.records.isEmpty)
        activity.updateContinuation?.resume()
        await pause.value
        XCTAssertNil(notification.pending)
    }

    func testUnknownAlarmStateDoesNotRiskADuplicateSoundAndReportsTheIssue() async {
        let alarm = CompanionAlarmBoundary()
        alarm.inventoryUnavailable = true
        let activity = CompanionActivityBoundary()
        let notification = CompanionNotificationBoundary()
        let companion = makeCompanion(alarm, activity, notification)

        await companion.synchronize(run: FocusRun(startedAt: date, resumedAt: date), userInitiated: true)

        XCTAssertNil(notification.pending)
        XCTAssertEqual(notification.permissionRequests, 0)
        XCTAssertNotNil(companion.alarmIssue)

        await companion.synchronize(run: FocusRun())
        XCTAssertNil(companion.alarmIssue)
    }

    private func makeCompanion(
        _ alarm: CompanionAlarmBoundary,
        _ activity: CompanionActivityBoundary,
        _ notification: CompanionNotificationBoundary,
    ) -> TimerCompanion {
        TimerCompanion(
            alarms: TimerAlarm(manager: alarm, now: { self.date }),
            liveActivity: TimerLiveActivity(client: activity, now: { self.date }),
            notifications: CompletionAlerts(center: notification, now: { self.date }),
        )
    }
}

@MainActor
private final class CompanionAlarmBoundary: TimerAlarmManager {
    var authorizationState = TimerAlarmAuthorization.authorized
    var records: [TimerAlarmRecord] = []
    var permissionRequests = 0
    var deferSchedule = false
    var inventoryUnavailable = false
    var onSchedule: (() -> Void)?
    var onCancel: (() -> Void)?
    var continuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> TimerAlarmAuthorization {
        permissionRequests += 1
        authorizationState = .authorized
        return .authorized
    }

    func alarms() throws -> [TimerAlarmRecord] {
        if inventoryUnavailable { throw BoundaryError.unavailable }
        return records
    }

    func schedule(id: UUID, deadline: Date, runID: UUID, phase: TimerAlarmPhase) async throws {
        if deferSchedule {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onSchedule?()
            }
        }
        records.append(TimerAlarmRecord(id: id, deadline: deadline, state: .scheduled))
    }

    func cancel(id: UUID) throws {
        records.removeAll { $0.id == id }
        onCancel?()
    }

    private enum BoundaryError: Error {
        case unavailable
    }
}

@MainActor
private final class CompanionActivityBoundary: TimerActivityClient {
    var activities: [TimerActivityRecord] = []
    var ended: [TimerActivityRecord] = []
    var canRequest = true
    var onUpdate: (() -> Void)?
    var deferUpdate = false
    var updateContinuation: CheckedContinuation<Void, Never>?

    func request(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState) throws {
        activities.append(TimerActivityRecord(id: attributes.runID.uuidString, attributes: attributes, state: state, isActive: true))
    }

    func update(id: String, state: TimerActivityAttributes.ContentState) async {
        if deferUpdate {
            await withCheckedContinuation { continuation in
                updateContinuation = continuation
                onUpdate?()
            }
        }
        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index] = TimerActivityRecord(id: id, attributes: activities[index].attributes, state: state, isActive: true)
        }
        if !deferUpdate { onUpdate?() }
    }

    func end(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?) async {
        if let record = activities.first(where: { $0.id == id }) {
            ended.append(TimerActivityRecord(id: id, attributes: record.attributes, state: state, isActive: false))
        }
        activities.removeAll { $0.id == id }
    }
}

@MainActor
private final class CompanionNotificationBoundary: CompletionNotificationCenter {
    weak var delegate: (any UNUserNotificationCenterDelegate)?
    var permissionRequests = 0
    var pending: UNNotificationRequest?
    private var status = UNAuthorizationStatus.notDetermined

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        status = .authorized
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        if let pending, identifiers.contains(pending.identifier) {
            self.pending = nil
        }
    }
}
