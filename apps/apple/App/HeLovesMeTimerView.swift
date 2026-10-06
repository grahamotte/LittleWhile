import SwiftUI

private enum HeLovesMePalette {
    static let daySky = [
        Color(red: 0.72, green: 0.85, blue: 0.93),
        Color(red: 0.91, green: 0.95, blue: 0.94),
        Color(red: 0.99, green: 0.95, blue: 0.86),
    ]
    static let duskSky = [
        Color(red: 0.56, green: 0.56, blue: 0.81),
        Color(red: 0.87, green: 0.67, blue: 0.79),
        Color(red: 0.98, green: 0.80, blue: 0.67),
    ]
    static let dayGround = [Color(red: 0.62, green: 0.78, blue: 0.53), Color(red: 0.43, green: 0.62, blue: 0.40)]
    static let duskGround = [Color(red: 0.42, green: 0.52, blue: 0.50), Color(red: 0.27, green: 0.36, blue: 0.38)]
    static let dayGrass = Color(red: 0.38, green: 0.59, blue: 0.34)
    static let duskGrass = Color(red: 0.25, green: 0.38, blue: 0.36)
    static let stem = Color(red: 0.39, green: 0.60, blue: 0.33)
    static let leaf = Color(red: 0.50, green: 0.72, blue: 0.42)
    static let petal = Color.white
    static let petalBase = Color(red: 0.90, green: 0.88, blue: 0.95)
    static let petalEdge = Color(red: 0.74, green: 0.71, blue: 0.82)
    static let disc = Color(red: 1, green: 0.86, blue: 0.36)
    static let discEdge = Color(red: 0.93, green: 0.60, blue: 0.13)
    static let seed = Color(red: 0.74, green: 0.43, blue: 0.08)
    static let ink = Color(red: 0.25, green: 0.23, blue: 0.31)
    static let love = Color(red: 0.89, green: 0.33, blue: 0.46)
}

