import Foundation

enum TimerAlarmCoverage: Equatable, Sendable {
    case scheduled
    case unavailable
    case uncertain
}

enum TimerAlarmAuthorization {
    case notDetermined
    case denied
    case authorized
}

enum TimerAlarmPhase: Equatable, Sendable {
    case focus
    case rest
}

struct TimerAlarmRecord {
    enum State {
        case scheduled
        case alerting
        case other
    }

    let id: UUID
    let deadline: Date?
    let state: State
}

@MainActor
protocol TimerAlarmManager: AnyObject {
    var authorizationState: TimerAlarmAuthorization { get }

    func requestAuthorization() async throws -> TimerAlarmAuthorization
    func alarms() throws -> [TimerAlarmRecord]
    func schedule(id: UUID, deadline: Date, runID: UUID, phase: TimerAlarmPhase) async throws
    func cancel(id: UUID) throws
}

@MainActor
final class TimerAlarm {
    private let manager: (any TimerAlarmManager)?
    private let now: () -> Date
    private var latestRun: FocusRun?
    private var generation = 0
    private var isSynchronizing = false
    private var shouldRequestPermission = false
    private var waiters: [(generation: Int, continuation: CheckedContinuation<TimerAlarmCoverage, Never>)] = []

    convenience init() {
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            self.init(manager: SystemTimerAlarmManager())
            return
        }
#endif
        self.init(manager: nil)
    }

    init(manager: (any TimerAlarmManager)?, now: @escaping () -> Date = Date.init) {
        self.manager = manager
        self.now = now
    }

    func synchronize(run: FocusRun, requestPermission: Bool = false) async -> TimerAlarmCoverage {
        latestRun = run
        generation += 1
        let requestedGeneration = generation
        shouldRequestPermission = shouldRequestPermission || requestPermission

        if isSynchronizing {
            return await withCheckedContinuation { continuation in
                waiters.append((requestedGeneration, continuation))
            }
        }

        isSynchronizing = true
        while let currentRun = latestRun {
            let currentGeneration = generation
            let covered = await reconcile(run: currentRun, generation: currentGeneration)
            guard currentGeneration == generation else { continue }

            isSynchronizing = false
            let finishedWaiters = waiters
            waiters.removeAll()
            for waiter in finishedWaiters {
                waiter.continuation.resume(returning: waiter.generation == currentGeneration ? covered : .unavailable)
            }
            return requestedGeneration == currentGeneration ? covered : .unavailable
        }

        isSynchronizing = false
        return .unavailable
    }

    private func reconcile(run: FocusRun, generation currentGeneration: Int) async -> TimerAlarmCoverage {
        guard let manager else { return .unavailable }
        let run = run.resumingAtPauseDeadline()

        var authorization = manager.authorizationState
        let canPrompt = shouldRequestPermission
        var promptCompleted = false
        if run.isRunning, !run.isComplete(at: now()),
           authorization == .notDetermined, canPrompt {
            shouldRequestPermission = false
            do {
                authorization = try await manager.requestAuthorization()
                promptCompleted = true
            } catch {
                authorization = manager.authorizationState
            }
        }
        guard currentGeneration == generation else { return .unavailable }
        shouldRequestPermission = false
        guard authorization != .denied else { return .unavailable }
        guard let alarms = try? manager.alarms() else { return .uncertain }

        let ownedIDs = [run.id, run.restAlarmID]
        var cancellationFailed = false
        for alarm in alarms where !ownedIDs.contains(alarm.id) {
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                cancellationFailed = true
            }
        }
        guard !cancellationFailed else { return .uncertain }

        let date = now()
        let existing = alarms.filter { ownedIDs.contains($0.id) }
        if run.isComplete(at: date) {
            return finishCompleted(existing: existing, at: date, manager: manager)
        }

        guard run.isRunning else {
            return cancelOwned(existing: existing, manager: manager)
        }

        let scheduleDate = now()
        let neededAlarms = needed(run: run, at: scheduleDate)
        guard !neededAlarms.isEmpty else { return .unavailable }

        if neededAlarms.allSatisfy({ item in
            existing.contains { $0.id == item.id && $0.state == .alerting }
        }) {
            return .scheduled
        }

        if authorization != .authorized {
            let tryScheduleAnyway = promptCompleted && authorization == .notDetermined
            if !tryScheduleAnyway {
                return existing.isEmpty ? .unavailable : .uncertain
            }
        }

        return await ensure(
            neededAlarms,
            existing: existing,
            runID: run.id,
            manager: manager,
        )
    }

    private func needed(run: FocusRun, at date: Date) -> [(id: UUID, deadline: Date, phase: TimerAlarmPhase)] {
        guard run.isRunning, !run.isComplete(at: date) else { return [] }
        var alarms: [(id: UUID, deadline: Date, phase: TimerAlarmPhase)] = []
        let delay = run.resumeDelay(at: date)
        let focusRemaining = run.focusRemaining(at: date)
        if focusRemaining > 0 {
            alarms.append((run.id, date.addingTimeInterval(delay + focusRemaining), .focus))
        }
        if run.restSeconds > 0 {
            let totalRemaining = run.remaining(at: date)
            if totalRemaining > 0 {
                alarms.append((run.restAlarmID, date.addingTimeInterval(delay + totalRemaining), .rest))
            }
        }
        return alarms
    }

    private func finishCompleted(
        existing: [TimerAlarmRecord],
        at date: Date,
        manager: any TimerAlarmManager,
    ) -> TimerAlarmCoverage {
        var covered = false
        for alarm in existing {
            if alarm.state == .alerting {
                covered = true
                continue
            }
            if alarm.state == .scheduled, alarm.deadline == nil {
                covered = true
                continue
            }
            if alarm.state == .scheduled, let deadline = alarm.deadline, deadline <= date {
                covered = true
                continue
            }
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                return .uncertain
            }
        }
        return covered ? .scheduled : .unavailable
    }

    private func cancelOwned(existing: [TimerAlarmRecord], manager: any TimerAlarmManager) -> TimerAlarmCoverage {
        for alarm in existing {
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                return .uncertain
            }
        }
        return .unavailable
    }

    private func ensure(
        _ neededAlarms: [(id: UUID, deadline: Date, phase: TimerAlarmPhase)],
        existing: [TimerAlarmRecord],
        runID: UUID,
        manager: any TimerAlarmManager,
    ) async -> TimerAlarmCoverage {
        let neededIDs = Set(neededAlarms.map(\.id))
        for alarm in existing where !neededIDs.contains(alarm.id) {
            if alarm.state == .alerting { continue }
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                return .uncertain
            }
        }

        for needed in neededAlarms {
            let existingAlarm = existing.first { $0.id == needed.id }
            if existingAlarm?.state == .alerting {
                continue
            }
            if let existingAlarm, existingAlarm.state == .scheduled {
                if existingAlarm.deadline == nil {
                    continue
                }
                if let existingDeadline = existingAlarm.deadline,
                   abs(existingDeadline.timeIntervalSince(needed.deadline)) < 0.5 {
                    continue
                }
            }
            if let existingAlarm {
                do {
                    try manager.cancel(id: existingAlarm.id)
                } catch {
                    return .uncertain
                }
            }
            do {
                try await manager.schedule(id: needed.id, deadline: needed.deadline, runID: runID, phase: needed.phase)
            } catch {
                guard let remainingAlarms = try? manager.alarms() else { return .uncertain }
                if remainingAlarms.isEmpty {
                    return .unavailable
                }
                if remainingAlarms.allSatisfy({ neededIDs.contains($0.id) }),
                   remainingAlarms.contains(where: { alarm in
                       alarm.id == needed.id && (
                           alarm.state == .alerting
                               || (
                                   alarm.state == .scheduled
                                       && alarm.deadline.map { abs($0.timeIntervalSince(needed.deadline)) < 0.5 } == true
                               )
                       )
                   }) {
                    continue
                }
                return .uncertain
            }
        }
        return .scheduled
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(AlarmKit)
import AlarmKit
import SwiftUI

