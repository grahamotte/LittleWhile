import SwiftUI

private enum GraveyardPalette {
    static let sky = [
        Color(red: 0.04, green: 0.04, blue: 0.11),
        Color(red: 0.11, green: 0.08, blue: 0.24),
        Color(red: 0.24, green: 0.16, blue: 0.33),
    ]
    static let partySky = [
        Color(red: 0.12, green: 0.03, blue: 0.2),
        Color(red: 0.3, green: 0.08, blue: 0.38),
        Color(red: 0.52, green: 0.2, blue: 0.32),
    ]
    static let hills = Color(red: 0.07, green: 0.06, blue: 0.14)
    static let ground = [Color(red: 0.1, green: 0.11, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.08)]
    static let grass = Color(red: 0.11, green: 0.16, blue: 0.17)
    static let mound = Color(red: 0.07, green: 0.07, blue: 0.1)
    static let moon = Color(red: 0.97, green: 0.94, blue: 0.8)
    static let crater = Color(red: 0.84, green: 0.8, blue: 0.66)
    static let stone = [Color(red: 0.58, green: 0.58, blue: 0.62), Color(red: 0.36, green: 0.36, blue: 0.42)]
    static let stoneEdge = Color(red: 0.18, green: 0.18, blue: 0.24)
    static let ghost = Color(red: 0.94, green: 0.97, blue: 1)
    static let ghostShade = Color(red: 0.74, green: 0.82, blue: 0.92)
    static let ghostGlow = Color(red: 0.6, green: 1, blue: 0.85)
    static let face = Color(red: 0.08, green: 0.07, blue: 0.14)
    static let pumpkin = Color(red: 0.93, green: 0.47, blue: 0.1)
    static let pumpkinEdge = Color(red: 0.6, green: 0.25, blue: 0.05)
    static let candle = Color(red: 1, green: 0.84, blue: 0.3)
    static let ink = Color(red: 0.86, green: 0.92, blue: 0.95)
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
            drawBats(in: context, size: size)
            drawHills(in: context, size: size)
            drawTree(in: context)
            drawGround(in: context, size: size)

            let ghosts = Dictionary(uniqueKeysWithValues: scene.ghosts.map { ($0.grave, $0) })
            for (index, grave) in layout.graves.enumerated() {
                drawGrave(grave, tremble: scene.trembles[index], in: context)
                if let pose = ghosts[index] {
                    drawGhost(pose, grave: grave, in: context)
                }
            }

            drawPumpkins(in: context, size: size)
            drawFog(in: context, size: size)
            if scene.party > 0 {
                drawParty(in: context, size: size, ghosts: scene.ghosts)
            }
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

        var stars = Path()
        for index in 0..<46 {
            let twinkle = 0.5 + 0.5 * sin(time * 1.6 + Double(index) * 2.3)
            let radius = 0.5 + 1.1 * CGFloat(Self.noise(index, 3.1)) * CGFloat(0.5 + 0.5 * twinkle)
            let center = CGPoint(
                x: CGFloat(Self.noise(index, 12.9898)) * size.width,
                y: CGFloat(Self.noise(index, 78.233)) * layout.horizon * 0.9,
            )
            stars.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        context.fill(stars, with: .color(.white.opacity(0.75)))
    }