struct HeLovesMeTimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var daisy: HeLovesMeDaisy?

    let snapshot: TimerSnapshot

    var body: some View {
        GeometryReader { safeGeometry in
            GeometryReader { geometry in
                let key = HeLovesMeDaisy.Key(seed: snapshot.runID, size: geometry.size, goalSeconds: snapshot.goalSeconds)
                let daisy = daisy(for: key)

                TimelineView(.animation(
                    minimumInterval: 1.0 / 60,
                    paused: snapshot.status != .running || scenePhase != .active || reduceMotion,
                )) { context in
                    let elapsed = HeLovesMeDaisy.elapsed(snapshot: snapshot, at: context.date)
                    let scene = daisy.scene(elapsed: elapsed, restSeconds: snapshot.restSeconds, settled: reduceMotion)
                    let caption = HeLovesMeDaisy.caption(fallen: scene.fallen, finished: scene.finished)

                    ZStack(alignment: .top) {
                        HeLovesMeGarden(layout: daisy.layout, scene: scene, time: reduceMotion ? 0 : elapsed)
                            .accessibilityHidden(true)

                        VStack(spacing: 2) {
                            Text(snapshot.clockText)
                                .font(.system(size: 58, weight: .light, design: .serif))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))

                            HStack(spacing: 7) {
                                Text(caption)
                                    .font(.system(.title3, design: .serif).italic())
                                if scene.finished {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(HeLovesMePalette.love)
                                }
                            }
                            .id(caption)
                            .transition(.opacity)
                        }
                        .foregroundStyle(HeLovesMePalette.ink)
                        .padding(.top, safeGeometry.safeAreaInsets.top + 82)
                        .animation(.easeInOut(duration: 0.6), value: caption)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(accessibilityStatus). \(snapshot.clockText) remaining. \(caption). \(snapshot.goalSeconds / 60) minute focus. \(snapshot.restSeconds / 60) minute rest.")
                    }
                }
                .onChange(of: key, initial: true) { _, key in
                    self.daisy = self.daisy(for: key)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func daisy(for key: HeLovesMeDaisy.Key) -> HeLovesMeDaisy {
        if let daisy, daisy.key == key {
            return daisy
        }
        return HeLovesMeDaisy(key: key)
    }

    private var accessibilityStatus: String {
        switch snapshot.status {
        case .ready: "Ready"
        case .running: snapshot.isResting ? "Resting" : "Focusing"
        case .paused: snapshot.isResting ? "Rest paused" : "Paused"
        case .complete: "Complete"
        }
    }
}

struct HeLovesMeThemePreview: View {
    var body: some View {
        GeometryReader { geometry in
            let daisy = HeLovesMeDaisy(key: HeLovesMeDaisy.Key(seed: UUID(uuid: (0x4C, 0x6F, 0x76, 0x65, 0x73, 0x4D, 0x65, 0x4E, 0x6F, 0x74, 0x44, 0x61, 0x69, 0x73, 0x79, 0x21)), size: geometry.size, goalSeconds: 1_500))

            ZStack(alignment: .top) {
                HeLovesMeGarden(
                    layout: daisy.layout,
                    scene: daisy.scene(elapsed: 940, restSeconds: 0, settled: true),
                    time: 0,
                )

                Text("18:00")
                    .font(.system(size: 17, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(HeLovesMePalette.ink)
                    .padding(.top, 12)
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}

private struct HeLovesMeGarden: View {
    let layout: HeLovesMeLayout
    let scene: HeLovesMeScene
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            drawSky(in: context, size: size)
            drawGround(in: context, size: size)
            drawStem(in: context)

            let length = layout.petalLength
            let width = layout.petalWidth
            let petal = HeLovesMePetal().path(in: CGRect(x: -length / 2, y: -width / 2, width: length, height: width))
            for pose in scene.petals where pose.attached {
                drawPetal(petal, pose: pose, in: context)
            }
            drawDisc(in: context)
            for pose in scene.petals where !pose.attached {
                drawPetal(petal, pose: pose, in: context)
            }
        }
    }

    private func drawSky(in context: GraphicsContext, size: CGSize) {
        let sky = Path(CGRect(origin: .zero, size: size))
        context.fill(sky, with: .linearGradient(
            Gradient(colors: HeLovesMePalette.daySky),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: layout.groundLevel),
        ))

        if scene.dusk > 0 {
            var dusk = context
            dusk.opacity = scene.dusk
            dusk.fill(sky, with: .linearGradient(
                Gradient(colors: HeLovesMePalette.duskSky),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: layout.groundLevel),
            ))
            var stars = Path()
            for index in 0..<32 {
                let twinkle = 0.5 + 0.5 * sin(time * 1.4 + Double(index) * 1.7)
                let radius = 0.6 + 1.1 * CGFloat(Self.noise(index, 3.1)) * CGFloat(0.55 + 0.45 * twinkle)
                let center = CGPoint(
                    x: CGFloat(Self.noise(index, 12.9898)) * size.width,
                    y: CGFloat(Self.noise(index, 78.233)) * layout.headCenter.y * 0.95,
                )
                stars.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            dusk.fill(stars, with: .color(.white.opacity(0.85)))
        }

        let glow = layout.petalLength * 3.2
        context.fill(
            Path(ellipseIn: CGRect(x: scene.headCenter.x - glow, y: scene.headCenter.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.42), .white.opacity(0)]),
                center: scene.headCenter,
                startRadius: 0,
                endRadius: glow,
            ),
        )
    }

    private func drawGround(in context: GraphicsContext, size: CGSize) {
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: size.height))
        for step in 0...48 {
            let x = size.width * CGFloat(step) / 48
            ground.addLine(to: CGPoint(x: x, y: layout.groundY(at: x)))
        }
        ground.addLine(to: CGPoint(x: size.width, y: size.height))
        ground.closeSubpath()

        var grass = Path()
        let count = max(12, Int(size.width / 7))
        let half = max(1, layout.petalWidth * 0.08)
        for index in 0..<count {
            let x = (CGFloat(index) + CGFloat(Self.noise(index, 12.9898))) * size.width / CGFloat(count)
            let base = layout.groundY(at: x) + 2
            let height = layout.petalWidth * (0.7 + CGFloat(Self.noise(index, 78.233)) * 0.9)
            let lean = height * (CGFloat(Self.noise(index, 39.425) - 0.5) * 0.6 + CGFloat(sin(time * 1.3 + Double(index) * 0.7)) * 0.12)
            grass.move(to: CGPoint(x: x - half, y: base))
            grass.addQuadCurve(
                to: CGPoint(x: x + lean, y: base - height),
                control: CGPoint(x: x - half * 0.5 + lean * 0.3, y: base - height * 0.6),
            )
            grass.addQuadCurve(
                to: CGPoint(x: x + half, y: base),
                control: CGPoint(x: x + half * 0.5 + lean * 0.3, y: base - height * 0.5),
            )
            grass.closeSubpath()
        }

        let top = CGPoint(x: 0, y: layout.groundLevel - layout.moundHeight)
        let bottom = CGPoint(x: 0, y: size.height)
        context.fill(ground, with: .linearGradient(Gradient(colors: HeLovesMePalette.dayGround), startPoint: top, endPoint: bottom))
        context.fill(grass, with: .color(HeLovesMePalette.dayGrass))
        if scene.dusk > 0 {
            var dusk = context
            dusk.opacity = scene.dusk
            dusk.fill(ground, with: .linearGradient(Gradient(colors: HeLovesMePalette.duskGround), startPoint: top, endPoint: bottom))
            dusk.fill(grass, with: .color(HeLovesMePalette.duskGrass))
        }
    }

    private func drawStem(in context: GraphicsContext) {
        let base = layout.stemBase
        let head = scene.headCenter
        let control = CGPoint(x: base.x, y: (base.y + head.y) / 2)
        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: head, control: control)

        for (position, angle, size) in [(0.3, -2.55, 0.9), (0.5, -0.55, 0.75)] {
            let t = CGFloat(position)
            let point = CGPoint(
                x: (1 - t) * (1 - t) * base.x + 2 * (1 - t) * t * control.x + t * t * head.x,
                y: (1 - t) * (1 - t) * base.y + 2 * (1 - t) * t * control.y + t * t * head.y,
            )
            let length = layout.petalLength * CGFloat(size)
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -length * 0.3))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: length * 0.3))
            var vein = Path()
            vein.move(to: .zero)
            vein.addLine(to: CGPoint(x: length * 0.8, y: 0))

            var local = context
            local.translateBy(x: point.x, y: point.y)
            local.rotate(by: .radians(angle + 0.05 * sin(time * 1.1 + position * 5)))
            local.fill(leaf, with: .linearGradient(
                Gradient(colors: [HeLovesMePalette.stem, HeLovesMePalette.leaf]),
                startPoint: .zero,
                endPoint: CGPoint(x: length, y: 0),
            ))
            local.stroke(vein, with: .color(HeLovesMePalette.stem.opacity(0.7)), lineWidth: max(0.5, length * 0.02))
        }

        context.stroke(
            stem,
            with: .color(HeLovesMePalette.stem),
            style: StrokeStyle(lineWidth: max(1, layout.centerRadius * 0.2), lineCap: .round),
        )
    }

    private func drawPetal(_ petal: Path, pose: HeLovesMePetalPose, in context: GraphicsContext) {
        let length = layout.petalLength
        var local = context
        local.translateBy(x: pose.center.x, y: pose.center.y)
        local.rotate(by: .radians(pose.angle))
        local.scaleBy(x: pose.scale, y: pose.scale)
        local.fill(petal, with: .linearGradient(
            Gradient(colors: [HeLovesMePalette.petalBase, HeLovesMePalette.petal, HeLovesMePalette.petal]),
            startPoint: CGPoint(x: -length / 2, y: 0),
            endPoint: CGPoint(x: length / 2, y: 0),
        ))
        local.stroke(petal, with: .color(HeLovesMePalette.petalEdge.opacity(0.55)), lineWidth: max(0.4, length * 0.008))
        var vein = Path()
        vein.move(to: CGPoint(x: -length * 0.36, y: 0))
        vein.addLine(to: CGPoint(x: length * 0.22, y: 0))
        local.stroke(vein, with: .color(HeLovesMePalette.petalEdge.opacity(0.3)), lineWidth: max(0.4, length * 0.007))
    }

    private func drawDisc(in context: GraphicsContext) {
        let radius = layout.centerRadius
        let head = scene.headCenter
        let shadow = radius * 1.15
        context.fill(
            Path(ellipseIn: CGRect(x: head.x - shadow, y: head.y - shadow, width: shadow * 2, height: shadow * 2)),
            with: .color(.black.opacity(0.07)),
        )
        context.fill(
            Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [HeLovesMePalette.disc, HeLovesMePalette.discEdge]),
                center: CGPoint(x: head.x - radius * 0.25, y: head.y - radius * 0.25),
                startRadius: 0,
                endRadius: radius * 1.25,
            ),
        )

        var seeds = Path()
        let count = 64
        for index in 0..<count {
            let angle = Double(index) * 2.399_963 + scene.headAngle
            let distance = radius * 0.86 * CGFloat((Double(index) + 0.5) / Double(count)).squareRoot()
            let dot = radius * (0.045 + 0.03 * distance / radius)
            let center = CGPoint(x: head.x + CGFloat(cos(angle)) * distance, y: head.y + CGFloat(sin(angle)) * distance)
            seeds.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
        }
        context.fill(seeds, with: .color(HeLovesMePalette.seed.opacity(0.42)))
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index + 1) * salt) * 43_758.5453
        return value - value.rounded(.down)
    }
}

