import UserNotifications
import XCTest
@testable import App

final class CompletionAlertsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testSchedulesRemainingTimeWithCompletionContent() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(
            startedAt: date.addingTimeInterval(-60),
            progressSeconds: 30,
            goalSeconds: 300,
            resumedAt: date.addingTimeInterval(-10),
        )

        await alerts.synchronize(run: run)

        let request = try? XCTUnwrap(center.pendingRequest)
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(request?.identifier, "littlewhile.timer.complete")
        XCTAssertEqual(request?.content.title, "Time’s up")
        XCTAssertEqual(request?.content.body, "A little while, well spent.")
        XCTAssertNotNil(request?.content.sound)
        XCTAssertEqual(trigger?.timeInterval, 260)
        XCTAssertEqual(trigger?.repeats, false)
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertTrue(center.delegate === alerts)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    @MainActor
    func testSchedulesFocusAndCompletionNotificationsForARestRun() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date)

        await alerts.synchronize(run: run)

        XCTAssertEqual(center.addedRequests.map(\.identifier), ["littlewhile.timer.focus", "littlewhile.timer.complete"])
        XCTAssertEqual(
            center.addedRequests.map { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval },
            [300, 360],
        )
        XCTAssertEqual(center.addedRequests[0].content.title, "Focus is up")
        XCTAssertEqual(center.addedRequests[1].content.title, "Time’s up")
    }

    @MainActor
    func testLoopingRunSchedulesTheNextCycle() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, goalSeconds: 300, restSeconds: 60, resumedAt: date, loops: true)

        await alerts.synchronize(run: run)

        XCTAssertEqual(
            center.addedRequests.map(\.identifier),
            ["littlewhile.timer.focus", "littlewhile.timer.complete", "littlewhile.timer.focus.next", "littlewhile.timer.complete.next"],
        )
        XCTAssertEqual(
            center.addedRequests.map { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval },
            [300, 360, 660, 720],
        )
        XCTAssertEqual(center.addedRequests.map(\.content.title), ["Focus is up", "Rest is up", "Focus is up", "Rest is up"])
    }

    @MainActor
    func testLoopingRunWithoutRestSchedulesEachFocusEnd() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, progressSeconds: 70, goalSeconds: 60, resumedAt: date, loops: true)

        await alerts.synchronize(run: run)

        XCTAssertEqual(center.addedRequests.map(\.identifier), ["littlewhile.timer.complete", "littlewhile.timer.complete.next"])
        XCTAssertEqual(
            center.addedRequests.map { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval },
            [50, 110],
        )
        XCTAssertEqual(center.addedRequests[0].content.title, "Focus is up")
        XCTAssertEqual(center.addedRequests[0].content.body, "Your next cycle has started.")
    }

    @MainActor
    func testPausedUnstartedAndCompleteRunsCancelPendingNotifications() async {
        for stoppedRun in [
            FocusRun(),
            FocusRun(startedAt: date, progressSeconds: 30),
            FocusRun(startedAt: date, goalSeconds: 60, resumedAt: date.addingTimeInterval(-60)),
        ] {
            let center = NotificationCenterBoundary()
            let alerts = CompletionAlerts(center: center, now: { self.date })
            await alerts.synchronize(run: FocusRun(startedAt: date, resumedAt: date))
            XCTAssertNotNil(center.pendingRequest)

            await alerts.synchronize(run: stoppedRun)

            XCTAssertNil(center.pendingRequest)
            XCTAssertEqual(
                center.removedIdentifiers.last,
                ["littlewhile.timer.focus", "littlewhile.timer.complete", "littlewhile.timer.focus.next", "littlewhile.timer.complete.next"],
            )
        }
    }

    @MainActor
    func testPermissionIsRequestedOnlyFromAnExplicitPlay() async {
        let center = NotificationCenterBoundary()
        center.status = .notDetermined
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        await alerts.synchronize(run: run)
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertNil(center.pendingRequest)

        await alerts.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertNotNil(center.pendingRequest)

        await alerts.synchronize(run: run, requestPermission: true)
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    @MainActor
    func testDeniedPermissionDoesNotScheduleOrAskAgain() async {
        let center = NotificationCenterBoundary()
        center.status = .notDetermined
        center.permissionGranted = false
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        await alerts.synchronize(run: run, requestPermission: true)
        await alerts.synchronize(run: run, requestPermission: true)

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertNil(center.pendingRequest)
        XCTAssertTrue(run.isRunning)
    }

    @MainActor
    func testProvisionalAuthorizationAllowsScheduling() async {
        let center = NotificationCenterBoundary()
        center.status = .provisional
        let alerts = CompletionAlerts(center: center, now: { self.date })

        await alerts.synchronize(run: FocusRun(startedAt: date, resumedAt: date))

        XCTAssertNotNil(center.pendingRequest)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    @MainActor
    func testNotificationFailuresDoNotBlockFutureScheduling() async {
        let center = NotificationCenterBoundary()
        center.status = .notDetermined
        center.permissionError = true
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)

        await alerts.synchronize(run: run, requestPermission: true)
        XCTAssertNil(center.pendingRequest)

        center.status = .authorized
        center.addError = true
        await alerts.synchronize(run: run)
        XCTAssertNil(center.pendingRequest)

        center.addError = false
        await alerts.synchronize(run: run)
        XCTAssertNotNil(center.pendingRequest)
    }

    @MainActor
    func testUsesTimeAfterPermissionAndSkipsAlreadyFinishedRuns() async {
        let center = NotificationCenterBoundary()
        center.status = .notDetermined
        var now = date
        center.onPermissionRequest = { now = now.addingTimeInterval(60) }
        let alerts = CompletionAlerts(center: center, now: { now })

        await alerts.synchronize(
            run: FocusRun(startedAt: date, goalSeconds: 60, resumedAt: date),
            requestPermission: true,
        )

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertNil(center.pendingRequest)
    }

    @MainActor
    func testSubsecondRemainderUsesValidNotificationInterval() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })

        await alerts.synchronize(
            run: FocusRun(startedAt: date, progressSeconds: 59.8, goalSeconds: 60, resumedAt: date),
        )

        XCTAssertEqual((center.pendingRequest?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 1)
    }

    @MainActor
    func testPauseWhileReadingPermissionPreventsScheduling() async {
        let center = NotificationCenterBoundary()
        center.deferStatus = true
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let started = AsyncStream<Void>.makeStream()
        center.onStatusRequest = { started.continuation.yield(()) }
        let synchronization = Task {
            await alerts.synchronize(run: FocusRun(startedAt: date, resumedAt: date))
        }
        for await _ in started.stream { break }

        await alerts.synchronize(run: FocusRun(startedAt: date, progressSeconds: 10))
        center.deferredStatus?.resume(returning: .authorized)
        await synchronization.value

        XCTAssertEqual(center.addedRequests.count, 0)
        XCTAssertNil(center.pendingRequest)
    }

    @MainActor
    func testPauseDuringAnInFlightAddRemovesItsLateNotification() async {
        let center = NotificationCenterBoundary()
        center.deferAdd = true
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let started = AsyncStream<Void>.makeStream()
        center.onAdd = { started.continuation.yield(()) }
        let synchronization = Task {
            await alerts.synchronize(run: FocusRun(startedAt: date, resumedAt: date))
        }
        for await _ in started.stream { break }

        await alerts.synchronize(run: FocusRun(startedAt: date, progressSeconds: 10))
        center.deferredAdd?.resume()
        await synchronization.value

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertNil(center.pendingRequest)
    }

    @MainActor
    func testNewRunReplacesAnInFlightNotification() async {
        let center = NotificationCenterBoundary()
        center.deferAdd = true
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let started = AsyncStream<Void>.makeStream()
        center.onAdd = { started.continuation.yield(()) }
        let synchronization = Task {
            await alerts.synchronize(run: FocusRun(startedAt: date, goalSeconds: 300, resumedAt: date))
        }
        for await _ in started.stream { break }

        await alerts.synchronize(run: FocusRun(startedAt: date, goalSeconds: 600, resumedAt: date))
        center.deferAdd = false
        center.deferredAdd?.resume()
        await synchronization.value

        XCTAssertEqual(center.addedRequests.count, 2)
        XCTAssertEqual((center.pendingRequest?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 600)
    }

    @MainActor
    func testSystemAlarmSuppressesFallbackNotificationAndPermissionRequest() async {
        let center = NotificationCenterBoundary()
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)
        await alerts.synchronize(run: run)
        XCTAssertNotNil(center.pendingRequest)

        center.status = .notDetermined
        await alerts.synchronize(run: run, requestPermission: true, enabled: false)

        XCTAssertNil(center.pendingRequest)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    @MainActor
    func testDisablingDuringInFlightAddRemovesLateFallback() async {
        let center = NotificationCenterBoundary()
        center.deferAdd = true
        let alerts = CompletionAlerts(center: center, now: { self.date })
        let run = FocusRun(startedAt: date, resumedAt: date)
        let started = AsyncStream<Void>.makeStream()
        center.onAdd = { started.continuation.yield(()) }
        let synchronization = Task { await alerts.synchronize(run: run) }
        for await _ in started.stream { break }

        await alerts.synchronize(run: run, enabled: false)
        center.deferredAdd?.resume()
        await synchronization.value

        XCTAssertNil(center.pendingRequest)
    }
}