    private func drawMoon(in context: GraphicsContext) {
        let center = layout.moonCenter
        let radius = layout.moonRadius
        let glow = radius * 3
        let hue = Color(hue: (time * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 1)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [GraveyardPalette.moon.opacity(0.35), GraveyardPalette.moon.opacity(0)]),
                center: center,
                startRadius: radius * 0.8,
                endRadius: glow,
            ),
        )
        if scene.party > 0 {
            var party = context
            party.opacity = scene.party * 0.5
            party.fill(
                Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                with: .radialGradient(Gradient(colors: [hue, hue.opacity(0)]), center: center, startRadius: radius, endRadius: glow),
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [.white, GraveyardPalette.moon]),
                center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.3),
                startRadius: 0,
                endRadius: radius * 1.3,
            ),
        )
        var craters = Path()
        for (dx, dy, size) in [(-0.35, -0.1, 0.22), (0.25, 0.3, 0.16), (0.3, -0.35, 0.12), (-0.1, 0.45, 0.1)] {
            let crater = radius * CGFloat(size)
            craters.addEllipse(in: CGRect(
                x: center.x + radius * CGFloat(dx) - crater,
                y: center.y + radius * CGFloat(dy) - crater,
                width: crater * 2,
                height: crater * 2,
            ))
        }
        context.fill(craters, with: .color(GraveyardPalette.crater.opacity(0.6)))

        for index in 0..<3 {
            let width = radius * CGFloat(2.4 + Double(index) * 0.5)
            let span = layout.size.width + width * 2
            let x = (CGFloat(time * (6 + Double(index) * 3)) + span * CGFloat(Self.noise(index, 7.7))).truncatingRemainder(dividingBy: span) - width
            let y = center.y + radius * CGFloat(Double(index) * 0.7 - 0.5)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: width, height: radius * 0.32)),
                with: .color(GraveyardPalette.hills.opacity(0.55)),
            )
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
        var branches = Path()
        func branch(from start: CGPoint, angle: Double, length: CGFloat, depth: Int) {
            let sway = 0.03 * sin(time * 0.8 + Double(depth))
            let end = CGPoint(x: start.x + CGFloat(cos(angle + sway)) * length, y: start.y + CGFloat(sin(angle + sway)) * length)
            branches.move(to: start)
            branches.addLine(to: end)
            guard depth > 0 else { return }
            branch(from: end, angle: angle - 0.45 - 0.1 * Double(depth % 2), length: length * 0.72, depth: depth - 1)
            branch(from: end, angle: angle + 0.4 + 0.12 * Double(depth % 3), length: length * 0.66, depth: depth - 1)
        }
        let height = layout.size.height * 0.11
        branch(from: base, angle: -.pi / 2 + 0.08, length: height, depth: 5)
        context.stroke(
            branches,
            with: .color(GraveyardPalette.hills),
            style: StrokeStyle(lineWidth: max(1, height * 0.04), lineCap: .round),
        )
        var trunk = Path()
        trunk.move(to: CGPoint(x: base.x - height * 0.07, y: base.y))
        trunk.addLine(to: CGPoint(x: base.x + height * 0.04, y: base.y - height))
        trunk.addLine(to: CGPoint(x: base.x + height * 0.11, y: base.y))
        trunk.closeSubpath()
        context.fill(trunk, with: .color(GraveyardPalette.hills))
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
    }

    private func drawGrave(_ grave: GraveyardGrave, tremble: Double, in context: GraphicsContext) {
        let stone = layout.stoneSize(grave)
        let ground = grave.ground
        let mound = CGRect(x: ground.x - stone.width * 0.62, y: ground.y - stone.width * 0.04, width: stone.width * 1.24, height: stone.width * 0.36)
        context.fill(Path(ellipseIn: mound), with: .color(GraveyardPalette.mound))

        var local = context
        local.translateBy(x: ground.x, y: ground.y)
        local.rotate(by: .radians(grave.tilt + tremble))
        let rect = CGRect(x: -stone.width / 2, y: -stone.height, width: stone.width, height: stone.height)
        let shape = GraveyardTombstone(style: grave.style).path(in: rect)
        local.fill(shape, with: .linearGradient(
            Gradient(colors: GraveyardPalette.stone),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY),
        ))
        local.stroke(shape, with: .color(GraveyardPalette.stoneEdge), lineWidth: max(0.6, stone.width * 0.03))
        if grave.style != .cross {
            local.draw(
                Text("RIP")
                    .font(.system(size: stone.width * 0.22, weight: .bold, design: .serif))
                    .foregroundStyle(GraveyardPalette.stoneEdge.opacity(0.8)),
                at: CGPoint(x: 0, y: -stone.height * 0.55),
            )
        }

        var grass = Path()
        for index in 0..<5 {
            let x = ground.x + stone.width * (CGFloat(index) / 4 - 0.5) * 1.1
            let height = stone.width * (0.12 + 0.1 * CGFloat(Self.noise(index + Int(ground.x), 9.1)))
            grass.move(to: CGPoint(x: x - 1.5, y: ground.y + 2))
            grass.addLine(to: CGPoint(x: x + height * 0.2, y: ground.y - height))
            grass.addLine(to: CGPoint(x: x + 1.5, y: ground.y + 2))
            grass.closeSubpath()
        }
        context.fill(grass, with: .color(GraveyardPalette.grass))
    }

    private func drawGhost(_ pose: GraveyardGhostPose, grave: GraveyardGrave, in context: GraphicsContext) {
        let size = layout.ghostSize(grave)
        let emergence = layout.emergence(grave)
        let bottom = emergence.y + size.height - CGFloat(pose.rise) * size.height * 1.15 + pose.offset.dy
        let center = CGPoint(x: emergence.x + pose.offset.dx, y: bottom - size.height / 2)

        var clipped = context
        clipped.clip(to: Path(CGRect(x: 0, y: 0, width: layout.size.width, height: emergence.y)))
        let glow = size.height * 0.9
        clipped.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [GraveyardPalette.ghostGlow.opacity(0.28 * min(1, pose.rise)), GraveyardPalette.ghostGlow.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: glow,
            ),
        )

        var local = clipped
        local.translateBy(x: center.x, y: center.y)
        local.rotate(by: .radians(pose.tilt))
        local.scaleBy(x: CGFloat(abs(pose.facing) < 0.15 ? 0.15 : pose.facing), y: 1)
        local.opacity = 0.92

        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let armLength = size.width * 0.32
        for side in [-1.0, 1.0] {
            let shoulder = CGPoint(x: rect.midX + CGFloat(side) * size.width * 0.36, y: rect.minY + size.height * 0.48)
            let angle = side > 0 ? 0.9 - pose.arms * 1.9 : .pi - 0.9 + pose.arms * 1.9
            var arm = Path()
            arm.move(to: shoulder)
            arm.addLine(to: CGPoint(x: shoulder.x + CGFloat(cos(angle)) * armLength, y: shoulder.y + CGFloat(sin(angle)) * armLength))
            local.stroke(arm, with: .color(GraveyardPalette.ghost), style: StrokeStyle(lineWidth: size.width * 0.16, lineCap: .round))
        }

        let body = GraveyardGhost(wave: time * 5 + Double(grave.ground.x)).path(in: rect)
        local.fill(body, with: .linearGradient(
            Gradient(colors: [GraveyardPalette.ghost, GraveyardPalette.ghost, GraveyardPalette.ghostShade]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY),
        ))
        if scene.party > 0 {
            var tint = local
            tint.opacity = scene.party * 0.25
            tint.fill(body, with: .color(Color(hue: (time * 0.3 + Double(pose.grave) * 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 1)))
        }

        let eye = size.width * 0.11
        let blink = (time + Double(pose.grave) * 1.3).truncatingRemainder(dividingBy: 4 + Double(pose.grave % 3)) < 0.15 ? 0.15 : 1
        var face = Path()
        for side in [-1.0, 1.0] {
            face.addEllipse(in: CGRect(
                x: rect.midX + CGFloat(side) * size.width * 0.17 - eye / 2,
                y: rect.minY + size.height * 0.3 - eye * 0.7 * CGFloat(blink),
                width: eye,
                height: eye * 1.4 * CGFloat(blink),
            ))
        }
        let mouthTop = rect.minY + size.height * 0.48
        if scene.party > 0.5 {
            face.move(to: CGPoint(x: rect.midX - eye, y: mouthTop))
            face.addQuadCurve(to: CGPoint(x: rect.midX + eye, y: mouthTop), control: CGPoint(x: rect.midX, y: mouthTop + eye * 2.2))
            face.closeSubpath()
        } else {
            let mouth = eye * CGFloat(0.8 + 0.6 * pose.arms)
            face.addEllipse(in: CGRect(x: rect.midX - mouth / 2, y: mouthTop, width: mouth, height: mouth * 1.3))
        }
        local.fill(face, with: .color(GraveyardPalette.face))
    }

    private func drawPumpkins(in context: GraphicsContext, size: CGSize) {
        let radius = layout.stoneWidth * 0.34
        for (x, flickerPhase) in [(0.07, 0.0), (0.5, 2.1), (0.93, 4.3)] {
            let center = CGPoint(x: size.width * CGFloat(x), y: size.height * 0.955)
            let flicker = 0.75 + 0.15 * sin(time * 9 + flickerPhase) + 0.1 * sin(time * 23 + flickerPhase)
            let glow = radius * 2.6
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                with: .radialGradient(
                    Gradient(colors: [GraveyardPalette.candle.opacity(0.3 * flicker), GraveyardPalette.candle.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: glow,
                ),
            )
            var stem = Path()
            stem.addRoundedRect(in: CGRect(x: center.x - radius * 0.1, y: center.y - radius * 1.05, width: radius * 0.2, height: radius * 0.35), cornerSize: CGSize(width: radius * 0.05, height: radius * 0.05))
            context.fill(stem, with: .color(GraveyardPalette.grass))
            for lobe in [-0.45, 0.45, 0] {
                let lobeRect = CGRect(x: center.x + radius * CGFloat(lobe) - radius * 0.65, y: center.y - radius * 0.8, width: radius * 1.3, height: radius * 1.6)
                context.fill(Path(ellipseIn: lobeRect), with: .color(GraveyardPalette.pumpkin))
                context.stroke(Path(ellipseIn: lobeRect), with: .color(GraveyardPalette.pumpkinEdge), lineWidth: max(0.5, radius * 0.05))
            }
            var carving = Path()
            for side in [-1.0, 1.0] {
                let eye = CGPoint(x: center.x + radius * CGFloat(side) * 0.4, y: center.y - radius * 0.2)
                carving.move(to: CGPoint(x: eye.x, y: eye.y - radius * 0.2))
                carving.addLine(to: CGPoint(x: eye.x + radius * 0.18, y: eye.y + radius * 0.1))
                carving.addLine(to: CGPoint(x: eye.x - radius * 0.18, y: eye.y + radius * 0.1))
                carving.closeSubpath()
            }
            carving.move(to: CGPoint(x: center.x - radius * 0.55, y: center.y + radius * 0.2))
            for step in 1...6 {
                let x = center.x - radius * 0.55 + radius * 1.1 * CGFloat(step) / 6
                carving.addLine(to: CGPoint(x: x, y: center.y + radius * (step.isMultiple(of: 2) ? 0.2 : 0.32)))
            }
            carving.addQuadCurve(to: CGPoint(x: center.x - radius * 0.55, y: center.y + radius * 0.2), control: CGPoint(x: center.x, y: center.y + radius * 0.75))
            carving.closeSubpath()
            context.fill(carving, with: .color(GraveyardPalette.candle.opacity(flicker)))
        }
    }

    private func drawFog(in context: GraphicsContext, size: CGSize) {
        for index in 0..<6 {
            let width = size.width * CGFloat(0.6 + 0.4 * Self.noise(index, 5.3))
            let span = size.width + width
            let speed = 5 + 6 * Self.noise(index, 2.7)
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let travel = (CGFloat(time * speed) + span * CGFloat(Self.noise(index, 8.8))).truncatingRemainder(dividingBy: span)
            let x = direction > 0 ? travel - width : size.width - travel
            let y = layout.horizon + (size.height - layout.horizon) * CGFloat(0.1 + 0.15 * Double(index))
            let rect = CGRect(x: x, y: y, width: width, height: size.height * 0.045)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0)]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
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
            let hue = (Double(index) * 0.17 + time * 0.1).truncatingRemainder(dividingBy: 1)
            let color = Color(hue: hue, saturation: 0.8, brightness: 1)
            let radius = max(2, layout.stoneWidth * 0.05)
            if on {
                party.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius * 4, y: point.y - radius * 3, width: radius * 8, height: radius * 8)),
                    with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]), center: CGPoint(x: point.x, y: point.y + radius), startRadius: 0, endRadius: radius * 4),
                )
            }
            party.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y, width: radius * 2, height: radius * 2.6)),
                with: .color(on ? color : color.opacity(0.35)),
            )
        }

        for index in 0..<10 {
            let hue = (Double(index) * 0.1 + time * 0.15).truncatingRemainder(dividingBy: 1)
            let color = Color(hue: hue, saturation: 0.7, brightness: 1)
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
                        .foregroundStyle(Color(hue: (Double(pose.grave) * 0.13 + cycle * 0.2).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 1)),
                    at: point,
                )
            }
        }
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
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - head, y: crown.y))
        path.addArc(center: crown, radius: head, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - hem),
            control1: CGPoint(x: rect.midX + head, y: crown.y + height * 0.3),
            control2: CGPoint(x: rect.maxX - width * 0.02, y: rect.maxY - hem * 2.5),
        )
        let scallops = 4
        for index in 0..<scallops {
            let start = rect.maxX - width * CGFloat(index) / CGFloat(scallops)
            let end = rect.maxX - width * CGFloat(index + 1) / CGFloat(scallops)
            let ripple = CGFloat(sin(wave + Double(index) * 1.6)) * hem * 0.35
            path.addQuadCurve(
                to: CGPoint(x: end, y: rect.maxY - hem),
                control: CGPoint(x: (start + end) / 2, y: rect.maxY + hem - hem * 0.35 + ripple),
            )
        }
        path.addCurve(
            to: CGPoint(x: rect.midX - head, y: crown.y),
            control1: CGPoint(x: rect.minX + width * 0.02, y: rect.maxY - hem * 2.5),
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
