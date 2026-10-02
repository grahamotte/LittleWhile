#if os(iOS)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct TimerActivityWidgets: WidgetBundle {
    var body: some Widget {
        TimerActivityWidget()
        if #available(iOS 26.0, *) {
            TimerAlarmActivityWidget()
        }
    }
}

struct TimerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let content = TimerActivityView(context: context, now: timeline.date)
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            content.brandIcon
                                .frame(width: 22, height: 22)

                            Text(content.statusText)
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            Text(content.goalText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        content.countdown
                            .font(.system(size: 44, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                    }

                    content.ring
                        .frame(width: 46, height: 46)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .activitySystemActionForegroundColor(.primary)
                .accessibilityElement(children: .combine)
            }
        } dynamicIsland: { context in
            let content = TimerActivityView(context: context, now: .now)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    content.brandIcon
                        .frame(width: 24, height: 24)
                        .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(content.goalText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            content.countdown
                                .font(.system(size: 38, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .minimumScaleFactor(0.75)

                            Text(content.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        content.progress
                            .tint(.white)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                content.brandIcon
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                if content.hasFinished {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                } else {
                    content.countdown
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .minimumScaleFactor(0.6)
                }
            } minimal: {
                if content.hasFinished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                } else {
                    content.brandIcon
                        .frame(width: 20, height: 20)
                }
            }
            .keylineTint(Color(red: 0.93, green: 0.89, blue: 0.82))
        }
    }
}

private struct TimerActivityView {
    let context: ActivityViewContext<TimerActivityAttributes>
    let now: Date

    var deadline: Date? {
        guard let deadline = context.state.deadline else { return nil }
        let cycle = Double(context.attributes.goalSeconds + context.attributes.restSeconds)
        guard context.attributes.loops, !context.state.isPaused, cycle > 0, deadline <= now else { return deadline }
        let cycles = (now.timeIntervalSince(deadline) / cycle).rounded(.down) + 1
        return deadline.addingTimeInterval(cycles * cycle)
    }

    var hasFinished: Bool {
        if context.state.isComplete || (context.isStale && !context.state.isPaused) {
            return true
        }
        if context.state.isPaused {
            return false
        }
        if let deadline {
            return deadline <= now
        }
        return context.state.remainingSeconds <= 0
    }

    var isResting: Bool {
        guard !hasFinished, context.attributes.restSeconds > 0 else { return false }
        if let deadline {
            return now >= deadline.addingTimeInterval(-Double(context.attributes.restSeconds))
        }
        return context.state.remainingSeconds <= Double(context.attributes.restSeconds)
    }

    var periodSeconds: Int {
        isResting ? context.attributes.restSeconds : context.attributes.goalSeconds
    }

    var periodDeadline: Date? {
        guard let deadline else { return nil }
        if isResting || context.attributes.restSeconds <= 0 {
            return deadline
        }
        return deadline.addingTimeInterval(-Double(context.attributes.restSeconds))
    }

    var periodRemaining: Double {
        if let periodDeadline {
            return max(0, periodDeadline.timeIntervalSince(now))
        }
        if isResting {
            return max(0, context.state.remainingSeconds)
        }
        return max(0, context.state.remainingSeconds - Double(context.attributes.restSeconds))
    }

    var statusText: String {
        if hasFinished { return "Time’s up" }
        if context.state.isPaused { return "Paused" }
        return isResting ? "Rest" : "Remaining"
    }

    var goalText: String {
        "\(periodSeconds / 60) min"
    }

    var brandIcon: some View {
        MiniBrandIcon()
    }

    @ViewBuilder
    var countdown: some View {
        if hasFinished {
            Text("00:00")
        } else if !context.state.isPaused, let periodDeadline {
            Text(
                timerInterval: periodDeadline.addingTimeInterval(-Double(periodSeconds))...periodDeadline,
                countsDown: true,
                showsHours: false,
            )
            .contentTransition(.numericText(countsDown: true))
        } else {
            Text(
                Duration.seconds(max(0, periodRemaining).rounded(.up))
                    .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))),
            )
        }
    }

    @ViewBuilder
    var progress: some View {
        if hasFinished {
            ProgressView(value: 1)
        } else if !context.state.isPaused, let periodDeadline {
            ProgressView(
                timerInterval: periodDeadline.addingTimeInterval(-Double(periodSeconds))...periodDeadline,
                countsDown: false,
            ) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        } else {
            ProgressView(value: 1 - periodRemaining / Double(max(1, periodSeconds)))
        }
    }

    @ViewBuilder
    var ring: some View {
        if hasFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Timer complete")
        } else if context.state.isPaused {
            progress
                .progressViewStyle(.circular)
                .tint(.secondary)
                .accessibilityLabel("Timer paused")
        } else {
            progress
                .progressViewStyle(.circular)
                .tint(.primary)
                .accessibilityLabel("Timer progress")
        }
    }
}

private struct MiniBrandIcon: View {
    var body: some View {
        Image("MiniIcon")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

@available(iOS 26.0, *)
struct TimerAlarmActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FocusAlarmMetadata>.self) { context in
            let content = AlarmActivityContent(context: context)

            HStack(spacing: 12) {
                MiniBrandIcon()
                    .frame(width: 36, height: 36)

                content.title
                    .font(.headline)

                Spacer(minLength: 0)

                content.countdown
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .activityBackgroundTint(context.attributes.tintColor.opacity(0.35))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let content = AlarmActivityContent(context: context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniBrandIcon()
                        .frame(width: 24, height: 24)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .lastTextBaseline) {
                        content.title
                            .font(.headline)
                        Spacer(minLength: 8)
                        content.countdown
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                MiniBrandIcon()
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                if content.isAlerting {
                    Image(systemName: "alarm.fill")
                        .font(.caption.weight(.bold))
                } else {
                    content.countdown
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .minimumScaleFactor(0.6)
                }
            } minimal: {
                MiniBrandIcon()
                    .frame(width: 20, height: 20)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }
}

@available(iOS 26.0, *)
private struct AlarmActivityContent {
    let context: ActivityViewContext<AlarmAttributes<FocusAlarmMetadata>>

    var isAlerting: Bool {
        if case .alert = context.state.mode { return true }
        return false
    }

    var title: Text {
        switch context.state.mode {
        case .paused:
            Text(context.attributes.presentation.paused?.title ?? "Paused")
        case .alert:
            Text(context.attributes.presentation.alert.title)
        default:
            Text(context.attributes.presentation.countdown?.title ?? "Focus")
        }
    }

    @ViewBuilder
    var countdown: some View {
        switch context.state.mode {
        case .alert:
            Text("00:00")
        case .countdown(let countdown):
            Text(
                timerInterval: countdown.startDate...countdown.fireDate,
                countsDown: true,
                showsHours: false,
            )
            .contentTransition(.numericText(countsDown: true))
        case .paused(let paused):
            Text(
                Duration.seconds(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration).rounded(.up))
                    .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))),
            )
        @unknown default:
            EmptyView()
        }
    }
}
#endif