@MainActor
private final class NotificationCenterBoundary: CompletionNotificationCenter {
    weak var delegate: (any UNUserNotificationCenterDelegate)?
    var status = UNAuthorizationStatus.authorized
    var permissionGranted = true
    var permissionError = false
    var addError = false
    var authorizationRequests = 0
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [[String]] = []
    var pendingRequest: UNNotificationRequest?
    var onPermissionRequest: (() -> Void)?
    var onStatusRequest: (() -> Void)?
    var onAdd: (() -> Void)?
    var deferStatus = false
    var deferAdd = false
    var deferredStatus: CheckedContinuation<UNAuthorizationStatus, Never>?
    var deferredAdd: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard deferStatus else { return status }
        return await withCheckedContinuation { continuation in
            deferredStatus = continuation
            onStatusRequest?()
        }
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        onPermissionRequest?()
        if permissionError { throw BoundaryError.failed }
        status = permissionGranted ? .authorized : .denied
        return permissionGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        if deferAdd {
            await withCheckedContinuation { continuation in
                deferredAdd = continuation
                onAdd?()
            }
        }
        if addError { throw BoundaryError.failed }
        pendingRequest = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        if let request = pendingRequest, identifiers.contains(request.identifier) {
            pendingRequest = nil
        }
    }

    private enum BoundaryError: Error {
        case failed
    }
}
