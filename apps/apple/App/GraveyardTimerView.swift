import SwiftUI

private enum GraveyardPalette {
    static let sky = [
        Color(red: 0.01, green: 0.02, blue: 0.05),
        Color(red: 0.05, green: 0.08, blue: 0.13),
        Color(red: 0.14, green: 0.2, blue: 0.22),
    ]
    static let partySky = [
        Color(red: 0.08, green: 0.02, blue: 0.13),
        Color(red: 0.24, green: 0.06, blue: 0.3),
        Color(red: 0.5, green: 0.2, blue: 0.12),
    ]
    static let haze = Color(red: 0.4, green: 0.62, blue: 0.45)
    static let hills = Color(red: 0.03, green: 0.04, blue: 0.06)
    static let ground = [Color(red: 0.07, green: 0.09, blue: 0.1), Color(red: 0.02, green: 0.025, blue: 0.035)]
    static let grass = Color(red: 0.08, green: 0.12, blue: 0.11)
    static let mound = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let iron = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let cloud = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let moon = Color(red: 0.94, green: 0.95, blue: 0.86)
    static let halo = Color(red: 0.72, green: 0.86, blue: 0.9)
    static let crater = Color(red: 0.78, green: 0.8, blue: 0.72)
    static let stone = [Color(red: 0.46, green: 0.49, blue: 0.51), Color(red: 0.22, green: 0.24, blue: 0.27)]
    static let stoneEdge = Color(red: 0.1, green: 0.11, blue: 0.14)
    static let moss = Color(red: 0.24, green: 0.36, blue: 0.2)
    static let dirt = Color(red: 0.2, green: 0.15, blue: 0.11)
    static let ghost = Color(red: 0.93, green: 0.98, blue: 1)
    static let ghostShade = Color(red: 0.62, green: 0.84, blue: 0.86)
    static let ghostGlow = Color(red: 0.5, green: 1, blue: 0.82)
    static let fog = Color(red: 0.72, green: 0.86, blue: 0.84)
    static let wisp = Color(red: 0.55, green: 1, blue: 0.7)
    static let face = Color(red: 0.03, green: 0.04, blue: 0.07)
    static let crowEye = Color(red: 1, green: 0.82, blue: 0.32)
    static let ink = Color(red: 0.84, green: 0.94, blue: 0.93)
    static let partyHues = [0.07, 0.78, 0.33, 0.12, 0.85]

    static func party(_ index: Int, shift: Double = 0) -> Color {
        let hue = partyHues[((index % partyHues.count) + partyHues.count) % partyHues.count] + shift
        return Color(hue: hue - hue.rounded(.down), saturation: 0.85, brightness: 1)
    }
}

