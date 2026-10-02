import SwiftUI

struct PauseCountdownView: View {
    let remaining: TimeInterval
    let window: TimeInterval

    private var fraction: Double {
        guard window > 0 else { return 0 }
        return min(1, max(0, remaining / window))
    }

    private var seconds: Int {
        Int(ceil(max(0, remaining)))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(.secondary.opacity(0.3), lineWidth: 3)
                    PauseWedge(fraction: fraction)
                        .fill(.primary.opacity(0.85))
                        .padding(6)
                }
                .frame(width: 140, height: 140)

                Text("Resuming in \(seconds)s")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paused. Resuming in \(seconds) seconds.")
    }
}

struct PauseWedge: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        guard fraction > 0 else { return path }
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 + 360 * (1 - min(1, fraction))),
            endAngle: .degrees(270),
            clockwise: false,
        )
        path.closeSubpath()
        return path
    }
}
