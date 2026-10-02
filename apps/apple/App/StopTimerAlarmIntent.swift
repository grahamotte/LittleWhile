#if os(iOS)
import AppIntents

@available(iOS 26.0, *)
nonisolated struct StopTimerAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop focus alarm" }

    @Parameter(title: "Run")
    var runIdentifier: String

    init() {
        runIdentifier = ""
    }

    init(runID: UUID) {
        runIdentifier = runID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let runID = UUID(uuidString: runIdentifier) {
            let run = await MainActor.run { RunStore().currentRun }
            if run.id == runID, run.loops, !run.isComplete(at: .now) {
                _ = await TimerAlarm().synchronize(run: run)
                await TimerLiveActivity().synchronize(run: run)
            } else {
                await TimerLiveActivity().finish(runID: runID)
            }
        }
        return .result()
    }
}
#endif