struct GraveyardTimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var graveyard: Graveyard?

    let snapshot: TimerSnapshot

    var body: some View {
        GeometryReader { safeGeometry in
            GeometryReader { geometry in
                let key = Graveyard.Key(seed: snapshot.runID, size: geometry.size, goalSeconds: snapshot.goalSeconds)
                let graveyard = graveyard(for: key)

                TimelineView(.animation(
                    minimumInterval: 1.0 / 60,
                    paused: snapshot.status != .running || scenePhase != .active || reduceMotion,
                )) { context in
                    let elapsed = Graveyard.elapsed(snapshot: snapshot, at: context.date)
                    let scene = graveyard.scene(elapsed: elapsed, restSeconds: snapshot.restSeconds, settled: reduceMotion)
                    let caption = Graveyard.caption(mood: scene.mood)

                    ZStack(alignment: .top) {
                        GraveyardNight(layout: graveyard.layout, scene: scene, time: reduceMotion ? 0 : elapsed)
                            .accessibilityHidden(true)

                        VStack(spacing: 2) {
                            Text(snapshot.clockText)
                                .font(.system(size: 58, weight: .light, design: .serif))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))

                            Text(caption)
                                .font(.system(.title3, design: .serif).italic())
                                .id(caption)
                                .transition(.opacity)
                        }
                        .foregroundStyle(GraveyardPalette.ink)
                        .shadow(color: GraveyardPalette.ghostGlow.opacity(0.35), radius: 8)
                        .padding(.top, safeGeometry.safeAreaInsets.top + 82)
                        .animation(.easeInOut(duration: 0.6), value: caption)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(accessibilityStatus). \(snapshot.clockText) remaining. \(caption). \(snapshot.goalSeconds / 60) minute focus. \(snapshot.restSeconds / 60) minute rest.")
                    }
                }
                .onChange(of: key, initial: true) { _, key in
                    self.graveyard = self.graveyard(for: key)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func graveyard(for key: Graveyard.Key) -> Graveyard {
        if let graveyard, graveyard.key == key {
            return graveyard
        }
        return Graveyard(key: key)
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

struct GraveyardThemePreview: View {
    var body: some View {
        GeometryReader { geometry in
            let graveyard = Graveyard(key: Graveyard.Key(seed: UUID(uuid: (0x47, 0x68, 0x6F, 0x73, 0x74, 0x50, 0x61, 0x72, 0x74, 0x79, 0x42, 0x6F, 0x6F, 0x21, 0x21, 0x21)), size: geometry.size, goalSeconds: 1_500))

            ZStack(alignment: .top) {
                GraveyardNight(
                    layout: graveyard.layout,
                    scene: graveyard.scene(elapsed: 1_560, restSeconds: 300, settled: true),
                    time: 0,
                )

                Text("04:00")
                    .font(.system(size: 17, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(GraveyardPalette.ink)
                    .padding(.top, 12)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}


private struct GraveyardNight: View {
    let layout: GraveyardLayout
    let scene: GraveyardScene
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            drawSky(in: context, size: size)
            drawMoon(in: context)
            drawClouds(in: context, size: size)
            drawBats(in: context, size: size)
            drawHills(in: context, size: size)
            drawTree(in: context)
            drawGround(in: context, size: size)
            drawFence(in: context, size: size)

            let ghosts = Dictionary(uniqueKeysWithValues: scene.ghosts.map { ($0.grave, $0) })
            for row in GraveyardLayout.rows.indices {
                for (index, grave) in layout.graves.enumerated() where grave.row == row {
                    drawGrave(grave, index: index, tremble: scene.trembles[index], in: context)
                    if let pose = ghosts[index] {
                        drawGhost(pose, grave: grave, in: context)
                    }
                }
                drawFog(in: context, size: size, depth: layout.graves.first { $0.row == row }?.ground.y ?? layout.horizon, layer: row)
            }

            drawWisps(in: context, size: size)
            drawFog(in: context, size: size, depth: size.height * 0.97, layer: 3)
            if scene.party > 0 {
                drawParty(in: context, size: size, ghosts: scene.ghosts)
            }
            drawVignette(in: context, size: size)
        }
    }

    private func drawSky(in context: GraphicsContext, size: CGSize) {
        let sky = Path(CGRect(origin: .zero, size: size))
        let end = CGPoint(x: 0, y: layout.horizon)
        context.fill(sky, with: .linearGradient(Gradient(colors: GraveyardPalette.sky), startPoint: .zero, endPoint: end))
        if scene.party > 0 {
            var party = context
            party.opacity = scene.party * 0.85
            party.fill(sky, with: .linearGradient(Gradient(colors: GraveyardPalette.partySky), startPoint: .zero, endPoint: end))
        }
        context.fill(
            Path(CGRect(x: 0, y: layout.horizon - size.height * 0.16, width: size.width, height: size.height * 0.2)),
            with: .linearGradient(
                Gradient(colors: [GraveyardPalette.haze.opacity(0), GraveyardPalette.haze.opacity(0.16 * (1 - scene.party))]),
                startPoint: CGPoint(x: 0, y: layout.horizon - size.height * 0.16),
                endPoint: CGPoint(x: 0, y: layout.horizon),
            ),
        )

        var stars = Path()
        for index in 0..<56 {
            let twinkle = 0.5 + 0.5 * sin(time * 1.6 + Double(index) * 2.3)
            let radius = 0.4 + 1 * CGFloat(Self.noise(index, 3.1)) * CGFloat(0.4 + 0.6 * twinkle)
            let center = CGPoint(
                x: CGFloat(Self.noise(index, 12.9898)) * size.width,
                y: CGFloat(Self.noise(index, 78.233)) * layout.horizon * 0.85,
            )
            stars.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        context.fill(stars, with: .color(.white.opacity(0.7)))
    }

    private func drawMoon(in context: GraphicsContext) {
        let center = layout.moonCenter
        let radius = layout.moonRadius
        let glow = radius * 3.6
        let halo = Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2))
        context.fill(halo, with: .radialGradient(
            Gradient(colors: [GraveyardPalette.halo.opacity(0.42), GraveyardPalette.halo.opacity(0.1), GraveyardPalette.halo.opacity(0)]),
            center: center,
            startRadius: radius * 0.9,
            endRadius: glow,
        ))
        if scene.party > 0 {
            var party = context
            party.opacity = scene.party * 0.55
            let hue = GraveyardPalette.party(Int(time / 2), shift: 0)
            party.fill(halo, with: .radialGradient(Gradient(colors: [hue, hue.opacity(0)]), center: center, startRadius: radius, endRadius: glow))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [.white, GraveyardPalette.moon, GraveyardPalette.crater]),
                center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
                startRadius: 0,
                endRadius: radius * 1.6,
            ),
        )
        var craters = Path()
        for (dx, dy, size) in [(-0.35, -0.1, 0.22), (0.25, 0.3, 0.16), (0.3, -0.35, 0.12), (-0.1, 0.45, 0.1), (0.05, -0.02, 0.07)] {
            let crater = radius * CGFloat(size)
            craters.addEllipse(in: CGRect(
                x: center.x + radius * CGFloat(dx) - crater,
                y: center.y + radius * CGFloat(dy) - crater,
                width: crater * 2,
                height: crater * 2,
            ))
        }
        context.fill(craters, with: .color(GraveyardPalette.crater.opacity(0.55)))
    }

    private func drawClouds(in context: GraphicsContext, size: CGSize) {
        let radius = layout.moonRadius
        for index in 0..<4 {
            let width = radius * CGFloat(3 + Self.noise(index, 2.2) * 2)
            let span = size.width + width * 2
            let x = (CGFloat(time * (3 + Double(index) * 2)) + span * CGFloat(Self.noise(index, 7.7))).truncatingRemainder(dividingBy: span) - width
            let y = layout.moonCenter.y + radius * CGFloat(Double(index) * 0.9 - 1.6)
            for puff in 0..<7 {
                let reach = width * CGFloat(0.16 + 0.1 * Self.noise(index * 7 + puff, 4.1))
                let center = CGPoint(
                    x: x + width * CGFloat(puff) / 6,
                    y: y + radius * CGFloat(0.3 * Self.noise(index * 7 + puff, 6.6) - 0.15),
                )
                var puffContext = context
                puffContext.scaleBy(x: 1, y: 0.32)
                let scaled = CGPoint(x: center.x, y: center.y / 0.32)
                puffContext.fill(
                    Path(ellipseIn: CGRect(x: scaled.x - reach, y: scaled.y - reach, width: reach * 2, height: reach * 2)),
                    with: .radialGradient(
                        Gradient(colors: [GraveyardPalette.cloud.opacity(0.7), GraveyardPalette.cloud.opacity(0.35), GraveyardPalette.cloud.opacity(0)]),
                        center: scaled,
                        startRadius: 0,
                        endRadius: reach,
                    ),
                )
            }
        }
    }

    private func drawBats(in context: GraphicsContext, size: CGSize) {
        let wing = layout.moonRadius * 0.28
        for index in 0..<3 {
            let speed = 18 + Double(index) * 7
            let span = size.width + wing * 6
            let x = (CGFloat(time * speed) + span * CGFloat(Self.noise(index, 4.4))).truncatingRemainder(dividingBy: span) - wing * 3
            let y = layout.moonCenter.y - layout.moonRadius * CGFloat(1.4 - Double(index) * 0.9) + wing * CGFloat(sin(time * 1.3 + Double(index)))
            let flap = CGFloat(sin(time * 14 + Double(index) * 2))
            let scale = 1 - CGFloat(index) * 0.2
            var local = context
            local.translateBy(x: x, y: y)
            local.scaleBy(x: scale, y: scale)
            var bat = Path()
            bat.move(to: CGPoint(x: 0, y: 0))
            bat.addQuadCurve(to: CGPoint(x: -wing, y: -wing * 0.5 * flap), control: CGPoint(x: -wing * 0.5, y: -wing * 0.6 * flap - wing * 0.2))
            bat.addQuadCurve(to: CGPoint(x: -wing * 0.4, y: wing * 0.1), control: CGPoint(x: -wing * 0.7, y: wing * 0.1))
            bat.addQuadCurve(to: CGPoint(x: 0, y: wing * 0.25), control: CGPoint(x: -wing * 0.2, y: 0))
            bat.addQuadCurve(to: CGPoint(x: wing * 0.4, y: wing * 0.1), control: CGPoint(x: wing * 0.2, y: 0))
            bat.addQuadCurve(to: CGPoint(x: wing, y: -wing * 0.5 * flap), control: CGPoint(x: wing * 0.7, y: wing * 0.1))
            bat.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: wing * 0.5, y: -wing * 0.6 * flap - wing * 0.2))
            bat.closeSubpath()
            bat.addEllipse(in: CGRect(x: -wing * 0.13, y: -wing * 0.15, width: wing * 0.26, height: wing * 0.4))
            local.fill(bat, with: .color(GraveyardPalette.face))
        }
    }

    private func drawHills(in context: GraphicsContext, size: CGSize) {
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: size.height))
        for step in 0...48 {
            let x = size.width * CGFloat(step) / 48
            hills.addLine(to: CGPoint(x: x, y: layout.hillY(at: x)))
        }
        hills.addLine(to: CGPoint(x: size.width, y: size.height))
        hills.closeSubpath()
        context.fill(hills, with: .color(GraveyardPalette.hills))
    }

    private func drawTree(in context: GraphicsContext) {
        let base = CGPoint(x: layout.size.width * 0.12, y: layout.hillY(at: layout.size.width * 0.12) + 4)
        let height = layout.size.height * 0.12
        let depths = 6
        var levels = Array(repeating: Path(), count: depths + 1)
        var perch = base
        func branch(from start: CGPoint, angle: Double, length: CGFloat, depth: Int) {
            let sway = 0.025 * sin(time * 0.7 + Double(depth)) * Double(depths - depth)
            let bend = 0.25 * (Self.noise(depth * 7 + Int(length), 3.3) - 0.5)
            let end = CGPoint(x: start.x + CGFloat(cos(angle + sway)) * length, y: start.y + CGFloat(sin(angle + sway)) * length)
            let middle = CGPoint(
                x: (start.x + end.x) / 2 + CGFloat(cos(angle + .pi / 2)) * length * CGFloat(bend),
                y: (start.y + end.y) / 2 + CGFloat(sin(angle + .pi / 2)) * length * CGFloat(bend),
            )
            levels[depth].move(to: start)
            levels[depth].addQuadCurve(to: end, control: middle)
            if depth == 3 && end.x > perch.x {
                perch = end
            }
            guard depth > 0 else { return }
            branch(from: end, angle: angle - 0.5 - 0.12 * Double(depth % 2), length: length * 0.7, depth: depth - 1)
            branch(from: end, angle: angle + 0.42 + 0.14 * Double(depth % 3), length: length * 0.64, depth: depth - 1)
        }
        branch(from: base, angle: -.pi / 2 + 0.1, length: height, depth: depths)
        for (depth, path) in levels.enumerated() {
            context.stroke(
                path,
                with: .color(GraveyardPalette.hills),
                style: StrokeStyle(lineWidth: max(0.8, height * 0.07 * CGFloat(depth + 1) / CGFloat(depths + 1)), lineCap: .round),
            )
        }

        let crow = height * 0.13
        var local = context
        local.translateBy(x: perch.x, y: perch.y - crow * 0.35)
        var body = Path(ellipseIn: CGRect(x: -crow * 0.5, y: -crow * 0.35, width: crow, height: crow * 0.62))
        body.addEllipse(in: CGRect(x: crow * 0.22, y: -crow * 0.62, width: crow * 0.42, height: crow * 0.4))
        body.move(to: CGPoint(x: crow * 0.6, y: -crow * 0.48))
        body.addLine(to: CGPoint(x: crow * 0.88, y: -crow * 0.38))
        body.addLine(to: CGPoint(x: crow * 0.58, y: -crow * 0.34))
        body.closeSubpath()
        body.move(to: CGPoint(x: -crow * 0.4, y: -crow * 0.05))
        body.addLine(to: CGPoint(x: -crow * 0.95, y: crow * 0.25))
        body.addLine(to: CGPoint(x: -crow * 0.3, y: crow * 0.2))
        body.closeSubpath()
        local.fill(body, with: .color(GraveyardPalette.face))
        let blink = (time + 1.7).truncatingRemainder(dividingBy: 5.3) < 0.18
        if !blink {
            let eye = max(0.6, crow * 0.06)
            local.fill(
                Path(ellipseIn: CGRect(x: crow * 0.46 - eye, y: -crow * 0.47 - eye, width: eye * 2, height: eye * 2)),
                with: .color(GraveyardPalette.crowEye),
            )
        }
    }

    private func drawGround(in context: GraphicsContext, size: CGSize) {
        let top = layout.horizon + size.height * 0.02
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: size.height))
        for step in 0...32 {
            let x = size.width * CGFloat(step) / 32
            ground.addLine(to: CGPoint(x: x, y: top + size.height * 0.008 * CGFloat(sin(Double(step) * 0.9))))
        }
        ground.addLine(to: CGPoint(x: size.width, y: size.height))
        ground.closeSubpath()
        context.fill(ground, with: .linearGradient(
            Gradient(colors: GraveyardPalette.ground),
            startPoint: CGPoint(x: 0, y: top),
            endPoint: CGPoint(x: 0, y: size.height),
        ))
        let pool = layout.moonRadius * 4
        let light = CGPoint(x: layout.moonCenter.x - layout.moonRadius, y: top + size.height * 0.08)
        context.fill(
            Path(ellipseIn: CGRect(x: light.x - pool * 1.4, y: light.y - pool * 0.4, width: pool * 2.8, height: pool * 0.8)),
            with: .radialGradient(
                Gradient(colors: [GraveyardPalette.halo.opacity(0.07), GraveyardPalette.halo.opacity(0)]),
                center: light,
                startRadius: 0,
                endRadius: pool * 1.4,
            ),
        )
    }

    private func drawFence(in context: GraphicsContext, size: CGSize) {
        let base = layout.horizon + size.height * 0.035
        let height = size.height * 0.05
        let spacing = max(4, layout.stoneWidth * 0.2)
        var fence = Path()
        var x = spacing / 2
        while x < size.width {
            let lean = CGFloat(Self.noise(Int(x), 1.3) - 0.5) * spacing * 0.3
            let top = base - height * CGFloat(0.85 + 0.15 * Self.noise(Int(x), 5.7))
            fence.move(to: CGPoint(x: x, y: base))
            fence.addLine(to: CGPoint(x: x + lean, y: top))
            fence.move(to: CGPoint(x: x + lean - spacing * 0.12, y: top + spacing * 0.1))
            fence.addLine(to: CGPoint(x: x + lean, y: top - spacing * 0.3))
            fence.addLine(to: CGPoint(x: x + lean + spacing * 0.12, y: top + spacing * 0.1))
            x += spacing
        }
        for rail in [0.25, 0.75] {
            fence.move(to: CGPoint(x: 0, y: base - height * CGFloat(rail)))
            fence.addLine(to: CGPoint(x: size.width, y: base - height * CGFloat(rail) + size.height * 0.004))
        }
        context.stroke(fence, with: .color(GraveyardPalette.iron), style: StrokeStyle(lineWidth: max(0.8, spacing * 0.1), lineCap: .round, lineJoin: .round))
    }

    private func drawGrave(_ grave: GraveyardGrave, index: Int, tremble: Double, in context: GraphicsContext) {
        let stone = layout.stoneSize(grave)
        let ground = grave.ground
        var shadow = Path()
        let cast = CGVector(dx: -stone.height * 0.55, dy: stone.width * 0.18)
        shadow.move(to: CGPoint(x: ground.x - stone.width * 0.5, y: ground.y))
        shadow.addLine(to: CGPoint(x: ground.x + stone.width * 0.5, y: ground.y))
        shadow.addLine(to: CGPoint(x: ground.x + stone.width * 0.3 + cast.dx, y: ground.y + cast.dy))
        shadow.addLine(to: CGPoint(x: ground.x - stone.width * 0.7 + cast.dx, y: ground.y + cast.dy))
        shadow.closeSubpath()
        context.fill(shadow, with: .color(.black.opacity(0.35)))
        let mound = CGRect(x: ground.x - stone.width * 0.62, y: ground.y - stone.width * 0.04, width: stone.width * 1.24, height: stone.width * 0.36)
        context.fill(Path(ellipseIn: mound), with: .linearGradient(
            Gradient(colors: [GraveyardPalette.dirt.opacity(0.7), GraveyardPalette.mound]),
            startPoint: CGPoint(x: mound.midX, y: mound.minY),
            endPoint: CGPoint(x: mound.midX, y: mound.maxY),
        ))

        var local = context
        local.translateBy(x: ground.x, y: ground.y)
        local.rotate(by: .radians(grave.tilt + tremble))
        let rect = CGRect(x: -stone.width / 2, y: -stone.height, width: stone.width, height: stone.height)
        let shape = GraveyardTombstone(style: grave.style).path(in: rect)
        local.fill(shape, with: .linearGradient(
            Gradient(colors: GraveyardPalette.stone),
            startPoint: CGPoint(x: rect.maxX, y: rect.minY),
            endPoint: CGPoint(x: rect.minX, y: rect.maxY),
        ))
        var weathered = local
        weathered.clip(to: shape)
        weathered.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [GraveyardPalette.moss.opacity(0.4), GraveyardPalette.moss.opacity(0)]),
            startPoint: CGPoint(x: 0, y: rect.maxY),
            endPoint: CGPoint(x: 0, y: rect.maxY - stone.height * 0.28),
        ))
        var speckles = Path()
        for speck in 0..<10 {
            let dot = stone.width * CGFloat(0.015 + 0.025 * Self.noise(index * 10 + speck, 2.9))
            speckles.addEllipse(in: CGRect(
                x: rect.minX + rect.width * CGFloat(Self.noise(index * 10 + speck, 6.3)) - dot,
                y: rect.minY + rect.height * CGFloat(Self.noise(index * 10 + speck, 8.7)) - dot,
                width: dot * 2,
                height: dot * 2,
            ))
        }
        weathered.fill(speckles, with: .color(GraveyardPalette.stoneEdge.opacity(0.35)))
        if index % 3 == 1 {
            var crack = Path()
            crack.move(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.05))
            crack.addLine(to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.22))
            crack.addLine(to: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.34))
            crack.addLine(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.5))
            weathered.stroke(crack, with: .color(GraveyardPalette.stoneEdge), lineWidth: max(0.6, stone.width * 0.025))
        }
        local.stroke(shape, with: .color(GraveyardPalette.stoneEdge), lineWidth: max(0.6, stone.width * 0.03))
        local.stroke(shape, with: .linearGradient(
            Gradient(colors: [GraveyardPalette.halo.opacity(0.55), GraveyardPalette.halo.opacity(0)]),
            startPoint: CGPoint(x: rect.maxX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.midY),
        ), lineWidth: max(0.6, stone.width * 0.025))
        if grave.style != .cross {
            let engraving = CGPoint(x: 0, y: -stone.height * 0.55)
            let font = Font.system(size: stone.width * 0.2, weight: .semibold, design: .serif)
            local.draw(Text("RIP").font(font).foregroundStyle(GraveyardPalette.halo.opacity(0.18)), at: CGPoint(x: engraving.x, y: engraving.y + 0.8))
            local.draw(Text("RIP").font(font).foregroundStyle(GraveyardPalette.stoneEdge.opacity(0.85)), at: engraving)
        }

        var grass = Path()
        for blade in 0..<9 {
            let x = ground.x + stone.width * (CGFloat(blade) / 8 - 0.5) * 1.3
            let height = stone.width * (0.08 + 0.16 * CGFloat(Self.noise(index * 9 + blade, 9.1)))
            let lean = height * CGFloat(Self.noise(index * 9 + blade, 4.7) - 0.5) + height * 0.1 * CGFloat(sin(time * 1.1 + Double(blade)))
            grass.move(to: CGPoint(x: x - 1.2, y: ground.y + 3))
            grass.addQuadCurve(to: CGPoint(x: x + lean, y: ground.y - height), control: CGPoint(x: x, y: ground.y - height * 0.5))
            grass.addQuadCurve(to: CGPoint(x: x + 1.2, y: ground.y + 3), control: CGPoint(x: x + 0.6, y: ground.y - height * 0.4))
            grass.closeSubpath()
        }
        context.fill(grass, with: .color(GraveyardPalette.grass))
    }

    private func drawGhost(_ pose: GraveyardGhostPose, grave: GraveyardGrave, in context: GraphicsContext) {
        let size = layout.ghostSize(grave)
        let emergence = layout.emergence(grave)
        let bottom = emergence.y + size.height - CGFloat(pose.rise) * size.height * 1.15 + pose.offset.dy
        let center = CGPoint(x: emergence.x + pose.offset.dx, y: bottom - size.height / 2)
        let presence = min(1, max(0, pose.rise))

        drawDisturbance(pose, at: emergence, size: size, in: context)

        var clipped = context
        clipped.clip(to: Path(CGRect(x: 0, y: 0, width: layout.size.width, height: emergence.y)))
        let glow = size.height * 1.1
        clipped.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [GraveyardPalette.ghostGlow.opacity(0.32 * presence), GraveyardPalette.ghostGlow.opacity(0.08 * presence), GraveyardPalette.ghostGlow.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: glow,
            ),
        )

        var local = clipped
        local.translateBy(x: center.x, y: center.y)
        local.rotate(by: .radians(pose.tilt))
        local.scaleBy(x: CGFloat(abs(pose.facing) < 0.15 ? 0.15 : pose.facing), y: 1)
        local.opacity = 0.9

        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let armLength = size.width * 0.34
        var arms = Path()
        for side in [-1.0, 1.0] {
            let shoulder = CGPoint(x: rect.midX + CGFloat(side) * size.width * 0.3, y: rect.minY + size.height * 0.46)
            let angle = side > 0 ? 0.9 - pose.arms * 1.9 : .pi - 0.9 + pose.arms * 1.9
            let hand = CGPoint(x: shoulder.x + CGFloat(cos(angle)) * armLength, y: shoulder.y + CGFloat(sin(angle)) * armLength)
            let droop = CGPoint(
                x: (shoulder.x + hand.x) / 2 + CGFloat(side) * armLength * 0.1,
                y: (shoulder.y + hand.y) / 2 + armLength * 0.25,
            )
            arms.move(to: shoulder)
            arms.addQuadCurve(to: hand, control: droop)
        }
        local.stroke(arms, with: .color(GraveyardPalette.ghost.opacity(0.92)), style: StrokeStyle(lineWidth: size.width * 0.14, lineCap: .round))

        let body = GraveyardGhost(wave: time * 4 + Double(grave.ground.x)).path(in: rect)
        local.fill(body, with: .linearGradient(
            Gradient(colors: [GraveyardPalette.ghost, GraveyardPalette.ghost, GraveyardPalette.ghostShade.opacity(0.7), GraveyardPalette.ghostShade.opacity(0)]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY),
        ))
        if scene.party > 0 {
            var tint = local
            tint.opacity = scene.party * 0.3
            tint.fill(body, with: .linearGradient(
                Gradient(colors: [GraveyardPalette.party(pose.grave, shift: time * 0.05), GraveyardPalette.party(pose.grave, shift: time * 0.05).opacity(0)]),
                startPoint: CGPoint(x: 0, y: rect.minY),
                endPoint: CGPoint(x: 0, y: rect.maxY),
            ))
        }

        let eye = size.width * 0.12
        let blink = (time + Double(pose.grave) * 1.3).truncatingRemainder(dividingBy: 4 + Double(pose.grave % 3)) < 0.15 ? 0.15 : 1
        var face = Path()
        for side in [-1.0, 1.0] {
            let eyeCenter = CGPoint(x: rect.midX + CGFloat(side) * size.width * 0.16, y: rect.minY + size.height * 0.3)
            var socket = Path(ellipseIn: CGRect(x: -eye / 2, y: -eye * 0.75 * CGFloat(blink), width: eye, height: eye * 1.5 * CGFloat(blink)))
            socket = socket.applying(CGAffineTransform(rotationAngle: CGFloat(side) * -0.25).concatenating(CGAffineTransform(translationX: eyeCenter.x, y: eyeCenter.y)))
            face.addPath(socket)
        }
        let mouthTop = rect.minY + size.height * 0.45
        if scene.party > 0.5 {
            face.move(to: CGPoint(x: rect.midX - eye, y: mouthTop))
            face.addQuadCurve(to: CGPoint(x: rect.midX + eye, y: mouthTop), control: CGPoint(x: rect.midX, y: mouthTop + eye * 2.2))
            face.closeSubpath()
        } else {
            let mouth = eye * CGFloat(0.7 + 0.5 * pose.arms)
            face.addEllipse(in: CGRect(x: rect.midX - mouth / 2, y: mouthTop, width: mouth, height: mouth * (1.3 + CGFloat(pose.arms) * 0.8)))
        }
        local.fill(face, with: .color(GraveyardPalette.face))
        if scene.party <= 0.5 {
            var gleam = Path()
            for side in [-1.0, 1.0] {
                let dot = eye * 0.16
                gleam.addEllipse(in: CGRect(
                    x: rect.midX + CGFloat(side) * size.width * 0.16 - dot,
                    y: rect.minY + size.height * 0.3 - dot * CGFloat(blink),
                    width: dot * 2,
                    height: dot * 2 * CGFloat(blink),
                ))
            }
            local.fill(gleam, with: .color(GraveyardPalette.ghostGlow.opacity(0.9)))
        }
    }

    private func drawDisturbance(_ pose: GraveyardGhostPose, at emergence: CGPoint, size: CGSize, in context: GraphicsContext) {
        let lasting: TimeInterval = 1.6
        guard pose.age > 0, pose.age < lasting else { return }
        let fade = 1 - pose.age / lasting
        let spread = size.width * CGFloat(0.4 + pose.age * 0.5)
        context.fill(
            Path(ellipseIn: CGRect(x: emergence.x - spread, y: emergence.y - spread * 0.35, width: spread * 2, height: spread * 0.6)),
            with: .radialGradient(
                Gradient(colors: [GraveyardPalette.fog.opacity(0.4 * fade), GraveyardPalette.fog.opacity(0)]),
                center: emergence,
                startRadius: 0,
                endRadius: spread,
            ),
        )
        var clods = Path()
        for clod in 0..<7 {
            let direction = (Self.noise(clod + pose.grave * 7, 3.7) - 0.5) * 2.4
            let speed = 1.6 + Self.noise(clod + pose.grave * 7, 9.2) * 1.4
            let t = pose.age
            let point = CGPoint(
                x: emergence.x + size.width * CGFloat(direction * t * 0.9),
                y: emergence.y - size.height * CGFloat(speed * t - 3.2 * t * t),
            )
            guard point.y <= emergence.y + 2 else { continue }
            let radius = size.width * CGFloat(0.025 + 0.025 * Self.noise(clod, 5.5))
            clods.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        context.fill(clods, with: .color(GraveyardPalette.dirt.opacity(fade)))
    }

    private func drawWisps(in context: GraphicsContext, size: CGSize) {
        guard scene.party < 1 else { return }
        var wisps = context
        wisps.opacity = 1 - scene.party
        for index in 0..<3 {
            let drift = time * (0.12 + 0.05 * Double(index)) + Double(index) * 2.1
            let center = CGPoint(
                x: size.width * CGFloat(0.5 + 0.42 * sin(drift)),
                y: layout.horizon + (size.height - layout.horizon) * CGFloat(0.2 + 0.3 * Self.noise(index, 2.6)) + size.height * 0.02 * CGFloat(sin(time * 0.9 + Double(index) * 1.7)),
            )
            let pulse = 0.55 + 0.45 * sin(time * 2.3 + Double(index) * 2)
            let radius = max(1, layout.stoneWidth * 0.03)
            let halo = radius * 9
            wisps.fill(
                Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(colors: [GraveyardPalette.wisp.opacity(0.4 * pulse), GraveyardPalette.wisp.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: halo,
                ),
            )
            wisps.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(GraveyardPalette.wisp.opacity(0.5 + 0.5 * pulse)),
            )
        }
    }

    private func drawFog(in context: GraphicsContext, size: CGSize, depth: CGFloat, layer: Int) {
        for band in 0..<3 {
            let index = layer * 3 + band
            let width = size.width * CGFloat(0.7 + 0.6 * Self.noise(index, 5.3))
            let span = size.width + width
            let speed = 4 + 5 * Self.noise(index, 2.7)
            let travel = (CGFloat(time * speed) + span * CGFloat(Self.noise(index, 8.8))).truncatingRemainder(dividingBy: span)
            let x = band.isMultiple(of: 2) ? travel - width : size.width - travel
            let height = size.height * CGFloat(0.035 + 0.02 * Self.noise(index, 1.1))
            let rect = CGRect(x: x, y: depth - height * CGFloat(0.2 + 0.5 * Self.noise(index, 3.9)), width: width, height: height)
            var fog = context
            fog.scaleBy(x: 1, y: rect.height / rect.width)
            let center = CGPoint(x: rect.midX, y: rect.midY * rect.width / rect.height)
            fog.fill(
                Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width)),
                with: .radialGradient(
                    Gradient(colors: [GraveyardPalette.fog.opacity(0.16), GraveyardPalette.fog.opacity(0.06), GraveyardPalette.fog.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: width / 2,
                ),
            )
        }
    }

    private func drawParty(in context: GraphicsContext, size: CGSize, ghosts: [GraveyardGhostPose]) {
        var party = context
        party.opacity = scene.party

        let bulbs = 14
        var wire = Path()
        let anchorLeft = CGPoint(x: 0, y: layout.horizon - size.height * 0.08)
        let anchorRight = CGPoint(x: size.width, y: layout.horizon - size.height * 0.12)
        let sag = CGPoint(x: size.width / 2, y: layout.horizon + size.height * 0.02)
        wire.move(to: anchorLeft)
        wire.addQuadCurve(to: anchorRight, control: sag)
        party.stroke(wire, with: .color(GraveyardPalette.face), lineWidth: 1)
        for index in 0..<bulbs {
            let t = (CGFloat(index) + 0.5) / CGFloat(bulbs)
            let point = CGPoint(
                x: (1 - t) * (1 - t) * anchorLeft.x + 2 * (1 - t) * t * sag.x + t * t * anchorRight.x,
                y: (1 - t) * (1 - t) * anchorLeft.y + 2 * (1 - t) * t * sag.y + t * t * anchorRight.y,
            )
            let on = sin(time * 4 + Double(index) * 1.3) > -0.3
            let color = GraveyardPalette.party(index + Int(time / 1.5))
            let radius = max(2, layout.stoneWidth * 0.05)
            if on {
                party.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius * 4, y: point.y - radius * 3, width: radius * 8, height: radius * 8)),
                    with: .radialGradient(Gradient(colors: [color.opacity(0.5), color.opacity(0)]), center: CGPoint(x: point.x, y: point.y + radius), startRadius: 0, endRadius: radius * 4),
                )
            }
            party.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y, width: radius * 2, height: radius * 2.6)),
                with: .color(on ? color : color.opacity(0.3)),
            )
        }

        for index in 0..<10 {
            let color = GraveyardPalette.party(index)
            let center = CGPoint(
                x: size.width * CGFloat(0.5 + 0.45 * sin(time * (0.3 + Self.noise(index, 1.9) * 0.4) + Double(index) * 1.7)),
                y: layout.horizon - size.height * CGFloat(0.06 + 0.18 * Self.noise(index, 6.1)) + size.height * 0.03 * CGFloat(sin(time * 1.2 + Double(index))),
            )
            let radius = max(1.5, layout.stoneWidth * 0.06)
            party.fill(
                Path(ellipseIn: CGRect(x: center.x - radius * 4, y: center.y - radius * 4, width: radius * 8, height: radius * 8)),
                with: .radialGradient(Gradient(colors: [color.opacity(0.6), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius * 4),
            )
            party.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.white))
        }

        for pose in ghosts where pose.rise > 0.8 {
            let grave = layout.graves[pose.grave]
            let ghost = layout.ghostSize(grave)
            let top = layout.emergence(grave).y - ghost.height * 1.15 + pose.offset.dy
            for note in 0..<2 {
                let cycle = (time * 0.5 + Double(note) * 0.5 + Double(pose.grave) * 0.37).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(
                    x: grave.ground.x + pose.offset.dx + ghost.width * CGFloat(0.5 + 0.3 * sin(cycle * 6 + Double(note))),
                    y: top - ghost.height * CGFloat(cycle * 0.9),
                )
                var fading = party
                fading.opacity = scene.party * (1 - cycle)
                fading.draw(
                    Text(note == 0 ? "♪" : "♫")
                        .font(.system(size: ghost.width * 0.3, weight: .bold))
                        .foregroundStyle(GraveyardPalette.party(pose.grave + note)),
                    at: point,
                )
            }
        }
    }

    private func drawVignette(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.black.opacity(0), .black.opacity(0.55)]),
                center: center,
                startRadius: min(size.width, size.height) * 0.4,
                endRadius: max(size.width, size.height) * 0.75,
            ),
        )
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index + 1) * salt) * 43_758.5453
        return value - value.rounded(.down)
    }
}

