import SwiftUI

private enum PlanePalette {
    static let sky = [
        Color(red: 0.36, green: 0.69, blue: 0.97),
        Color(red: 0.62, green: 0.83, blue: 0.99),
        Color(red: 1, green: 0.87, blue: 0.76),
    ]
    static let sun = Color(red: 1, green: 0.95, blue: 0.7)
    static let ocean = [
        Color(red: 0.5, green: 0.88, blue: 0.97),
        Color(red: 0.18, green: 0.6, blue: 0.9),
        Color(red: 0.09, green: 0.34, blue: 0.68),
    ]
    static let rim = Color(red: 0.08, green: 0.27, blue: 0.55)
    static let land = Color(red: 0.56, green: 0.83, blue: 0.42)
    static let landEdge = Color(red: 0.27, green: 0.58, blue: 0.3)
    static let ice = Color(red: 0.96, green: 0.98, blue: 1)
    static let iceEdge = Color(red: 0.7, green: 0.83, blue: 0.93)
    static let atmosphere = Color(red: 0.86, green: 0.96, blue: 1)
    static let capital = Color(red: 0.1, green: 0.24, blue: 0.38)
    static let trail = Color(red: 1, green: 0.4, blue: 0.4)
    static let origin = Color(red: 1, green: 0.76, blue: 0.2)
    static let stop = Color(red: 0.4, green: 0.6, blue: 1)
    static let destination = Color(red: 1, green: 0.33, blue: 0.42)
    static let body = Color.white
    static let bodyShade = Color(red: 0.8, green: 0.86, blue: 0.94)
    static let accent = Color(red: 1, green: 0.38, blue: 0.36)
    static let window = Color(red: 0.15, green: 0.3, blue: 0.52)
    static let ink = Color(red: 0.07, green: 0.16, blue: 0.33)
    static let cloud = Color.white
    static let shadow = Color(red: 0.03, green: 0.12, blue: 0.3)
    static let nightSky = [
        Color(red: 0.02, green: 0.04, blue: 0.14),
        Color(red: 0.07, green: 0.09, blue: 0.27),
        Color(red: 0.24, green: 0.16, blue: 0.36),
    ]
    static let night = Color(red: 0.01, green: 0.03, blue: 0.13)
    static let nightAtmosphere = Color(red: 0.32, green: 0.45, blue: 0.9)
    static let nightCloud = Color(red: 0.42, green: 0.48, blue: 0.62)
    static let cityLight = Color(red: 1, green: 0.84, blue: 0.45)
    static let moon = Color(red: 0.95, green: 0.95, blue: 0.86)
    static let nightInk = Color(red: 0.93, green: 0.95, blue: 1)
    static let navigationRed = Color(red: 1, green: 0.2, blue: 0.25)
    static let navigationGreen = Color(red: 0.25, green: 1, blue: 0.45)
}

