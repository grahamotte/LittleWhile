import SwiftUI

enum PaperCranePalette {
    static let wall = [Color(red: 0.961, green: 0.945, blue: 0.914), Color(red: 0.918, green: 0.894, blue: 0.851)]
    static let fiber = Color(red: 0.55, green: 0.47, blue: 0.38)
    static let ink = Color(red: 0.24, green: 0.21, blue: 0.2)
    static let shadow = Color(red: 0.2, green: 0.13, blue: 0.1)
    static let white = SIMD3<Double>(0.988, 0.976, 0.953)
    static let color = SIMD3<Double>(0.8, 0.255, 0.224)
    static let whiteEdge = Color(red: 0.69, green: 0.64, blue: 0.58)
    static let colorEdge = Color(red: 0.48, green: 0.11, blue: 0.1)

    static func tone(_ face: PaperCraneFace, shade: Double) -> SIMD3<Double> {
        let base = face == .white ? white : color
        let darkened = base * min(1, face == .white ? 1 - (1 - shade) * 0.55 : shade)
        let glow = min(1, max(0, shade - 1) * 1.6)
        return darkened + (SIMD3<Double>(1, 0.985, 0.96) - darkened) * glow * 0.5
    }

    static func paint(_ tone: SIMD3<Double>) -> Color {
        Color(red: min(1, max(0, tone.x)), green: min(1, max(0, tone.y)), blue: min(1, max(0, tone.z)))
    }
}

