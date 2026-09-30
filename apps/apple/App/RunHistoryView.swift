import SwiftUI

struct RunHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    let store: RunStore

    var body: some View {
        VStack(spacing: 0) {
            header

            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    MonthlyActivityView(runs: store.runs, date: context.date)
                        .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 18, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(store.visibleRuns(at: context.date)) { run in
                        if run.id == store.currentRun.id {
                            historyRow(run, isCurrent: true, at: context.date)
                                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            historyRow(run, isCurrent: false, at: context.date)
                                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.deleteRun(id: run.id)
                                    }
                                }
                                .contextMenu {
                                    Button("Delete run", systemImage: "trash", role: .destructive) {
                                        store.deleteRun(id: run.id)
                                    }
                                }
                                .accessibilityAction(named: Text("Delete run")) {
                                    store.deleteRun(id: run.id)
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("History")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))

            Spacer(minLength: 0)

            GlassIconButton(symbol: "xmark", label: "Close history") {
                dismiss()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
    }

    private func historyRow(_ run: FocusRun, isCurrent: Bool, at date: Date) -> some View {
        let complete = run.isComplete(at: date)

        return VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Duration.seconds(run.elapsed(at: date)).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(.title2, design: .rounded, weight: .medium))

                        Text("of \(Duration.seconds(run.totalSeconds).formatted(.time(pattern: .minuteSecond)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }

                Spacer(minLength: 0)

                Image(systemName: complete ? "checkmark" : "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(complete ? Color.primary : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.05), in: Circle())
                    .accessibilityHidden(true)
            }

            ProgressView(value: run.fraction(at: date))
                .tint(.primary.opacity(0.65))
                .accessibilityLabel("Run progress")

            HStack {
                Text(TimerThemes.resolve(run.theme).name)

                Spacer()

                Text(isCurrent ? "Current" : (complete ? "Completed" : "Finished early"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
