import Foundation

struct TimerSnapshot: Equatable {
    enum Status: Equatable {
        case ready
        case running
        case paused
        case complete
    }

    let runID: UUID
    let sampledAt: Date
    let goalSeconds: Int
    let restSeconds: Int
    let totalSeconds: Int
    let elapsedSeconds: TimeInterval
    let remainingSeconds: TimeInterval
    let progress: Double
    let isResting: Bool
    let status: Status
    let pauseRemainingSeconds: TimeInterval?
    let pauseWindowSeconds: TimeInterval

    init(run source: FocusRun, at date: Date) {
        let run = source.autoResumed(at: date)
        runID = run.id
        sampledAt = date
        goalSeconds = run.goalSeconds
        restSeconds = run.restSeconds
        totalSeconds = run.totalSeconds
        elapsedSeconds = run.elapsed(at: date)
        remainingSeconds = run.periodRemaining(at: date)
        progress = run.periodProgress(at: date)
        isResting = run.isResting(at: date)
        pauseRemainingSeconds = run.pauseRemaining(at: date)
        pauseWindowSeconds = FocusRun.pauseWindow
        if run.isComplete(at: date) {
            status = .complete
        } else if run.isRunning {
            status = .running
        } else if run.hasStarted {
            status = .paused
        } else {
            status = .ready
        }
    }

    var clockText: String {
        let seconds = Int(ceil(remainingSeconds))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var controlSymbol: String {
        switch status {
        case .running: "pause.fill"
        case .complete: "arrow.counterclockwise"
        case .ready, .paused: "play.fill"
        }
    }

    var controlLabel: String {
        switch status {
        case .ready: "Start timer"
        case .running: "Pause timer"
        case .paused: "Resume timer"
        case .complete: "New run with the same settings"
        }
    }
}
