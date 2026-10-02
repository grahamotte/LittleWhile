import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

nonisolated struct TimerActivityAttributes: Codable, Hashable, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var deadline: Date?
        var remainingSeconds: Double
        var isPaused: Bool
        var isComplete: Bool
    }

    var runID: UUID
    var goalSeconds: Int
    var restSeconds: Int = 0
    var loops: Bool = false
}

#if os(iOS) && canImport(ActivityKit)
extension TimerActivityAttributes: ActivityAttributes {}
#endif
