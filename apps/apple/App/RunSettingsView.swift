import SwiftUI

struct RunSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTheme: String
    @State private var visibleTheme: String?
    @State private var selectedMinute: Int
    @State private var visibleMinute: Int?
    @State private var selectedRestMinute: Int
    @State private var visibleRestMinute: Int?
    @State private var loops: Bool
    @State private var didPositionSelectors = false

    let onStart: (Int, Int, Bool, String) -> Void

    init(currentRun: FocusRun, onStart: @escaping (Int, Int, Bool, String) -> Void) {
        _selectedTheme = State(initialValue: TimerThemes.resolve(currentRun.theme).id)
        _visibleTheme = State(initialValue: nil)
        _selectedMinute = State(initialValue: min(120, max(1, currentRun.goalSeconds / 60)))
        _visibleMinute = State(initialValue: nil)
        _selectedRestMinute = State(initialValue: min(120, max(0, currentRun.restSeconds / 60)))
        _visibleRestMinute = State(initialValue: nil)
        _loops = State(initialValue: currentRun.loops)
        self.onStart = onStart
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    themeSelector
                    minuteSelector(
                        title: "Focus",
                        selected: $selectedMinute,
                        visible: $visibleMinute,
                        range: 1...120,
                        accessibilityLabel: "Focus duration",
                    )
                    minuteSelector(
                        title: "Rest",
                        selected: $selectedRestMinute,
                        visible: $visibleRestMinute,
                        range: 0...120,
                        accessibilityLabel: "Rest duration",
                    )
                    Toggle(isOn: $loops) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Loop")
                                .font(.headline)
                            Text("Start the next cycle as soon as rest ends.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 28)
                    Link("Privacy Policy", destination: URL(string: "https://github.com/grahamotte/littlewhile.app/blob/master/docs/privacy-policy.md")!)
                        .font(.footnote)
                        .padding(.horizontal, 28)
                }
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassActionButton(title: "Start") {
                onStart(selectedMinute, selectedRestMinute, loops, selectedTheme)
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 22)
            .background(.background)
        }
        .sensoryFeedback(.selection, trigger: selectedMinute)
        .sensoryFeedback(.selection, trigger: selectedRestMinute)
        .sensoryFeedback(.selection, trigger: selectedTheme)
        .task {
            await Task.yield()
            visibleTheme = selectedTheme
            visibleMinute = selectedMinute
            visibleRestMinute = selectedRestMinute
            await Task.yield()
            didPositionSelectors = true
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Settings")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))

            Spacer(minLength: 0)

            GlassIconButton(symbol: "xmark", label: "Close settings") {
                dismiss()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }

    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Theme")
                .font(.headline)
                .padding(.horizontal, 28)

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(TimerThemes.all, id: \.id) { theme in
                            Button {
                                selectedTheme = theme.id
                                visibleTheme = theme.id
                            } label: {
                                VStack(spacing: 13) {
                                    theme.preview
                                        .frame(width: 176, height: 176)
                                        .clipShape(RoundedRectangle(cornerRadius: 26))
                                        .padding(5)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 31)
                                                .strokeBorder(
                                                    selectedTheme == theme.id ? Color.primary : Color.clear,
                                                    lineWidth: 2,
                                                )
                                        }
                                        .overlay(alignment: .bottomTrailing) {
                                            if selectedTheme == theme.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.background)
                                                    .frame(width: 24, height: 24)
                                                    .background(.primary, in: Circle())
                                                    .padding(13)
                                            }
                                        }

                                    Text(theme.name)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(theme.name) theme")
                            .accessibilityValue(selectedTheme == theme.id ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selectedTheme == theme.id ? .isSelected : [])
                            .id(theme.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(24, (geometry.size.width - 186) / 2), for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $visibleTheme, anchor: .center)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.07),
                            .init(color: .black, location: 0.93),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing,
                    )
                }
            }
            .frame(height: 220)
        }
    }

    private func minuteSelector(
        title: String,
        selected: Binding<Int>,
        visible: Binding<Int?>,
        range: ClosedRange<Int>,
        accessibilityLabel: String,
    ) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(selected.wrappedValue)")
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("min")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(range), id: \.self) { minute in
                            Capsule()
                                .fill(.primary.opacity(minute.isMultiple(of: 5) ? 0.5 : 0.18))
                                .frame(width: 1.5, height: minute.isMultiple(of: 5) ? 38 : 22)
                                .frame(width: 14, height: 74, alignment: .top)
                                .overlay(alignment: .top) {
                                    if minute.isMultiple(of: 5) {
                                        Text("\(minute)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                            .offset(y: 48)
                                    }
                                }
                                .id(minute)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, geometry.size.width / 2 - 7), for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollPosition(id: visible, anchor: .center)
                .onChange(of: visible.wrappedValue) { _, minute in
                    if didPositionSelectors, let minute {
                        selected.wrappedValue = minute
                    }
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 3, height: 46)
                        .offset(y: -4)
                        .allowsHitTesting(false)
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing,
                    )
                }
            }
            .frame(height: 74)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(selected.wrappedValue) \(selected.wrappedValue == 1 ? "minute" : "minutes")")
            .accessibilityHint("Swipe up or down to adjust by one minute")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selected.wrappedValue = min(range.upperBound, selected.wrappedValue + 1)
                    visible.wrappedValue = selected.wrappedValue
                case .decrement:
                    selected.wrappedValue = max(range.lowerBound, selected.wrappedValue - 1)
                    visible.wrappedValue = selected.wrappedValue
                @unknown default:
                    break
                }
            }
        }
    }
}
