import Foundation

struct FocusRun: Identifiable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var startedAt: Date?
    var progressSeconds: TimeInterval = 0
    var goalSeconds: Int = 25 * 60
    var restSeconds: Int = 0
    var theme: String = "boring"
    var resumedAt: Date?
    var pausedAt: Date?
    var loops: Bool = false
    var stoppedAt: Date?

    static let pauseWindow: TimeInterval = 60

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        startedAt: Date? = nil,
        progressSeconds: TimeInterval = 0,
        goalSeconds: Int = 25 * 60,
        restSeconds: Int = 0,
        theme: String = "boring",
        resumedAt: Date? = nil,
        pausedAt: Date? = nil,
        loops: Bool = false,
        stoppedAt: Date? = nil,
    ) {
        self.id = id
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.progressSeconds = progressSeconds
        self.goalSeconds = goalSeconds
        self.restSeconds = restSeconds
        self.theme = theme
        self.resumedAt = resumedAt
        self.pausedAt = pausedAt
        self.loops = loops
        self.stoppedAt = stoppedAt
    }

    var isRunning: Bool {
        resumedAt != nil
    }

    var pauseDeadline: Date? {
        guard !isRunning, let pausedAt else { return nil }
        return pausedAt.addingTimeInterval(Self.pauseWindow)
    }

    func pauseRemaining(at date: Date) -> TimeInterval? {
        guard let deadline = pauseDeadline, deadline > date, !isComplete(at: date) else { return nil }
        return deadline.timeIntervalSince(date)
    }

    func autoResumed(at date: Date) -> FocusRun {
        guard let deadline = pauseDeadline, deadline <= date else { return self }
        return resumingAtPauseDeadline()
    }

    func resumingAtPauseDeadline() -> FocusRun {
        guard let deadline = pauseDeadline else { return self }
        var run = self
        run.resumedAt = deadline
        run.pausedAt = nil
        return run
    }

    func resumeDelay(at date: Date) -> TimeInterval {
        guard let resumedAt else { return 0 }
        return max(0, resumedAt.timeIntervalSince(date))
    }

    var hasStarted: Bool {
        startedAt != nil
    }

    var totalSeconds: Int {
        max(0, goalSeconds) + max(0, restSeconds)
    }

    var restAlarmID: UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xB1
        bytes.1 ^= 0xEA
        bytes.2 ^= 0xC5
        bytes.3 ^= 0x07
        return UUID(uuid: bytes)
    }

    func alarmID(cycle: Int, resting: Bool) -> UUID {
        var bytes = (resting ? restAlarmID : id).uuid
        let value = UInt32(truncatingIfNeeded: max(0, cycle))
        bytes.4 ^= UInt8(truncatingIfNeeded: value >> 24)
        bytes.5 ^= UInt8(truncatingIfNeeded: value >> 16)
        bytes.6 ^= UInt8(truncatingIfNeeded: value >> 8)
        bytes.7 ^= UInt8(truncatingIfNeeded: value)
        return UUID(uuid: bytes)
    }

    func elapsed(at date: Date) -> TimeInterval {
        let total = TimeInterval(totalSeconds)
        let saved = progressSeconds.isFinite ? max(0, progressSeconds) : 0
        let progress = loops ? saved : min(total, saved)
        let interval = resumedAt.map { date.timeIntervalSince($0) } ?? 0
        let additional = interval.isFinite ? max(0, interval) : 0
        return loops ? progress + additional : min(total, progress + additional)
    }

    func completedCycles(at date: Date) -> Int {
        let total = TimeInterval(totalSeconds)
        guard total > 0 else { return 0 }
        let elapsed = elapsed(at: date)
        if loops {
            return Int(elapsed / total)
        }
        return elapsed >= total ? 1 : 0
    }

    func cycleElapsed(at date: Date) -> TimeInterval {
        let total = TimeInterval(totalSeconds)
        let elapsed = elapsed(at: date)
        guard loops, total > 0 else { return elapsed }
        return elapsed - TimeInterval(completedCycles(at: date)) * total
    }

    func focusElapsed(at date: Date) -> TimeInterval {
        let goal = TimeInterval(max(0, goalSeconds))
        guard loops else { return min(goal, elapsed(at: date)) }
        return TimeInterval(completedCycles(at: date)) * goal + min(goal, cycleElapsed(at: date))
    }

    func remaining(at date: Date) -> TimeInterval {
        max(0, TimeInterval(totalSeconds) - cycleElapsed(at: date))
    }

    func focusRemaining(at date: Date) -> TimeInterval {
        max(0, TimeInterval(max(0, goalSeconds)) - cycleElapsed(at: date))
    }

    func isResting(at date: Date) -> Bool {
        restSeconds > 0 && cycleElapsed(at: date) >= TimeInterval(max(0, goalSeconds)) && !isComplete(at: date)
    }

    func periodSeconds(at date: Date) -> Int {
        isResting(at: date) ? max(0, restSeconds) : max(0, goalSeconds)
    }

    func periodRemaining(at date: Date) -> TimeInterval {
        if isResting(at: date) {
            return remaining(at: date)
        }
        return focusRemaining(at: date)
    }

    func periodProgress(at date: Date) -> Double {
        let period = periodSeconds(at: date)
        guard period > 0 else { return 1 }
        return (TimeInterval(period) - periodRemaining(at: date)) / TimeInterval(period)
    }

    func fraction(at date: Date) -> Double {
        guard totalSeconds > 0 else { return 1 }
        return min(1, elapsed(at: date) / TimeInterval(totalSeconds))
    }

    func didFinishCycle(at date: Date) -> Bool {
        completedCycles(at: date) > 0
    }

    func isComplete(at date: Date) -> Bool {
        if stoppedAt != nil {
            return true
        }
        return !loops && elapsed(at: date) >= TimeInterval(totalSeconds)
    }
}

extension FocusRun: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case startedAt
        case progressSeconds
        case goalSeconds
        case restSeconds
        case theme
        case resumedAt
        case pausedAt
        case loops
        case stoppedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        progressSeconds = try container.decode(TimeInterval.self, forKey: .progressSeconds)
        goalSeconds = try container.decode(Int.self, forKey: .goalSeconds)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 0
        theme = try container.decode(String.self, forKey: .theme)
        resumedAt = try container.decodeIfPresent(Date.self, forKey: .resumedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        stoppedAt = try container.decodeIfPresent(Date.self, forKey: .stoppedAt)
    }
}