struct PlaneTimerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trip: PlaneTrip?
    @State private var dragCamera: PlaneCamera?
    @State private var dragStart: PlaneCamera?
    @State private var releasedAt: Date?

    let snapshot: TimerSnapshot

    var body: some View {
        GeometryReader { safeGeometry in
            GeometryReader { geometry in
                let key = PlaneTrip.Key(seed: snapshot.runID, goalSeconds: snapshot.goalSeconds, cycle: snapshot.cycle)
                let trip = trip(for: key)
                let radius = max(1, min(geometry.size.width * 0.46, geometry.size.height * 0.29))
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.61)

                TimelineView(.animation(
                    minimumInterval: 1.0 / 60,
                    paused: (snapshot.status != .running || scenePhase != .active || reduceMotion) && releasedAt == nil,
                )) { context in
                    let flight = flight(trip: trip, snapshot: snapshot, at: context.date)
                    let camera = camera(trip: trip, snapshot: snapshot, at: context.date)
                    let sun = PlaneDaylight.sun(at: reduceMotion ? snapshot.sampledAt : context.date)
                    let night = PlaneDaylight.night(at: camera.vector, sun: sun)
                    let route = PlaneTrip.route(flight: flight, trip: trip)
                    let caption = PlaneTrip.caption(flight: flight, trip: trip)

                    ZStack(alignment: .top) {
                        PlaneWorld(
                            trip: trip,
                            flight: flight,
                            globe: PlaneGlobe(center: center, radius: radius, camera: camera),
                            sun: sun,
                            time: reduceMotion ? 0 : PlaneTrip.elapsed(snapshot: snapshot, at: context.date),
                            showsLabels: true,
                        )
                        .accessibilityHidden(true)

                        VStack(spacing: 4) {
                            Text(snapshot.clockText)
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))

                            if !route.isEmpty {
                                Text(route)
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                            }

                            if !caption.isEmpty {
                                Text(caption)
                                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                                    .monospacedDigit()
                                    .opacity(0.75)
                            }
                        }
                        .foregroundStyle(PlanePalette.ink.mix(with: PlanePalette.nightInk, by: night))
                        .shadow(color: Color.white.mix(with: PlanePalette.night, by: night).opacity(0.6), radius: 6)
                        .padding(.top, safeGeometry.safeAreaInsets.top + 82)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel([accessibilityStatus, "\(snapshot.clockText) remaining", route, caption, "\(snapshot.goalSeconds / 60) minute focus", "\(snapshot.restSeconds / 60) minute rest"].filter { !$0.isEmpty }.joined(separator: ". ") + ".")
                    }
                    .contentShape(Rectangle())
                    .gesture(spinGesture(trip: trip, radius: radius))
                    .onChange(of: context.date) { _, date in
                        guard let releasedAt, date.timeIntervalSince(releasedAt) >= PlaneCamera.idleDelay + returnDuration else { return }
                        dragCamera = nil
                        self.releasedAt = nil
                    }
                }
                .onChange(of: key, initial: true) { _, key in
                    self.trip = self.trip(for: key)
                }
                .onChange(of: snapshot) { old, new in
                    let wasFlying = PlaneTrip.showsFlight(status: old.status)
                    let isFlying = PlaneTrip.showsFlight(status: new.status)
                    if wasFlying && !isFlying {
                        let oldTrip = self.trip(for: PlaneTrip.Key(seed: old.runID, goalSeconds: old.goalSeconds, cycle: old.cycle))
                        dragCamera = camera(trip: oldTrip, snapshot: old, at: .now)
                        dragStart = nil
                        releasedAt = nil
                    } else if !wasFlying && isFlying {
                        dragCamera = dragCamera ?? PlaneCamera.idle
                        releasedAt = Date.now.addingTimeInterval(-PlaneCamera.idleDelay)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private var returnDuration: TimeInterval {
        reduceMotion ? 0 : PlaneCamera.returnDuration
    }

    private func spinGesture(trip: PlaneTrip, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let start = dragStart ?? camera(trip: trip, snapshot: snapshot, at: .now)
                dragStart = start
                dragCamera = start.dragged(by: gesture.translation, radius: radius)
                releasedAt = nil
            }
            .onEnded { _ in
                dragStart = nil
                releasedAt = PlaneTrip.showsFlight(status: snapshot.status) ? .now : nil
            }
    }

    private func flight(trip: PlaneTrip, snapshot: TimerSnapshot, at date: Date) -> PlaneFlight? {
        guard PlaneTrip.showsFlight(status: snapshot.status) else { return nil }
        return trip.flight(elapsed: PlaneTrip.elapsed(snapshot: snapshot, at: reduceMotion ? snapshot.sampledAt : date))
    }

    private func camera(trip: PlaneTrip, snapshot: TimerSnapshot, at date: Date) -> PlaneCamera {
        guard let follow = flight(trip: trip, snapshot: snapshot, at: date).map({ PlaneCamera($0.position) }) else {
            return dragCamera ?? PlaneCamera.idle
        }
        guard let dragCamera else { return follow }
        guard let releasedAt else { return dragCamera }
        return PlaneCamera.returning(from: dragCamera, to: follow, idle: date.timeIntervalSince(releasedAt), duration: returnDuration) ?? follow
    }

    private func trip(for key: PlaneTrip.Key) -> PlaneTrip {
        if let trip, trip.key == key {
            return trip
        }
        return PlaneTrip(key: key)
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

struct PlaneThemePreview: View {
    var body: some View {
        GeometryReader { geometry in
            let trip = PlaneTrip(key: PlaneTrip.Key(seed: UUID(uuid: (0x42, 0x6F, 0x6E, 0x56, 0x6F, 0x79, 0x61, 0x67, 0x65, 0x21, 0x50, 0x6C, 0x61, 0x6E, 0x65, 0x21)), goalSeconds: 1_500, cycle: 0))
            let flight = trip.flight(elapsed: 600)
            let radius = min(geometry.size.width, geometry.size.height) * 0.4

            ZStack(alignment: .top) {
                PlaneWorld(
                    trip: trip,
                    flight: flight,
                    globe: PlaneGlobe(
                        center: CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.6),
                        radius: radius,
                        camera: flight.map { PlaneCamera($0.position) } ?? PlaneCamera.idle,
                    ),
                    sun: PlaneVector(latitude: 15, longitude: (flight?.position.longitude ?? 0) - 70),
                    time: 0,
                    showsLabels: false,
                )

                Text("15:00")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PlanePalette.ink)
                    .padding(.top, 12)
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}

struct PlaneJet: Shape {
    enum Part: CaseIterable {
        case body
        case wings
        case engines
        case tail
        case cockpit
        case silhouette
    }

    var part: Part = .silhouette

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        func mirrored(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(points.map { point($0.0, $0.1) })
            path.closeSubpath()
            path.addLines(points.map { point(1 - $0.0, $0.1) })
            path.closeSubpath()
            return path
        }

        func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(origin: point(x - width / 2, y - height / 2), size: CGSize(width: rect.width * width, height: rect.height * height))
        }

        switch part {
        case .body:
            var path = Path()
            path.move(to: point(0.5, 0))
            path.addQuadCurve(to: point(0.575, 0.16), control: point(0.575, 0.02))
            path.addLine(to: point(0.565, 0.86))
            path.addQuadCurve(to: point(0.5, 0.99), control: point(0.56, 0.99))
            path.addQuadCurve(to: point(0.435, 0.86), control: point(0.44, 0.99))
            path.addLine(to: point(0.425, 0.16))
            path.addQuadCurve(to: point(0.5, 0), control: point(0.425, 0.02))
            path.closeSubpath()
            return path
        case .wings:
            return mirrored([(0.45, 0.36), (0.03, 0.57), (0.01, 0.62), (0.03, 0.65), (0.45, 0.55)])
        case .engines:
            var path = Path()
            path.addEllipse(in: ellipse(0.27, 0.5, 0.08, 0.15))
            path.addEllipse(in: ellipse(0.73, 0.5, 0.08, 0.15))
            return path
        case .tail:
            return mirrored([(0.47, 0.8), (0.27, 0.92), (0.26, 0.95), (0.28, 0.97), (0.47, 0.93)])
        case .cockpit:
            return Path(ellipseIn: ellipse(0.5, 0.11, 0.1, 0.07))
        case .silhouette:
            var path = Path()
            for part in [Part.wings, .engines, .tail, .body] {
                path.addPath(PlaneJet(part: part).path(in: rect))
            }
            return path
        }
    }
}

private struct PlaneWorld: View {
    let trip: PlaneTrip
    let flight: PlaneFlight?
    let globe: PlaneGlobe
    let sun: PlaneVector
    let time: TimeInterval
    let showsLabels: Bool

    private static let clouds: [(latitude: Double, longitude: Double, size: CGFloat)] = [
        (12, -150, 1), (38, -95, 0.8), (-22, -60, 1.1), (55, -20, 0.9), (5, 15, 0.75),
        (-40, 40, 1), (30, 70, 0.85), (-8, 110, 1.05), (45, 140, 0.9), (-30, 170, 0.8),
        (65, 90, 0.7), (-55, -120, 0.9),
    ]
    private static let skyClouds: [(x: CGFloat, y: CGFloat, size: CGFloat, speed: CGFloat)] = [
        (0.1, 0.06, 0.34, 4), (0.7, 0.14, 0.24, 6), (0.35, 0.33, 0.2, 5), (0.85, 0.4, 0.28, 3.5), (0.15, 0.92, 0.3, 4.5),
    ]

    var body: some View {
        Canvas { context, size in
            drawSky(in: context, size: size)
            drawGlobe(in: context)
            drawRoute(in: context)
            drawClouds(in: context)
            let plane = planePlacement()
            drawStops(in: context, size: size, plane: plane)
            if let plane {
                drawPlane(plane, in: context)
            }
        }
    }

    private func drawSky(in context: GraphicsContext, size: CGSize) {
        let sky = Path(CGRect(origin: .zero, size: size))
        context.fill(sky, with: .linearGradient(
            Gradient(colors: PlanePalette.sky),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height),
        ))
        let night = PlaneDaylight.night(at: globe.camera.vector, sun: sun)
        let glow = CGPoint(x: size.width * 0.84, y: size.height * 0.14)
        context.fill(sky, with: .radialGradient(
            Gradient(colors: [PlanePalette.sun.opacity(0.9), PlanePalette.sun.opacity(0)]),
            center: glow,
            startRadius: 0,
            endRadius: max(1, size.width * 0.55),
        ))
        if night > 0 {
            var dark = context
            dark.opacity = night
            dark.fill(sky, with: .linearGradient(
                Gradient(colors: PlanePalette.nightSky),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height),
            ))
            var stars = Path()
            for index in 0..<70 {
                let twinkle = 0.6 + 0.4 * sin(time * 1.3 + Double(index) * 2.1)
                let radius = (0.5 + 1.1 * CGFloat(Self.noise(index, 3.7))) * CGFloat(twinkle)
                let point = CGPoint(x: CGFloat(Self.noise(index, 12.9898)) * size.width, y: CGFloat(Self.noise(index, 78.233)) * size.height * 0.75)
                stars.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
            dark.fill(stars, with: .color(.white.opacity(0.85)))
            let moon = max(8, min(size.width, size.height) * 0.045)
            dark.fill(
                Path(ellipseIn: CGRect(x: glow.x - moon * 3, y: glow.y - moon * 3, width: moon * 6, height: moon * 6)),
                with: .radialGradient(Gradient(colors: [PlanePalette.moon.opacity(0.25), PlanePalette.moon.opacity(0)]), center: glow, startRadius: moon, endRadius: moon * 3),
            )
            var crescent = dark
            crescent.clip(to: Path(ellipseIn: CGRect(x: glow.x - moon * 0.45, y: glow.y - moon * 1.15, width: moon * 2, height: moon * 2)), options: .inverse)
            crescent.fill(Path(ellipseIn: CGRect(x: glow.x - moon, y: glow.y - moon, width: moon * 2, height: moon * 2)), with: .color(PlanePalette.moon))
        }
        for cloud in Self.skyClouds {
            let width = size.width * cloud.size
            let span = size.width + width * 2
            let travel = (cloud.x * span + CGFloat(time) * cloud.speed).truncatingRemainder(dividingBy: span)
            drawPuff(
                in: context,
                center: CGPoint(x: travel - width, y: size.height * cloud.y),
                width: width,
                opacity: 0.55 * (1 - 0.5 * night),
                color: PlanePalette.cloud.mix(with: PlanePalette.nightCloud, by: night),
            )
        }
    }

    private func drawGlobe(in context: GraphicsContext) {
        let radius = globe.radius
        let center = globe.center
        guard radius > 0 else { return }
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let halo = radius * 1.16
        let night = PlaneDaylight.night(at: globe.camera.vector, sun: sun)
        let atmosphere = PlanePalette.atmosphere.mix(with: PlanePalette.nightAtmosphere, by: night)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: atmosphere.opacity(0.85 - 0.4 * night), location: 0.82),
                    .init(color: atmosphere.opacity(0), location: 1),
                ]),
                center: center,
                startRadius: 0,
                endRadius: halo,
            ),
        )
        context.fill(disc, with: .radialGradient(
            Gradient(colors: PlanePalette.ocean),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
            startRadius: 0,
            endRadius: radius * 1.6,
        ))

        var surface = context
        surface.clip(to: disc)
        var grid = Path()
        for latitude in stride(from: -60.0, through: 60, by: 30) {
            grid.addPath(globe.linePath(PlaneGlobe.parallel(latitude: latitude)))
        }
        for longitude in stride(from: -180.0, to: 180, by: 30) {
            grid.addPath(globe.linePath(PlaneGlobe.meridian(longitude: longitude)))
        }
        surface.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 0.8)

        var land = Path()
        var ice = Path()
        for ring in PlaneAtlas.land {
            if PlaneAtlas.isPolar(ring) {
                ice.addPath(globe.landPath(ring))
            } else {
                land.addPath(globe.landPath(ring))
            }
        }
        let style = StrokeStyle(lineWidth: max(1, radius * 0.014), lineJoin: .round)
        surface.stroke(land, with: .color(PlanePalette.landEdge), style: style)
        surface.stroke(ice, with: .color(PlanePalette.iceEdge), style: style)
        surface.fill(land, with: .color(PlanePalette.land))
        surface.fill(ice, with: .color(PlanePalette.ice))

        var capitals = Path()
        var cities = Path()
        var glows = Array(repeating: Path(), count: 4)
        var lights = Array(repeating: Path(), count: 4)
        let dot = max(0.8, radius * 0.009)
        for city in trip.cities {
            let point = city.point
            let depth = globe.depth(point)
            guard depth > 0 else { continue }
            let center = globe.project(point)
            let scale = CGFloat(min(1, depth * 3))
            let darkness = PlaneDaylight.night(at: point, sun: sun)
            if darkness < 0.5 {
                let size = dot * scale * (city.kind == .capital ? 1.25 : 0.8)
                let marker = CGRect(x: center.x - size, y: center.y - size, width: size * 2, height: size * 2)
                if city.kind == .capital {
                    capitals.addEllipse(in: marker)
                } else {
                    cities.addEllipse(in: marker)
                }
            }
            let level = min(3, Int(darkness * 4))
            guard darkness > 0.1 else { continue }
            let core = dot * scale * (city.hub ? 1.3 : 0.85)
            let halo = core * (city.hub ? 4.5 : 3.2)
            glows[level].addEllipse(in: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2))
            lights[level].addEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
        }
        surface.fill(cities, with: .color(PlanePalette.capital.opacity(0.35)))
        surface.fill(capitals, with: .color(PlanePalette.capital.opacity(0.6)))

        for band in 0..<12 {
            var shade = surface
            shade.opacity = 0.075
            shade.fill(
                globe.nightPath(sun: sun, radius: Double.pi / 2 + (Double(band) - 5.5) * 0.022),
                with: .color(PlanePalette.night),
                style: FillStyle(eoFill: true),
            )
        }
        for level in 0..<4 {
            let strength = Double(level + 1) / 4
            surface.fill(glows[level], with: .color(PlanePalette.cityLight.opacity(0.14 * strength)))
            surface.fill(lights[level], with: .color(PlanePalette.cityLight.opacity(strength)))
        }

        surface.fill(disc, with: .radialGradient(
            Gradient(stops: [
                .init(color: PlanePalette.shadow.opacity(0), location: 0.5),
                .init(color: PlanePalette.shadow.opacity(0.32), location: 1),
            ]),
            center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3),
            startRadius: 0,
            endRadius: radius * 1.3,
        ))
        let shine = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.78, width: radius * 0.7, height: radius * 0.44)
        surface.fill(Path(ellipseIn: shine), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.35 * (1 - 0.7 * night)), .white.opacity(0)]),
            center: CGPoint(x: shine.midX, y: shine.midY),
            startRadius: 0,
            endRadius: radius * 0.36,
        ))
        context.stroke(disc, with: .color(PlanePalette.rim.opacity(0.55)), lineWidth: max(1, radius * 0.012))
    }

    private func drawRoute(in context: GraphicsContext) {
        guard let flight else { return }
        let width = max(1.5, globe.radius * 0.016)
        var remaining = Path()
        var flown = Path()
        for (index, leg) in trip.legs.enumerated() {
            let start = trip.cities[leg.from].point
            let end = trip.cities[leg.to].point
            remaining.addPath(globe.linePath(PlaneGlobe.arc(from: start, to: end)))
            if index < flight.leg || (index == flight.leg && flight.stage == .landed) {
                flown.addPath(globe.linePath(PlaneGlobe.arc(from: start, to: end)))
            } else if index == flight.leg {
                flown.addPath(globe.linePath(PlaneGlobe.arc(from: start, to: end, fraction: flight.legProgress)))
            }
        }
        context.stroke(remaining, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, width * 2.6]))
        context.stroke(flown, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round, lineJoin: .round))
        context.stroke(flown, with: .color(PlanePalette.trail), style: StrokeStyle(lineWidth: width * 1.1, lineCap: .round, lineJoin: .round))
    }

    private func drawClouds(in context: GraphicsContext) {
        for cloud in Self.clouds {
            let point = PlaneVector(latitude: cloud.latitude, longitude: cloud.longitude + time * 0.5)
            let depth = globe.depth(point)
            guard depth > 0.05 else { continue }
            let fade = Self.smoothstep((depth - 0.05) / 0.35)
            let width = globe.radius * 0.26 * cloud.size * CGFloat(0.45 + 0.55 * depth)
            let center = globe.project(point, altitude: 0.04)
            var shadow = context
            shadow.opacity = 0.14 * fade
            drawPuff(in: shadow, center: CGPoint(x: center.x + width * 0.08, y: center.y + width * 0.16), width: width, color: PlanePalette.shadow)
            let darkness = PlaneDaylight.night(at: point, sun: sun)
            drawPuff(in: context, center: center, width: width, opacity: 0.9 * fade * (1 - 0.45 * darkness), color: PlanePalette.cloud.mix(with: PlanePalette.nightCloud, by: darkness))
        }
    }

    private func drawPuff(in context: GraphicsContext, center: CGPoint, width: CGFloat, opacity: Double = 1, color: Color = PlanePalette.cloud) {
        var puff = Path()
        let lobes: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, 0.05, 0.2), (-0.08, -0.08, 0.26), (0.2, -0.02, 0.22), (0.36, 0.08, 0.14)]
        for lobe in lobes {
            let radius = width * lobe.2
            puff.addEllipse(in: CGRect(x: center.x + width * lobe.0 - radius, y: center.y + width * lobe.1 - radius, width: radius * 2, height: radius * 2))
        }
        puff.addRoundedRect(
            in: CGRect(x: center.x - width * 0.45, y: center.y + width * 0.02, width: width * 0.94, height: width * 0.2),
            cornerSize: CGSize(width: width * 0.1, height: width * 0.1),
        )
        var layer = context
        layer.opacity *= opacity
        layer.fill(puff, with: .color(color))
    }

    private func drawStops(in context: GraphicsContext, size canvas: CGSize, plane: PlanePlacement?) {
        guard flight != nil else { return }
        let stops = trip.stops
        for (index, city) in stops.enumerated() {
            let point = city.point
            let depth = globe.depth(point)
            guard depth > 0 else { continue }
            let fade = Self.smoothstep(depth / 0.2)
            let center = globe.project(point)
            let color = index == 0 ? PlanePalette.origin : index == stops.count - 1 ? PlanePalette.destination : PlanePalette.stop
            let size = max(3, globe.radius * 0.035)
            var layer = context
            layer.opacity = fade
            if index == stops.count - 1, flight?.stage == .landed, time > 0 {
                let phase = CGFloat((time / 1.6).truncatingRemainder(dividingBy: 1))
                let ring = size * (1 + 3 * phase)
                layer.stroke(
                    Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                    with: .color(color.opacity(Double(1 - phase))),
                    lineWidth: 2,
                )
            }
            layer.fill(Path(ellipseIn: CGRect(x: center.x - size, y: center.y - size, width: size * 2, height: size * 2)), with: .color(.white))
            let inner = size * 0.62
            layer.fill(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)), with: .color(color))

            guard showsLabels else { continue }
            var lift = size + 14
            if let plane {
                let distance = hypot(plane.center.x - center.x, plane.center.y - center.y) / max(1, plane.size)
                lift += plane.size * 0.55 * CGFloat(Self.smoothstep(1.5 - Double(distance)))
            }
            let label = layer.resolve(Text(city.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(PlanePalette.ink))
            let measured = label.measure(in: CGSize(width: 240, height: 40))
            let pill = CGRect(
                x: min(max(8, center.x - measured.width / 2 - 8), max(8, canvas.width - measured.width - 24)),
                y: center.y - lift - measured.height / 2 - 3,
                width: measured.width + 16,
                height: measured.height + 6,
            )
            var shadow = layer
            shadow.opacity *= 0.18
            shadow.fill(Path(roundedRect: pill.offsetBy(dx: 0, dy: 2), cornerRadius: pill.height / 2), with: .color(PlanePalette.shadow))
            layer.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(.white))
            layer.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    private struct PlanePlacement {
        let center: CGPoint
        let size: CGFloat
        let altitude: Double
        let frame: CGAffineTransform

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * size, y: y * size).applying(frame)
        }
    }

    private func planePlacement() -> PlanePlacement? {
        guard let flight, globe.depth(flight.position) > 0 else { return nil }
        let center = globe.project(flight.position, altitude: 0.03 * flight.altitude)
        let right = globe.screenVector(flight.heading.cross(flight.position))
        let back = globe.screenVector(flight.heading * -1)
        return PlanePlacement(
            center: center,
            size: globe.radius * 0.2 * CGFloat(0.78 + 0.22 * flight.altitude),
            altitude: flight.altitude,
            frame: CGAffineTransform(a: right.dx, b: right.dy, c: back.dx, d: back.dy, tx: center.x, ty: center.y),
        )
    }

    private func drawPlane(_ plane: PlanePlacement, in context: GraphicsContext) {
        let rect = CGRect(x: -plane.size / 2, y: -plane.size / 2, width: plane.size, height: plane.size)

        var shadow = context
        shadow.translateBy(x: plane.size * (0.04 + 0.16 * CGFloat(plane.altitude)), y: plane.size * (0.06 + 0.26 * CGFloat(plane.altitude)))
        shadow.concatenate(plane.frame)
        shadow.scaleBy(x: 0.9, y: 0.9)
        shadow.opacity = 0.16 + 0.1 * (1 - plane.altitude)
        shadow.fill(PlaneJet().path(in: rect), with: .color(PlanePalette.shadow))

        if plane.altitude > 0.2, time > 0 {
            var puffs = Path()
            for engine in [-0.23, 0.23] {
                for index in 0..<7 {
                    let phase = CGFloat((time * 1.4 + Double(index) / 7).truncatingRemainder(dividingBy: 1))
                    let center = plane.point(CGFloat(engine), 0.32 + 1.5 * phase)
                    let radius = plane.size * (0.035 + 0.07 * phase) * CGFloat(plane.altitude) * (1 - phase)
                    puffs.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                }
            }
            var trail = context
            trail.opacity = 0.8 * plane.altitude
            trail.fill(puffs, with: .color(.white))
        }

        var jet = context
        jet.concatenate(plane.frame)
        let outline = StrokeStyle(lineWidth: max(0.8, plane.size * 0.025), lineJoin: .round)
        jet.stroke(PlaneJet().path(in: rect), with: .color(PlanePalette.ink.opacity(0.35)), style: outline)
        jet.fill(PlaneJet(part: .wings).path(in: rect), with: .color(PlanePalette.accent))
        jet.fill(PlaneJet(part: .tail).path(in: rect), with: .color(PlanePalette.accent))
        jet.fill(PlaneJet(part: .engines).path(in: rect), with: .color(PlanePalette.bodyShade))
        jet.fill(PlaneJet(part: .body).path(in: rect), with: .linearGradient(
            Gradient(colors: [PlanePalette.body, PlanePalette.bodyShade]),
            startPoint: CGPoint(x: rect.minX + plane.size * 0.44, y: 0),
            endPoint: CGPoint(x: rect.minX + plane.size * 0.58, y: 0),
        ))
        jet.fill(PlaneJet(part: .cockpit).path(in: rect), with: .color(PlanePalette.window))
        var fin = Path()
        fin.move(to: CGPoint(x: 0, y: rect.minY + plane.size * 0.78))
        fin.addLine(to: CGPoint(x: 0, y: rect.minY + plane.size * 0.96))
        jet.stroke(fin, with: .color(PlanePalette.accent), style: StrokeStyle(lineWidth: max(1, plane.size * 0.05), lineCap: .round))

        let darkness = flight.map { PlaneDaylight.night(at: $0.position, sun: sun) } ?? 0
        let strobe = time > 0 && (time * 1.1).truncatingRemainder(dividingBy: 1) < 0.12
        let beacons: [(CGFloat, CGFloat, Color, Bool)] = [
            (0.03, 0.63, PlanePalette.navigationRed, true),
            (0.97, 0.63, PlanePalette.navigationGreen, true),
            (0.5, 0.99, .white, strobe),
        ]
        for (x, y, color, lit) in beacons where lit {
            let point = CGPoint(x: rect.minX + plane.size * x, y: rect.minY + plane.size * y)
            let core = max(1, plane.size * 0.035)
            let halo = core * (2 + 3 * CGFloat(darkness))
            jet.fill(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)), with: .color(color.opacity(0.2 + 0.35 * darkness)))
            jet.fill(Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)), with: .color(color))
        }
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * (3 - 2 * x)
    }

    private static func noise(_ index: Int, _ salt: Double) -> Double {
        let value = sin(Double(index) * salt) * 43_758.545_3
        return value - value.rounded(.down)
    }
}
