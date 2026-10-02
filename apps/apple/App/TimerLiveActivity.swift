import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import UIKit
#endif

nonisolated struct TimerActivityRecord: Equatable {
    let id: String
    let attributes: TimerActivityAttributes
    let state: TimerActivityAttributes.ContentState
    let isActive: Bool
}

@MainActor
protocol TimerActivityClient: AnyObject {
    var activities: [TimerActivityRecord] { get }
    var canRequest: Bool { get }

    func request(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState) throws
    func update(id: String, state: TimerActivityAttributes.ContentState) async
    func end(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?) async
}

@MainActor
final class TimerLiveActivity {
    private let client: any TimerActivityClient
    private let now: () -> Date
    private var latestRun: FocusRun?
    private var creationRunID: UUID?
    private var finishedRunIDs = Set<UUID>()
    private var generation = 0
    private var isSynchronizing = false

    convenience init() {
        self.init(client: SystemTimerActivityClient())
    }

    init(client: any TimerActivityClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    func synchronize(run: FocusRun, userInitiated: Bool = false) async {
        guard !finishedRunIDs.contains(run.id) else { return }
        if latestRun?.id != run.id || !run.isRunning || run.isComplete(at: now()) {
            creationRunID = nil
        }
        if userInitiated, run.isRunning, !run.isComplete(at: now()) {
            creationRunID = run.id
        }
        latestRun = run
        generation += 1

        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        while let run = latestRun {
            let currentGeneration = generation
            await reconcile(run: run, generation: currentGeneration)
            guard currentGeneration != generation else { return }
        }
    }

    func finish(runID: UUID) async {
        finishedRunIDs.insert(runID)
        if latestRun?.id == runID {
            latestRun = nil
            creationRunID = nil
        }
        generation += 1

        for activity in client.activities where activity.attributes.runID == runID {
            let state = TimerActivityAttributes.ContentState(
                deadline: nil,
                remainingSeconds: 0,
                isPaused: false,
                isComplete: true,
            )
            await client.end(id: activity.id, state: state, dismissalDate: nil)
        }
    }

    private func reconcile(run source: FocusRun, generation currentGeneration: Int) async {
        let run = source.autoResumed(at: now())
        guard !finishedRunIDs.contains(run.id) else { return }
        let activities = client.activities
        let matching = activities.first { $0.attributes.runID == run.id && $0.isActive }

        for activity in activities where activity.id != matching?.id {
            let retainsCompletedRun = activity.attributes.runID == run.id && !activity.isActive
            if !retainsCompletedRun {
                await client.end(id: activity.id, state: activity.state, dismissalDate: nil)
                guard currentGeneration == generation else { return }
            }
        }

        let date = now()
        let complete = run.isComplete(at: date)
        let state = TimerActivityAttributes.ContentState(
            deadline: run.isRunning && !complete ? date.addingTimeInterval(run.remaining(at: date)) : nil,
            remainingSeconds: run.remaining(at: date),
            isPaused: !run.isRunning && !complete,
            isComplete: complete,
        )

        if let matching {
            creationRunID = nil
            if complete {
                await client.end(id: matching.id, state: state, dismissalDate: nil)
            } else if run.hasStarted {
                await client.update(id: matching.id, state: state)
            } else {
                await client.end(id: matching.id, state: state, dismissalDate: nil)
            }
        } else if run.isRunning, !complete, creationRunID == run.id, client.canRequest {
            creationRunID = nil
            let attributes = TimerActivityAttributes(runID: run.id, goalSeconds: run.goalSeconds, restSeconds: run.restSeconds)
            try? client.request(attributes: attributes, state: state)
        }
    }
}

@MainActor
private final class SystemTimerActivityClient: TimerActivityClient {
#if os(iOS) && canImport(ActivityKit)
    var activities: [TimerActivityRecord] {
        Activity<TimerActivityAttributes>.activities
            .filter { $0.activityState != .dismissed }
            .map { activity in
                TimerActivityRecord(
                    id: activity.id,
                    attributes: activity.attributes,
                    state: activity.content.state,
                    isActive: activity.activityState == .active || activity.activityState == .stale,
                )
            }
    }

    var canRequest: Bool {
        UIApplication.shared.applicationState == .active && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func request(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState) throws {
        _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: state.deadline),
            pushType: nil,
        )
    }

    func update(id: String, state: TimerActivityAttributes.ContentState) async {
        guard let activity = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: state.deadline))
    }

    func end(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?) async {
        guard let activity = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: dismissalDate.map { .after($0) } ?? .immediate,
        )
    }
#else
    var activities: [TimerActivityRecord] { [] }
    var canRequest: Bool { false }

    func request(attributes: TimerActivityAttributes, state: TimerActivityAttributes.ContentState) throws {}
    func update(id: String, state: TimerActivityAttributes.ContentState) async {}
    func end(id: String, state: TimerActivityAttributes.ContentState, dismissalDate: Date?) async {}
#endif
}
