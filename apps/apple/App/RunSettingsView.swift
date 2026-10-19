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

    private let themePreviewSide: CGFloat = 160

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

            ViewThatFits(in: .vertical) {
                settings
                ScrollView {
                    settings
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassActionButton(title: "Start") {
                onStart(selectedMinute, selectedRestMinute, loops, selectedTheme)
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 16)
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

    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            themeSelector
            minuteSelector(
                title: "Focus",
                selected: $selectedMinute,
                visible: $visibleMinute,
                range: 1...120,
                valueSize: 48,
                accessibilityLabel: "Focus duration",
            )
            minuteSelector(
                title: "Rest",
                selected: $selectedRestMinute,
                visible: $visibleRestMinute,
                range: 0...120,
                valueSize: 30,
                accessibilityLabel: "Rest duration",
            )
            Toggle(isOn: $loops) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loop")
                        .font(.headline)
                    Text("Start the next cycle as soon as rest ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
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
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.headline)
                .padding(.horizontal, 28)

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(TimerThemes.all, id: \.id) { theme in
                            Button {
                                selectedTheme = theme.id
                                visibleTheme = theme.id
                            } label: {
                                VStack(spacing: 8) {
                                    theme.preview
                                        .frame(width: 176, height: 176)
                                        .scaleEffect(themePreviewSide / 176)
                                        .frame(width: themePreviewSide, height: themePreviewSide)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .padding(4)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 24)
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
                                                    .frame(width: 22, height: 22)
                                                    .background(.primary, in: Circle())
                                                    .padding(10)
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
                .contentMargins(.horizontal, max(24, (geometry.size.width - themePreviewSide - 8) / 2), for: .scrollContent)
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
            .frame(height: themePreviewSide + 34)
        }
    }

    private func minuteSelector(
        title: String,
        selected: Binding<Int>,
        visible: Binding<Int?>,
        range: ClosedRange<Int>,
        valueSize: CGFloat,
        accessibilityLabel: String,
    ) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headline)

                Spacer(minLength: 0)

                Text("\(selected.wrappedValue)")
                    .font(.system(size: valueSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .accessibilityHidden(true)

            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(range), id: \.self) { minute in
                            Capsule()
                                .fill(.primary.opacity(minute.isMultiple(of: 5) ? 0.5 : 0.18))
                                .frame(width: 1.5, height: minute.isMultiple(of: 5) ? 30 : 18)
                                .frame(width: 14, height: 56, alignment: .top)
                                .overlay(alignment: .top) {
                                    if minute.isMultiple(of: 5) {
                                        Text("\(minute)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                            .offset(y: 38)
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
                        .frame(width: 3, height: 38)
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
            .frame(height: 56)
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
