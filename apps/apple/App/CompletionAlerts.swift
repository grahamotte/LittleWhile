import Foundation
import UserNotifications

@MainActor
protocol CompletionNotificationCenter: AnyObject {
    var delegate: (any UNUserNotificationCenterDelegate)? { get set }

    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
private final class SystemCompletionNotificationCenter: CompletionNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    var delegate: (any UNUserNotificationCenterDelegate)? {
        get { center.delegate }
        set { center.delegate = newValue }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@MainActor
final class CompletionAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let notificationIdentifier = "littlewhile.timer.complete"
    static let focusIdentifier = "littlewhile.timer.focus"
    static let nextFocusIdentifier = "littlewhile.timer.focus.next"
    static let nextNotificationIdentifier = "littlewhile.timer.complete.next"

    private static let identifiers = [focusIdentifier, notificationIdentifier, nextFocusIdentifier, nextNotificationIdentifier]

    private let center: any CompletionNotificationCenter
    private let now: () -> Date
    private var latestRun: FocusRun?
    private var isEnabled = true
    private var generation = 0
    private var isSynchronizing = false
    private var shouldRequestPermission = false

    convenience override init() {
        self.init(center: SystemCompletionNotificationCenter())
    }

    init(center: any CompletionNotificationCenter, now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
        super.init()
        center.delegate = self
    }

    func synchronize(run: FocusRun, requestPermission: Bool = false, enabled: Bool = true) async {
        latestRun = run
        isEnabled = enabled
        generation += 1
        shouldRequestPermission = shouldRequestPermission || requestPermission
        center.removePendingNotificationRequests(withIdentifiers: Self.identifiers)

        guard !isSynchronizing else { return }

        isSynchronizing = true
        defer { isSynchronizing = false }

        while let run = latestRun {
            let currentGeneration = generation
            await schedule(run: run, generation: currentGeneration)
            guard currentGeneration != generation else { return }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func schedule(run source: FocusRun, generation currentGeneration: Int) async {
        let run = source.resumingAtPauseDeadline()
        center.removePendingNotificationRequests(withIdentifiers: Self.identifiers)
        guard isEnabled, run.isRunning, run.remaining(at: now()) > 0 else { return }

        let status = await center.authorizationStatus()
        guard currentGeneration == generation else { return }

        let isAuthorized: Bool
        switch status {
        case .authorized, .provisional:
            shouldRequestPermission = false
            isAuthorized = true
#if os(iOS)
        case .ephemeral:
            shouldRequestPermission = false
            isAuthorized = true
#endif
        case .notDetermined where shouldRequestPermission:
            shouldRequestPermission = false
            isAuthorized = (try? await center.requestAuthorization()) == true
        default:
            shouldRequestPermission = false
            isAuthorized = false
        }

        guard currentGeneration == generation, isAuthorized else { return }

        let sampledAt = now()
        let delay = run.resumeDelay(at: sampledAt)
        let totalRemaining = run.remaining(at: sampledAt) + delay
        guard totalRemaining > 0 else { return }

        var requests: [(identifier: String, content: UNMutableNotificationContent, interval: TimeInterval)] = []
        if run.restSeconds > 0, run.focusRemaining(at: sampledAt) > 0 {
            requests.append((Self.focusIdentifier, focusContent(), run.focusRemaining(at: sampledAt) + delay))
        }
        requests.append((Self.notificationIdentifier, cycleContent(run: run), totalRemaining))
        if run.loops {
            if run.restSeconds > 0 {
                requests.append((Self.nextFocusIdentifier, focusContent(), totalRemaining + TimeInterval(run.goalSeconds)))
            }
            requests.append((Self.nextNotificationIdentifier, cycleContent(run: run), totalRemaining + TimeInterval(run.totalSeconds)))
        }

        for request in requests {
            guard currentGeneration == generation else { return }
            try? await center.add(UNNotificationRequest(
                identifier: request.identifier,
                content: request.content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.interval), repeats: false),
            ))
        }
    }

    private func focusContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Focus is up"
        content.body = "Time for a rest."
        content.sound = .default
        return content
    }

    private func cycleContent(run: FocusRun) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if run.loops {
            content.title = run.restSeconds > 0 ? "Rest is up" : "Focus is up"
            content.body = "Your next cycle has started."
        } else {
            content.title = "Time’s up"
            content.body = "A little while, well spent."
        }
        content.sound = .default
        return content
    }
}
