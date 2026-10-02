import SwiftUI

struct AppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: RunStore
    @State private var companion: TimerCompanion?
    @State private var sheet: TimerSheet?
    @State private var showingRestart = false
    @State private var showingStop = false
    @State private var completedRunID: UUID?

    init(store: RunStore? = nil) {
        _store = State(initialValue: store ?? RunStore())
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = TimerSnapshot(run: store.currentRun, at: .now)
            let theme = TimerThemes.resolve(store.currentRun.theme)

            theme.screen(snapshot)
                .environment(\.colorScheme, theme.colorScheme)
                .overlay {
                    if let remaining = snapshot.pauseRemainingSeconds {
                        PauseCountdownView(remaining: remaining, window: snapshot.pauseWindowSeconds)
                            .environment(\.colorScheme, theme.colorScheme)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: snapshot.pauseRemainingSeconds != nil)
                .overlay(alignment: .top) {
                    controls(snapshot: snapshot)
                        .environment(\.colorScheme, theme.colorScheme)
                }
                .onChange(of: snapshot.status, initial: true) { _, status in
                    handleCompletion(snapshot)
                }
                .onChange(of: snapshot.status) { _, status in
                    guard status == .running, !store.currentRun.isRunning else { return }
                    store.refresh()
                    synchronizeCompanion()
                }
                .onChange(of: snapshot.cycle) { _, _ in
                    guard snapshot.loops else { return }
                    store.refresh()
                    synchronizeCompanion()
                }
                .sensoryFeedback(.success, trigger: snapshot.status == .complete) { _, completed in
                    completed
                }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings:
                RunSettingsView(currentRun: store.currentRun) { minutes, restMinutes, loops, theme in
                    store.startRun(minutes: minutes, theme: theme, restMinutes: restMinutes, loops: loops)
                    synchronizeCompanion(userInitiated: true)
                }
                .presentationDragIndicator(.visible)
            case .history:
                RunHistoryView(store: store)
                    .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Start this run over?", isPresented: $showingRestart, titleVisibility: .visible) {
            Button("Start over") {
                store.restart()
                synchronizeCompanion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress will stay in History. A fresh run with the same times and theme will be ready to start.")
        }
        .confirmationDialog(
            store.currentRun.loops ? "Stop this loop?" : "Stop this run?",
            isPresented: $showingStop,
            titleVisibility: .visible,
        ) {
            Button("Stop", role: .destructive) {
                store.stop()
                synchronizeCompanion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress will stay in History. A fresh run with the same times and theme will be ready to start.")
        }
        .alert("Alarm couldn’t be confirmed", isPresented: Binding(
            get: { companion?.alarmIssue != nil },
            set: { if !$0 { companion?.alarmIssue = nil } },
        )) {
            Button("OK", role: .cancel) { companion?.alarmIssue = nil }
        } message: {
            Text(companion?.alarmIssue ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refresh()
                synchronizeCompanion()
            }
        }
        .task {
            if companion == nil {
                companion = TimerCompanion()
            }
            store.refresh()
            await companion?.synchronize(run: store.currentRun)
        }
    }

    private func controls(snapshot: TimerSnapshot) -> some View {
        HStack(spacing: 12) {
            if !snapshot.canStop {
                GlassIconButton(symbol: "clock.arrow.circlepath", label: "History") {
                    sheet = .history
                }
                .transition(.scale.combined(with: .opacity))
                GlassIconButton(symbol: "slider.horizontal.3", label: "Run settings") {
                    sheet = .settings
                }
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            if snapshot.canStop {
                GlassIconButton(symbol: "stop.fill", label: snapshot.stopLabel) {
                    showingStop = true
                }
                .transition(.scale.combined(with: .opacity))
            }
            GlassIconButton(symbol: snapshot.controlSymbol, label: snapshot.controlLabel) {
                if snapshot.status == .complete {
                    store.restart()
                } else {
                    store.toggle()
                }
                synchronizeCompanion(userInitiated: store.currentRun.isRunning)
            }
            .contextMenu {
                Button("Start over", systemImage: "arrow.counterclockwise") {
                    showingRestart = true
                }
                .disabled(!store.currentRun.hasStarted)
            }
            .accessibilityHint("Touch and hold for the start over option.")
            .accessibilityAction(named: "Start over") {
                showingRestart = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: snapshot.canStop)
    }

    private func handleCompletion(_ snapshot: TimerSnapshot) {
        guard snapshot.status == .complete, completedRunID != snapshot.runID else { return }
        completedRunID = snapshot.runID
        store.refresh()
        Task {
            await companion?.complete(run: store.currentRun)
        }
    }

    private func synchronizeCompanion(userInitiated: Bool = false) {
        Task {
            await companion?.synchronize(run: store.currentRun, userInitiated: userInitiated)
        }
    }
}

private enum TimerSheet: String, Identifiable {
    case settings
    case history

    var id: Self { self }
}
