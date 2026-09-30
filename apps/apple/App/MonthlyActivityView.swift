import SwiftUI

struct MonthlyActivityView: View {
    @Environment(\.calendar) private var calendar
    @State private var selectedMonth: Date = .now

    let runs: [FocusRun]
    let date: Date

    var body: some View {
        let activity = MonthlyActivity(runs: runs, month: selectedMonth, at: date, calendar: calendar)

        VStack(spacing: 18) {
            HStack {
                GlassIconButton(symbol: "chevron.left", label: "Previous month") {
                    selectedMonth = activity.month(byAdding: -1, at: date)
                }

                Spacer(minLength: 0)

                Text(activity.month, format: .dateTime.month(.wide).year())
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                GlassIconButton(symbol: "chevron.right", label: "Next month") {
                    selectedMonth = activity.month(byAdding: 1, at: date)
                }
                .disabled(!activity.canGoForward(at: date))
                .opacity(activity.canGoForward(at: date) ? 1 : 0.35)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 12) {
                ForEach(0..<7, id: \.self) { index in
                    Text(activity.weekdaySymbols[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                ForEach(0..<activity.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(height: 54)
                        .accessibilityHidden(true)
                }

                ForEach(activity.days) { day in
                    VStack(spacing: 5) {
                        Text("\(day.number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(.primary.opacity(day.focusSeconds > 0 ? 0.65 : 0.1))
                            .frame(width: day.dotDiameter, height: day.dotDiameter)
                            .frame(height: 28)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(day.focusSeconds > 0
                        ? "\(Duration.seconds(day.focusSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))) of focus"
                        : "No focus time")
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        selectedMonth = activity.month(byAdding: value.translation.width > 0 ? -1 : 1, at: date)
                    }
            )

            Text("Larger dots mean more focus time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
    }
}