@available(iOS 26.0, *)
@MainActor
private final class SystemTimerAlarmManager: TimerAlarmManager {
    private let manager = AlarmManager.shared

    var authorizationState: TimerAlarmAuthorization {
        authorization(manager.authorizationState)
    }

    func requestAuthorization() async throws -> TimerAlarmAuthorization {
        authorization(try await manager.requestAuthorization())
    }

    func alarms() throws -> [TimerAlarmRecord] {
        try manager.alarms.map { alarm in
            let deadline: Date?
            if let schedule = alarm.schedule, case let .fixed(date) = schedule {
                deadline = date
            } else {
                deadline = nil
            }
            let state: TimerAlarmRecord.State
            switch alarm.state {
            case .scheduled, .countdown: state = .scheduled
            case .alerting: state = .alerting
            default: state = .other
            }
            return TimerAlarmRecord(id: alarm.id, deadline: deadline, state: state)
        }
    }

    func schedule(id: UUID, deadline: Date, runID: UUID, phase: TimerAlarmPhase) async throws {
        let title: LocalizedStringResource = "Time is up"
        let countdownTitle: LocalizedStringResource = phase == .rest ? "Rest" : "Focus"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark"),
            )
        }
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(title: countdownTitle),
                paused: AlarmPresentation.Paused(
                    title: "Paused",
                    resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill"),
                ),
            ),
            metadata: FocusAlarmMetadata(runID: runID),
            tintColor: Color(red: 0.76, green: 0.42, blue: 0.28),
        )
        let remaining = max(1, deadline.timeIntervalSince(Date()))
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: remaining,
            attributes: attributes,
            stopIntent: StopTimerAlarmIntent(runID: runID),
            sound: .default,
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
    }

    func cancel(id: UUID) throws {
        try manager.cancel(id: id)
    }

    private func authorization(_ state: AlarmManager.AuthorizationState) -> TimerAlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
#endif