struct PaperCraneTimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crane: PaperCrane?
    @State private var ledger = PaperCraneLedger()

    let snapshot: TimerSnapshot

    var body: some View {
        GeometryReader { safeGeometry in
            GeometryReader { geometry in
                let key = PaperCrane.Key(size: geometry.size, top: safeGeometry.safeAreaInsets.top + 196, goalSeconds: snapshot.goalSeconds)
                let crane = crane(for: key)

                ZStack(alignment: .top) {
                    PaperCraneBackdrop()
                        .accessibilityHidden(true)

                    TimelineView(.animation(
                        minimumInterval: 1.0 / 60,
                        paused: snapshot.status != .running || scenePhase != .active || reduceMotion,
                    )) { context in
                        let elapsed = PaperCrane.elapsed(snapshot: snapshot, at: context.date)
                        let scene = crane.scene(
                            elapsed: elapsed,
                            restSeconds: snapshot.restSeconds,
                            settled: reduceMotion,
                            looping: snapshot.loops && snapshot.status == .running,
                            arriving: snapshot.loops && snapshot.cycle > 0,
                        )
                        let caption = PaperCrane.caption(
                            folded: scene.folded,
                            finished: scene.finished,
                            started: snapshot.status != .ready,
                        )
                        let cranes = PaperCrane.cranes(
                            elapsed: elapsed,
                            goalSeconds: snapshot.goalSeconds,
                            cycle: snapshot.loops ? snapshot.cycle : 0,
                        )
                        let tally = ledger.count(run: snapshot.runID, cranes: cranes)

                        ZStack(alignment: .top) {
                            PaperCraneTable(scene: scene)
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
                            .foregroundStyle(PaperCranePalette.ink)
                            .padding(.top, safeGeometry.safeAreaInsets.top + 82)
                            .animation(.easeInOut(duration: 0.6), value: caption)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(accessibilityStatus). \(snapshot.clockText) remaining. \(caption). \(snapshot.goalSeconds / 60) minute focus. \(snapshot.restSeconds / 60) minute rest.")

                            HStack(spacing: 7) {
                                PaperCraneGlyph()
                                    .fill(PaperCranePalette.ink)
                                    .frame(width: 36, height: 24)
                                Text(tally, format: .number)
                                    .font(.system(.title3, design: .serif))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            .foregroundStyle(PaperCranePalette.ink)
                            .animation(.spring(duration: 0.5), value: tally)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, safeGeometry.safeAreaInsets.bottom + 22)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(tally) paper cranes")
                        }
                        .onChange(of: "\(snapshot.runID) \(cranes)", initial: true) {
                            ledger.credit(run: snapshot.runID, cranes: cranes)
                        }
                    }
                }
                .onChange(of: key, initial: true) { _, key in
                    self.crane = self.crane(for: key)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func crane(for key: PaperCrane.Key) -> PaperCrane {
        if let crane, crane.key == key {
            return crane
        }
        return PaperCrane(key: key)
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

struct PaperCraneThemePreview: View {
    var body: some View {
        GeometryReader { geometry in
            let crane = PaperCrane(key: PaperCrane.Key(size: geometry.size, top: 34, goalSeconds: 1_500))

            ZStack(alignment: .top) {
                PaperCraneBackdrop()
                PaperCraneTable(scene: crane.scene(elapsed: 1_500, restSeconds: 300, settled: true))

                Text("18:00")
                    .font(.system(size: 17, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(PaperCranePalette.ink)
                    .padding(.top, 12)
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}

struct PaperCraneGlyph: Shape {
    static let outline: [[CGPoint]] = {
        let fold = PaperCrane.folds[PaperCrane.foldCount - 1]
        let facets = fold.end.map { facet in
            var facet = facet
            facet.points = facet.points.map(fold.endCamera.apply)
            return facet
        }
        let points = facets.flatMap(\.points)
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        let side = max(0.000_1, max(maxX - minX, maxY - minY))
        return facets.map { facet in
            let polygon = facet.points.map { CGPoint(x: ($0.x - minX) / side, y: ($0.y - minY) / side) }
            let area = zip(polygon, polygon.dropFirst() + polygon.prefix(1)).reduce(CGFloat(0)) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
            return area >= 0 ? polygon : polygon.reversed()
        }
    }()

    func path(in rect: CGRect) -> Path {
        let points = Self.outline.flatMap { $0 }
        let width = points.map(\.x).max() ?? 1
        let height = points.map(\.y).max() ?? 1
        let scale = min(rect.width / max(0.000_1, width), rect.height / max(0.000_1, height))
        let origin = CGPoint(x: rect.midX - width * scale / 2, y: rect.midY - height * scale / 2)
        var path = Path()
        for polygon in Self.outline {
            path.addLines(polygon.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
            path.closeSubpath()
        }
        return path
    }
}

private enum PaperCraneGrain {
    static let size: CGFloat = 240
    static let light = fibers(salt: 0)
    static let dark = fibers(salt: 1)

    private static func fibers(salt: Int) -> Path {
        var path = Path()
        for index in 0..<110 {
            let seed = index * 2 + salt
            let start = CGPoint(x: CGFloat(noise(seed, 12.9898)) * size, y: CGFloat(noise(seed, 78.233)) * size)
            let angle = noise(seed, 39.425) * 2 * .pi
            let length = CGFloat(3 + noise(seed, 93.989) * 9)
            let end = CGPoint(x: start.x + CGFloat(cos(angle)) * length, y: start.y + CGFloat(sin(angle)) * length)
            let bend = CGFloat(noise(seed, 27.17) - 0.5) * length * 0.8
            path.move(to: start)
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: (start.x + end.x) / 2 - CGFloat(sin(angle)) * bend, y: (start.y + end.y) / 2 + CGFloat(cos(angle)) * bend),
            )
        }
        return path
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index + 1) * salt) * 43_758.5453
        return value - value.rounded(.down)
    }
}

private struct PaperCraneBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .linearGradient(
                Gradient(colors: PaperCranePalette.wall),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height),
            ))

            var fibers = Path()
            let count = Int(size.width * size.height / 900)
            let reach = max(6, min(size.width, size.height) * 0.035)
            for index in 0..<count {
                let start = CGPoint(x: CGFloat(Self.noise(index, 12.9898)) * size.width, y: CGFloat(Self.noise(index, 78.233)) * size.height)
                let angle = Self.noise(index, 39.425) * 2 * .pi
                let length = reach * CGFloat(0.4 + Self.noise(index, 93.989))
                let end = CGPoint(x: start.x + CGFloat(cos(angle)) * length, y: start.y + CGFloat(sin(angle)) * length)
                let bend = CGFloat(Self.noise(index, 27.17) - 0.5) * length * 0.6
                fibers.move(to: start)
                fibers.addQuadCurve(
                    to: end,
                    control: CGPoint(x: (start.x + end.x) / 2 - CGFloat(sin(angle)) * bend, y: (start.y + end.y) / 2 + CGFloat(cos(angle)) * bend),
                )
            }
            context.stroke(fibers, with: .color(PaperCranePalette.fiber.opacity(0.07)), lineWidth: 0.5)

            var specks = Path()
            for index in 0..<(count / 2) {
                let center = CGPoint(x: CGFloat(Self.noise(index, 4.898)) * size.width, y: CGFloat(Self.noise(index, 7.23)) * size.height)
                let radius = 0.3 + CGFloat(Self.noise(index, 1.3)) * 0.5
                specks.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            context.fill(specks, with: .color(PaperCranePalette.fiber.opacity(0.1)))

            let radius = max(size.width, size.height) * 0.75
            context.fill(bounds, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.32), .white.opacity(0), PaperCranePalette.shadow.opacity(0.07)]),
                center: CGPoint(x: size.width * 0.42, y: size.height * 0.4),
                startRadius: 0,
                endRadius: radius,
            ))
        }
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index + 1) * salt) * 43_758.5453
        return value - value.rounded(.down)
    }
}