struct GraveyardGhost: Shape {
    var wave: Double = 0

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let head = width * 0.4
        let crown = CGPoint(x: rect.midX, y: rect.minY + head)
        let hem = height * 0.1
        let tails = 5
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - head, y: crown.y))
        path.addArc(center: crown, radius: head, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - hem * 0.3),
            control1: CGPoint(x: rect.midX + head, y: crown.y + height * 0.3),
            control2: CGPoint(x: rect.maxX - width * 0.06, y: rect.maxY - hem * 3),
        )
        for index in 0..<tails {
            let start = rect.maxX - width * CGFloat(index) / CGFloat(tails)
            let end = rect.maxX - width * CGFloat(index + 1) / CGFloat(tails)
            let segment = start - end
            let curl = CGFloat(sin(wave + Double(index) * 1.6))
            let tip = rect.maxY - hem * 0.3 * (1 + CGFloat(sin(wave * 0.8 + Double(index + 1) * 2.1))) / 2
            let valley = CGPoint(x: (start + end) / 2, y: rect.maxY - hem * 2.2)
            path.addQuadCurve(to: valley, control: CGPoint(x: start - segment * 0.15 + curl * segment * 0.12, y: rect.maxY - hem * 0.9))
            path.addQuadCurve(to: CGPoint(x: end, y: tip), control: CGPoint(x: end + segment * 0.2 + curl * segment * 0.12, y: rect.maxY - hem * 1.1))
        }
        path.addCurve(
            to: CGPoint(x: rect.midX - head, y: crown.y),
            control1: CGPoint(x: rect.minX + width * 0.06, y: rect.maxY - hem * 3),
            control2: CGPoint(x: rect.midX - head, y: crown.y + height * 0.3),
        )
        path.closeSubpath()
        return path
    }
}

struct GraveyardTombstone: Shape {
    let style: GraveyardGrave.Style

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        var path = Path()
        switch style {
        case .rounded:
            let radius = width / 2
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        case .cross:
            let bar = width * 0.3
            let armY = rect.minY + rect.height * 0.22
            path.addRect(CGRect(x: rect.midX - bar / 2, y: rect.minY, width: bar, height: rect.height))
            path.addRect(CGRect(x: rect.minX, y: armY, width: width, height: bar))
        case .arch:
            path.move(to: CGPoint(x: rect.minX + width * 0.06, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + width * 0.06, y: rect.minY + rect.height * 0.4))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + width * 0.06, y: rect.minY + rect.height * 0.08))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - width * 0.06, y: rect.minY + rect.height * 0.4), control: CGPoint(x: rect.maxX - width * 0.06, y: rect.minY + rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.maxX - width * 0.06, y: rect.maxY))
            path.closeSubpath()
        case .slab:
            let slab = CGRect(x: rect.minX + width * 0.04, y: rect.minY + rect.height * 0.18, width: width * 0.92, height: rect.height * 0.82)
            path.addRoundedRect(in: slab, cornerSize: CGSize(width: width * 0.1, height: width * 0.1))
        }
        return path
    }
}