struct HeLovesMePetal: Shape {
    func path(in rect: CGRect) -> Path {
        let length = rect.width
        let width = rect.height
        let base = CGPoint(x: rect.minX, y: rect.midY)
        var path = Path()
        path.move(to: base)
        path.addCurve(
            to: CGPoint(x: rect.minX + length * 0.72, y: rect.minY),
            control1: CGPoint(x: rect.minX + length * 0.2, y: rect.midY - width * 0.15),
            control2: CGPoint(x: rect.minX + length * 0.45, y: rect.minY),
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - width * 0.2),
            control1: CGPoint(x: rect.minX + length * 0.9, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.midY - width * 0.4),
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - length * 0.05, y: rect.midY),
            control: CGPoint(x: rect.maxX - length * 0.015, y: rect.midY - width * 0.06),
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + width * 0.2),
            control: CGPoint(x: rect.maxX - length * 0.015, y: rect.midY + width * 0.06),
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + length * 0.72, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.midY + width * 0.4),
            control2: CGPoint(x: rect.minX + length * 0.9, y: rect.maxY),
        )
        path.addCurve(
            to: base,
            control1: CGPoint(x: rect.minX + length * 0.45, y: rect.maxY),
            control2: CGPoint(x: rect.minX + length * 0.2, y: rect.midY + width * 0.15),
        )
        path.closeSubpath()
        return path
    }
}