struct PaperCraneTable: View {
    let scene: PaperCraneScene

    var body: some View {
        Canvas { context, _ in
            var stage = context
            stage.opacity = scene.opacity

            if scene.standing > 0, scene.ground.width > 0 {
                var ground = stage
                ground.opacity = scene.opacity * scene.standing
                ground.fill(
                    Path(ellipseIn: scene.ground),
                    with: .radialGradient(
                        Gradient(colors: [PaperCranePalette.shadow.opacity(0.2), PaperCranePalette.shadow.opacity(0)]),
                        center: CGPoint(x: scene.ground.midX, y: scene.ground.midY),
                        startRadius: 0,
                        endRadius: scene.ground.width / 2,
                    ),
                )
            }

            for polygon in scene.polygons {
                draw(polygon, in: stage)
            }
            drawGrain(in: stage)

            if let hint = scene.hint {
                drawHint(hint, in: stage)
            }
        }
    }

    private func draw(_ polygon: PaperCranePolygon, in context: GraphicsContext) {
        let path = Self.path(polygon.points)
        let contactOpacity = 0.09 * (1 - min(1, scene.standing))
        if !polygon.shadow.isEmpty {
            let height = polygon.lift
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.2 + height * 0.09))
                layer.fill(Self.path(polygon.shadow), with: .color(PaperCranePalette.shadow.opacity(0.2 * Double(max(0.35, 1 - height / 400)))))
            }
        } else if contactOpacity > 0 {
            var contact = context
            contact.translateBy(x: 0.35, y: 0.8)
            contact.fill(path, with: .color(PaperCranePalette.shadow.opacity(contactOpacity)))
        }

        let tone = PaperCranePalette.tone(polygon.face, shade: polygon.shade)
        let bounds = path.boundingRect
        context.fill(path, with: .linearGradient(
            Gradient(colors: [
                PaperCranePalette.paint(tone * 1.025),
                PaperCranePalette.paint(tone * 0.965),
            ]),
            startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY),
        ))

        var seams = Path()
        var creases = Path()
        var edges = Path()
        for index in polygon.points.indices {
            let start = polygon.points[index]
            let end = polygon.points[(index + 1) % polygon.points.count]
            switch polygon.edges[safe: index] ?? .edge {
            case .edge:
                edges.move(to: start)
                edges.addLine(to: end)
            case .crease:
                seams.move(to: start)
                seams.addLine(to: end)
                creases.move(to: start)
                creases.addLine(to: end)
            case .hidden:
                seams.move(to: start)
                seams.addLine(to: end)
            }
        }
        context.stroke(seams, with: .color(PaperCranePalette.paint(tone)), lineWidth: 0.7)
        let edge = polygon.face == .white ? PaperCranePalette.whiteEdge : PaperCranePalette.colorEdge
        context.stroke(creases, with: .color(edge.opacity(0.22)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
        context.stroke(edges, with: .color(edge.opacity(0.55)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round))
    }

    private func drawGrain(in context: GraphicsContext) {
        var sheet = Path()
        for polygon in scene.polygons where polygon.points.count >= 3 {
            let clockwise = zip(polygon.points, polygon.points.dropFirst() + polygon.points.prefix(1))
                .reduce(CGFloat(0)) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y } >= 0
            sheet.addPath(Self.path(clockwise ? polygon.points : polygon.points.reversed()))
        }
        let bounds = sheet.boundingRect
        guard !bounds.isEmpty else { return }
        var grain = context
        grain.clip(to: sheet)
        let tile = PaperCraneGrain.size
        for column in 0...Int(bounds.width / tile) {
            for row in 0...Int(bounds.height / tile) {
                var local = grain
                local.translateBy(x: bounds.minX + CGFloat(column) * tile, y: bounds.minY + CGFloat(row) * tile)
                local.stroke(PaperCraneGrain.light, with: .color(.white.opacity(0.16)), lineWidth: 0.5)
                local.stroke(PaperCraneGrain.dark, with: .color(PaperCranePalette.shadow.opacity(0.07)), lineWidth: 0.5)
            }
        }
    }

    private func drawHint(_ hint: PaperCraneHintMarks, in context: GraphicsContext) {
        var marks = context
        marks.opacity = hint.opacity * 0.7
        let ink = GraphicsContext.Shading.color(PaperCranePalette.ink)
        let dash: [CGFloat] = hint.mountain ? [7, 3, 1.5, 3] : [5, 4]

        for crease in hint.creases where crease.count == 2 {
            var line = Path()
            line.move(to: crease[0])
            line.addLine(to: crease[1])
            marks.stroke(line, with: ink, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: dash))
        }

        for arrow in hint.arrows where arrow.count >= 2 {
            marks.stroke(Self.path(arrow, closed: false), with: ink, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            marks.stroke(Self.arrowhead(at: arrow[arrow.count - 1], from: arrow[arrow.count - 3]), with: ink, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }

        if let point = hint.turnOver {
            var loop = Path()
            loop.move(to: CGPoint(x: point.x - 30, y: point.y - 4))
            loop.addQuadCurve(to: CGPoint(x: point.x, y: point.y + 9), control: CGPoint(x: point.x - 20, y: point.y + 12))
            loop.addArc(center: point, radius: 9, startAngle: .degrees(90), endAngle: .degrees(-270), clockwise: true)
            loop.addQuadCurve(to: CGPoint(x: point.x + 20, y: point.y - 14), control: CGPoint(x: point.x + 18, y: point.y + 8))
            marks.stroke(loop, with: ink, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            marks.stroke(
                Self.arrowhead(at: CGPoint(x: point.x + 20, y: point.y - 14), from: CGPoint(x: point.x + 19.5, y: point.y - 6)),
                with: ink,
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round),
            )
        }
    }

    static func arrowhead(at tip: CGPoint, from tail: CGPoint, size: CGFloat = 6) -> Path {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        var path = Path()
        for spread in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + cos(angle + spread) * size, y: tip.y + sin(angle + spread) * size))
        }
        return path
    }

    private static func path(_ points: [CGPoint], closed: Bool = true) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }
}
