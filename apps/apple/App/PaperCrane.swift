import CoreGraphics
import Foundation
import simd

struct PaperCranePolygon: Equatable {
    let points: [CGPoint]
    let strokes: [Bool]
    let face: PaperCraneFace
    let shade: Double
    let shadow: [CGPoint]
    let lift: CGFloat
}

struct PaperCraneHintMarks: Equatable {
    let creases: [[CGPoint]]
    let arrows: [[CGPoint]]
    let mountain: Bool
    let turnOver: CGPoint?
    let opacity: Double
}

struct PaperCraneScene: Equatable {
    let polygons: [PaperCranePolygon]
    let hint: PaperCraneHintMarks?
    let folded: Int
    let finished: Bool
    let standing: Double
    let ground: CGRect
    let opacity: Double
}

struct PaperCraneLayout: Equatable {
    let size: CGSize
    let frame: CGRect

    init(size: CGSize, top: CGFloat) {
        let width = max(0, size.width.isFinite ? size.width : 0)
        let height = max(0, size.height.isFinite ? size.height : 0)
        self.size = CGSize(width: width, height: height)
        let upper = min(height, max(0, top))
        let lower = height * 0.88
        let side = min(width * 0.8, max(0, lower - upper), 420)
        frame = CGRect(x: (width - side) / 2, y: upper + (max(0, lower - upper) - side) / 2, width: side, height: side)
    }
}

struct PaperCrane {
    struct Key: Equatable {
        let size: CGSize
        let top: CGFloat
        let goalSeconds: Int
    }

    struct Fit: Equatable {
        let center: CGPoint
        let scale: CGFloat
        let origin: CGPoint

        func mix(_ other: Fit, _ progress: Double) -> Fit {
            let t = CGFloat(progress)
            return Fit(
                center: CGPoint(x: center.x + (other.center.x - center.x) * t, y: center.y + (other.center.y - center.y) * t),
                scale: scale + (other.scale - scale) * t,
                origin: CGPoint(x: origin.x + (other.origin.x - origin.x) * t, y: origin.y + (other.origin.y - origin.y) * t),
            )
        }
    }

    static let folds = PaperCraneWorkshop.crane()
    static let sheet = PaperCraneWorkshop.sheet()
    static let pivot = SIMD3<Double>(0, 0.3, 0)
    static let perspective = 6.0
    static let light = simd_normalize(SIMD3<Double>(-0.45, -0.75, 1))
    static let longestFold: TimeInterval = 2.6
    static let departure: TimeInterval = 2.4
    static let arrival: TimeInterval = 0.9

    let key: Key
    let layout: PaperCraneLayout
    let fits: [Fit]

    init(key: Key) {
        self.key = key
        layout = PaperCraneLayout(size: key.size, top: key.top)
        let stages = [(Self.sheet, PaperCraneCamera.flat)] + Self.folds.map { ($0.end, $0.endCamera) }
        let rect = layout.frame
        var fits: [Fit] = []
        for (facets, camera) in stages {
            let points = facets.flatMap { $0.points.map { Self.project($0, camera: camera) } }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            let fitted = min(rect.width / max(0.001, maxX - minX), rect.height / max(0.001, maxY - minY))
            let scale = fits.first.map { min(fitted, $0.scale * 1.3) } ?? fitted
            fits.append(Fit(
                center: CGPoint(x: rect.midX, y: rect.midY),
                scale: scale,
                origin: CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            ))
        }
        self.fits = fits
    }

    static var foldCount: Int {
        folds.count
    }

    var interval: TimeInterval {
        TimeInterval(max(0, key.goalSeconds)) / TimeInterval(Self.foldCount)
    }

    var duration: TimeInterval {
        min(Self.longestFold, interval * 0.6)
    }

    func start(_ index: Int) -> TimeInterval {
        interval * TimeInterval(index + 1) - duration
    }

    func moving(at elapsed: TimeInterval) -> Bool {
        let goal = TimeInterval(max(0, key.goalSeconds))
        guard elapsed < goal - 1, elapsed > Self.arrival + 0.5 else { return true }
        let lead = min(interval * 0.45, 8)
        return (0..<Self.foldCount).contains { elapsed > start($0) - lead - 1.5 && elapsed < start($0) + duration + 1 }
    }

    static func caption(folded: Int, finished: Bool, started: Bool, cranes: Int) -> String {
        if finished {
            return cranes <= 1 ? "one of a thousand" : "\(cranes) of a thousand"
        }
        if !started {
            return "a square of paper"
        }
        return "fold \(min(foldCount, folded + 1)) of \(foldCount)"
    }

    static func elapsed(snapshot: TimerSnapshot, at date: Date) -> TimeInterval {
        let total = TimeInterval(max(0, snapshot.totalSeconds))
        guard snapshot.status != .ready, total > 0 else { return 0 }
        let saved = snapshot.elapsedSeconds.isFinite ? max(0, snapshot.elapsedSeconds) : 0
        let interval = date.timeIntervalSince(snapshot.sampledAt)
        let additional = snapshot.status == .running && interval.isFinite ? max(0, interval) : 0
        let elapsed = saved + additional
        return snapshot.loops && snapshot.status == .running ? elapsed.truncatingRemainder(dividingBy: total) : min(total, elapsed)
    }

    func scene(
        elapsed rawElapsed: TimeInterval,
        restSeconds: Int,
        settled: Bool,
        looping: Bool = false,
        arriving: Bool = false,
    ) -> PaperCraneScene {
        let goal = TimeInterval(max(0, key.goalSeconds))
        let rest = TimeInterval(max(0, restSeconds))
        let elapsed = min(goal + rest, max(0, rawElapsed.isFinite ? rawElapsed : 0))
        let count = Self.foldCount

        if goal <= 0 || elapsed >= goal {
            return finishedScene(restElapsed: elapsed - goal, rest: rest, settled: settled, looping: looping)
        }

        let current = (0..<count).last { start($0) <= elapsed }
        var facets = Self.sheet.map { Posed(facet: $0, points: $0.points, layer: $0.layer, tucked: false, swinging: false) }
        var camera = PaperCraneCamera.flat
        var fit = fits[0]
        var folded = 0
        if let current {
            let fold = Self.folds[current]
            let progress = settled ? 1 : min(1, (elapsed - start(current)) / max(0.001, duration))
            let eased = PaperCraneGeometry.ease(progress)
            facets = fold.pieces.map { piece in
                var swinging = false
                if case .swing = piece.move {
                    swinging = progress < 1
                }
                let facet = progress >= 1 ? piece.end : piece.facet
                return Posed(
                    facet: facet,
                    points: piece.points(at: progress),
                    layer: piece.layer(at: progress),
                    tucked: piece.tucked && progress < 1,
                    swinging: swinging,
                )
            }
            camera = fold.startCamera.mix(fold.endCamera, eased)
            fit = fits[current].mix(fits[current + 1], eased)
            folded = progress >= 1 ? current + 1 : current
        }

        let standing = min(1, abs(camera.pitch) / max(0.001, abs(Self.folds[count - 1].endCamera.pitch)))
        let polygons = render(facets, camera: camera, fit: fit, standing: standing, offset: .zero)
        let opacity = arriving && !settled ? PaperCraneGeometry.ease(elapsed / Self.arrival) : 1
        return PaperCraneScene(
            polygons: polygons,
            hint: hint(elapsed: elapsed, settled: settled),
            folded: folded,
            finished: false,
            standing: standing,
            ground: ground(polygons, standing: standing),
            opacity: opacity,
        )
    }

    private func finishedScene(restElapsed: TimeInterval, rest: TimeInterval, settled: Bool, looping: Bool) -> PaperCraneScene {
        let fold = Self.folds[Self.foldCount - 1]
        let time = settled ? 0 : restElapsed
        let flap = 0.11 * sin(time * 1.7) * min(1, time / 1.5)
        let lift = settled ? 0 : CGFloat(sin(time * 1.1)) * 0.022 * CGFloat(min(1, time / 1.5))
        let camera = PaperCraneCamera(yaw: fold.endCamera.yaw + 0.16 * sin(time * 0.37), pitch: fold.endCamera.pitch)
        let wing = SIMD3<Double>(-1, 0, 0)
        let hinge = SIMD3<Double>(0, PaperCraneWorkshop.k, 0)
        var away = 0.0
        if looping && !settled && rest > 0 {
            away = PaperCraneGeometry.ease((restElapsed - (rest - Self.departure)) / Self.departure)
        }
        let facets = fold.end.map { facet in
            var points = facet.points
            if facet.group == "w1" || facet.group == "w2" {
                let sign: Double = facet.group == "w1" ? 1 : -1
                points = points.map { PaperCraneGeometry.rotate($0, origin: hinge, axis: wing, angle: flap * sign * (1 + away * 3)) }
            }
            return Posed(facet: facet, points: points, layer: facet.layer, tucked: false, swinging: false)
        }
        let base = fits[fits.count - 1]
        let offset = CGPoint(
            x: CGFloat(away * away) * layout.size.width * 0.45,
            y: (-lift - CGFloat(away * away) * 1.4) * base.scale,
        )
        let polygons = render(facets, camera: camera, fit: base, standing: 1, offset: offset)
        return PaperCraneScene(
            polygons: polygons,
            hint: nil,
            folded: Self.foldCount,
            finished: true,
            standing: 1,
            ground: ground(polygons, standing: 1).offsetBy(dx: 0, dy: -offset.y),
            opacity: 1 - away,
        )
    }

    private struct Posed {
        let facet: PaperCraneFacet
        let points: [SIMD3<Double>]
        let layer: Double
        let tucked: Bool
        let swinging: Bool
    }

    private static func view(_ point: SIMD3<Double>, camera: PaperCraneCamera) -> SIMD3<Double> {
        camera.apply(point - pivot) + pivot
    }

    private static func project(_ point: SIMD3<Double>, camera: PaperCraneCamera) -> CGPoint {
        let viewed = view(point, camera: camera)
        let factor = perspective / max(0.5, perspective - viewed.z)
        return CGPoint(x: pivot.x + (viewed.x - pivot.x) * factor, y: pivot.y + (viewed.y - pivot.y) * factor)
    }

    private func render(_ facets: [Posed], camera: PaperCraneCamera, fit: Fit, standing: Double, offset: CGPoint) -> [PaperCranePolygon] {
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: fit.center.x + (point.x - fit.origin.x) * fit.scale + offset.x,
                y: fit.center.y + (point.y - fit.origin.y) * fit.scale + offset.y,
            )
        }

        let drop = pow(1 - standing, 4)
        let sorted = facets.map { posed -> (Posed, Double) in
            let depth = posed.points.map { Self.view($0, camera: camera).z }.reduce(0, +) / Double(max(1, posed.points.count))
            return (posed, posed.tucked ? posed.layer * 0.001 : depth + posed.layer * 0.001)
        }
        .sorted { $0.1 < $1.1 }

        return sorted.map { posed, _ in
            let viewed = posed.points.map { Self.view($0, camera: camera) }
            var normal = PaperCraneGeometry.newell(viewed)
            let length = simd_length(normal)
            normal = length > 0.000_001 ? normal / length : SIMD3(0, 0, 1)
            if posed.swinging {
                normal = SIMD3(0, 0, normal.z >= 0 ? 1 : -1)
            }
            let face = normal.z >= 0 ? posed.facet.front : posed.facet.back
            let facing = normal.z >= 0 ? normal : -normal
            let shade = (0.56 + 0.44 * max(0, simd_dot(facing, Self.light))) / (0.56 + 0.44 * Self.light.z)
            let lift = drop * max(0, viewed.map(\.z).max() ?? 0)
            let shadow = lift > 0.004
                ? viewed.map { point in
                    screen(Self.project(
                        SIMD3(point.x + max(0, point.z) * 0.22, point.y + max(0, point.z) * 0.32, 0),
                        camera: .flat,
                    ))
                }
                : []
            return PaperCranePolygon(
                points: posed.points.map { screen(Self.project($0, camera: camera)) },
                strokes: posed.facet.strokes,
                face: face,
                shade: shade,
                shadow: shadow,
                lift: CGFloat(lift) * fit.scale,
            )
        }
    }

    private func ground(_ polygons: [PaperCranePolygon], standing: Double) -> CGRect {
        let points = polygons.flatMap(\.points)
        guard standing > 0, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let maxY = points.map(\.y).max() else {
            return .zero
        }
        let width = (maxX - minX) * 0.62
        let height = width * 0.16
        return CGRect(x: (minX + maxX) / 2 - width / 2, y: maxY + height * 0.9, width: width, height: height)
    }

    private func hint(elapsed: TimeInterval, settled: Bool) -> PaperCraneHintMarks? {
        let lead = min(interval * 0.45, 8)
        guard let index = (0..<Self.foldCount).first(where: { elapsed < start($0) + duration * 0.4 }) else { return nil }
        let opening = index == 0 ? 0 : start(index) - lead
        guard elapsed >= opening else { return nil }
        let fadeIn = index == 0 ? 1 : PaperCraneGeometry.ease((elapsed - opening) / min(1.2, lead * 0.4))
        let fadeOut = settled ? (elapsed < start(index) ? 1 : 0) : 1 - PaperCraneGeometry.ease((elapsed - start(index)) / (duration * 0.4))
        let opacity = min(fadeIn, fadeOut)
        guard opacity > 0 else { return nil }

        let fold = Self.folds[index]
        let fit = fits[index]
        func screen(_ point: SIMD3<Double>) -> CGPoint {
            let projected = Self.project(point, camera: fold.startCamera)
            return CGPoint(x: fit.center.x + (projected.x - fit.origin.x) * fit.scale, y: fit.center.y + (projected.y - fit.origin.y) * fit.scale)
        }

        let creases = fold.hint.creases.map { $0.map(screen) }
        let arrows = fold.hint.arrows.compactMap { arrow -> [CGPoint]? in
            let from = screen(arrow.from)
            let to = screen(arrow.to)
            let dx = to.x - from.x
            let dy = to.y - from.y
            let distance = hypot(dx, dy)
            guard distance > fit.scale * 0.04 else { return nil }
            let bend = distance * 0.32
            let control = CGPoint(x: (from.x + to.x) / 2 + dy / distance * bend, y: (from.y + to.y) / 2 - dx / distance * bend)
            let trim = 0.12
            return stride(from: trim, through: 1 - trim, by: (1 - 2 * trim) / 24).map { value in
                let t = CGFloat(value)
                let inverse = 1 - t
                return CGPoint(
                    x: inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x,
                    y: inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y,
                )
            }
        }
        var turnOver: CGPoint?
        if fold.hint.turnOver {
            let points = fold.start.flatMap { $0.points.map(screen) }
            let maxX = points.map(\.x).max() ?? fit.center.x
            let maxY = points.map(\.y).max() ?? fit.center.y
            turnOver = CGPoint(x: min(maxX, layout.size.width - 34), y: maxY + 20)
        }
        return PaperCraneHintMarks(creases: creases, arrows: arrows, mountain: fold.hint.mountain, turnOver: turnOver, opacity: opacity)
    }
}

extension PaperCraneWorkshop {
    static let r = 1 / 2.0.squareRoot()
    static let k = 1 - r

    static func sheet() -> [PaperCraneFacet] {
        let northWest = SIMD3(-r, -r, 0)
        let northEast = SIMD3(r, -r, 0)
        let southEast = SIMD3(r, r, 0)
        let southWest = SIMD3(-r, r, 0)
        return [
            facet("a", [northWest, northEast, southEast], strokes: [true, true, false]),
            facet("b", [northWest, southEast, southWest], strokes: [false, true, true]),
        ]
    }

    static func facet(_ group: String, _ points: [SIMD3<Double>], strokes: [Bool]) -> PaperCraneFacet {
        let up = PaperCraneGeometry.newell(points).z >= 0
        return PaperCraneFacet(group: group, points: points, strokes: strokes, layer: 0, front: up ? .white : .color, back: up ? .color : .white)
    }

    static func crane() -> [PaperCraneFold] {
        let origin = SIMD3<Double>(0, 0, 0)
        let northWest = SIMD3(-r, -r, 0)
        let southEast = SIMD3(r, r, 0)
        let southWest = SIMD3(-r, r, 0)
        let left = SIMD3(-0.5, 0.5, 0)
        let right = SIMD3(0.5, 0.5, 0)
        let bottom = SIMD3<Double>(0, 1, 0)
        let kiteLeft = SIMD3(-k, k, 0)
        let kiteRight = SIMD3(k, k, 0)
        let center = SIMD3(0, k, 0)
        let narrow = tan(.pi / 16) * (1 - k)
        let narrowLeft = SIMD3(-narrow, k, 0)
        let narrowRight = SIMD3(narrow, k, 0)

        func group(_ names: String...) -> (PaperCraneFacet) -> Bool {
            { names.contains($0.group) }
        }
        func side(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ reference: SIMD3<Double>) -> (PaperCraneFacet) -> Bool {
            let sign = PaperCraneGeometry.side(reference, a, b)
            return { PaperCraneGeometry.side($0.centroid, a, b) * sign > 0 }
        }

        let squash: (SIMD3<Double>) -> SIMD3<Double> = { point in
            let middle = SIMD3(0, r, 0)
            if point.x <= 0.000_001 {
                return affine(point, from: (origin, southWest, middle), to: (origin, left, bottom))
            }
            return affine(point, from: (origin, middle, southEast), to: (origin, bottom, right))
        }
        let bloom: (SIMD3<Double>, SIMD3<Double>) -> SIMD3<Double> = { start, end in
            let middle = (start + end) / 2
            return SIMD3(middle.x * 0.45, middle.y + 0.04, 0.55 * simd_length(end - start) + 0.3 * abs(start.x))
        }

        var workshop = PaperCraneWorkshop(facets: sheet())

        workshop.perform([Action(select: group("a"), kind: .fold(northWest, southEast, mountain: false, angle: .pi, layering: .top))])

        workshop.cut(origin, southWest) { _ in true }
        workshop.regroup("a1") { $0.group == "a" && side(origin, southWest, northWest)($0) }
        workshop.regroup("b1") { $0.group == "b" && side(origin, southWest, northWest)($0) }
        workshop.regroup("a2", where: group("a"))
        workshop.regroup("b2", where: group("b"))
        workshop.perform([Action(select: group("a1", "b1"), kind: .fold(origin, southWest, mountain: false, angle: .pi, layering: .top))])

        workshop.cut(origin, bottom, crease: true, where: group("a1", "b1"))
        workshop.paint(.color, where: group("a1"))
        workshop.perform([Action(select: group("a1", "b1"), kind: .morph(to: squash, via: bloom))])

        workshop.perform([Action(select: { _ in true }, kind: .turnOver)])

        workshop.cut(origin, bottom, crease: true, where: group("a2", "b2"))
        workshop.paint(.color, where: group("a2"))
        workshop.perform([Action(select: group("a2", "b2"), kind: .morph(to: squash, via: bloom))])

        for (front, kite, wing) in [("b2", "b2k", "w2"), ("b1", "b1k", "w1")] {
            workshop.cut(kiteLeft, bottom, where: group(front))
            workshop.cut(kiteRight, bottom, where: group(front))
            workshop.perform([
                Action(
                    select: { $0.group == front && side(kiteLeft, bottom, left)($0) },
                    kind: .fold(kiteLeft, bottom, mountain: false, angle: .pi, layering: .top),
                    window: 0...0.62,
                    regroup: kite,
                ),
                Action(
                    select: { $0.group == front && side(kiteRight, bottom, right)($0) },
                    kind: .fold(kiteRight, bottom, mountain: false, angle: .pi, layering: .top),
                    window: 0.38...1,
                    regroup: kite,
                ),
            ])

            workshop.cut(kiteLeft, kiteRight, where: group(front))
            workshop.paint(.color, where: group(front))
            var actions = [
                Action(
                    select: { ($0.group == front && $0.centroid.y > k) || $0.group == kite },
                    kind: .fold(kiteLeft, kiteRight, mountain: false, angle: .pi, layering: .top),
                    regroup: wing,
                ),
            ]
            if front == "b1" {
                workshop.cut(kiteLeft, bottom, where: group("a1", "a2"))
                workshop.cut(kiteRight, bottom, where: group("a1", "a2"))
                actions += [
                    Action(
                        select: { ["a1", "a2"].contains($0.group) && side(kiteLeft, bottom, left)($0) },
                        kind: .fold(kiteLeft, bottom, mountain: true, angle: .pi, layering: .bottom),
                        window: 0...0.7,
                        arrow: false,
                    ),
                    Action(
                        select: { ["a1", "a2"].contains($0.group) && side(kiteRight, bottom, right)($0) },
                        kind: .fold(kiteRight, bottom, mountain: true, angle: .pi, layering: .bottom),
                        window: 0.1...0.8,
                        arrow: false,
                    ),
                ]
            }
            workshop.perform(actions)
            workshop.paint(.color, where: group(wing))

            if front == "b2" {
                workshop.perform([Action(select: { _ in true }, kind: .turnOver)])
            }
        }

        workshop.cut(kiteLeft, kiteRight, where: group("a1", "a2"))
        let legs: (PaperCraneFacet) -> Bool = { ["a1", "a2"].contains($0.group) && $0.centroid.y > k }
        workshop.cut(bottom, narrowLeft, where: legs)
        workshop.cut(bottom, narrowRight, where: legs)
        let inner = workshop.facets.filter { $0.group == "a1" }.map(\.layer).max() ?? 0
        let wings = workshop.facets.filter { $0.group == "w1" }.map(\.layer).min() ?? 1
        let tuck = (inner + wings) / 2
        workshop.perform([
            Action(
                select: { $0.group == "a1" && $0.centroid.y > k && side(bottom, narrowLeft, kiteLeft)($0) },
                kind: .fold(bottom, narrowLeft, mountain: false, angle: .pi, layering: .value(tuck)),
                window: 0...0.6,
            ),
            Action(
                select: { $0.group == "a1" && $0.centroid.y > k && side(bottom, narrowRight, kiteRight)($0) },
                kind: .fold(bottom, narrowRight, mountain: false, angle: .pi, layering: .value(tuck)),
                window: 0.4...1,
            ),
            Action(
                select: { $0.group == "a2" && $0.centroid.y > k && side(bottom, narrowLeft, kiteLeft)($0) },
                kind: .fold(bottom, narrowLeft, mountain: true, angle: .pi, layering: .bottom),
                window: 0...0.6,
                arrow: false,
            ),
            Action(
                select: { $0.group == "a2" && $0.centroid.y > k && side(bottom, narrowRight, kiteRight)($0) },
                kind: .fold(bottom, narrowRight, mountain: true, angle: .pi, layering: .bottom),
                window: 0.4...1,
                arrow: false,
            ),
        ])

        for (sign, name) in [(-1.0, "neck"), (1.0, "tail")] {
            let rise = (name == "neck" ? 64.0 : 58.0) * .pi / 180
            let height = name == "neck" ? 0.318 : 0.322
            let target = sign < 0 ? .pi + rise : 2 * .pi - rise
            let leg = .pi / 2 - sign * 0.06
            let angle = (target + leg) / 2
            let a = SIMD3(0, height, 0)
            let b = a + SIMD3(cos(angle), sin(angle), 0) * sign * -1
            let strip: (PaperCraneFacet) -> Bool = { ["a1", "a2"].contains($0.group) && $0.centroid.y > k && $0.centroid.x * sign > 0 }
            workshop.cut(a, b, crease: true, where: strip)
            workshop.perform([
                Action(
                    select: { strip($0) && side(a, b, bottom)($0) },
                    kind: .swing(a, b, pivot: a + (b - a) * 0.05, turn: -sign),
                    regroup: name,
                ),
            ])
        }

        let neck = workshop.facets.filter { $0.group == "neck" }
        let tip = neck.flatMap(\.points).min { $0.y < $1.y } ?? origin
        let base = SIMD3(-0.06, 0.4, 0)
        let along = simd_normalize(tip - base)
        let headLength = 0.17
        let crossing = tip - along * headLength
        let headAngle = atan2(along.y, along.x) - 0.8
        let headA = crossing - SIMD3(cos(headAngle), sin(headAngle), 0) * 0.2
        let headB = crossing + SIMD3(cos(headAngle), sin(headAngle), 0) * 0.2
        let head: (PaperCraneFacet) -> Bool = { $0.group == "neck" }
        workshop.cut(headA, headB, crease: true, where: head)
        workshop.perform([
            Action(
                select: { head($0) && side(headA, headB, tip)($0) },
                kind: .swing(headA, headB, pivot: crossing, turn: -1),
                regroup: "neck",
            ),
        ])

        let spread = 0.44 * .pi
        workshop.perform(
            [
                Action(
                    select: group("w1"),
                    kind: .fold(kiteRight, kiteLeft, mountain: false, angle: spread, layering: .keep),
                ),
                Action(
                    select: group("w2"),
                    kind: .fold(kiteRight, kiteLeft, mountain: true, angle: spread, layering: .keep),
                    arrow: false,
                ),
            ],
            camera: PaperCraneCamera(yaw: 0.5, pitch: -0.36),
        )

        return workshop.folds
    }

    private static func affine(
        _ point: SIMD3<Double>,
        from: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>),
        to: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>),
    ) -> SIMD3<Double> {
        let u = from.1 - from.0
        let v = from.2 - from.0
        let p = point - from.0
        let determinant = u.x * v.y - u.y * v.x
        guard abs(determinant) > 0.000_001 else { return point }
        let s = (p.x * v.y - p.y * v.x) / determinant
        let t = (u.x * p.y - u.y * p.x) / determinant
        return to.0 + (to.1 - to.0) * s + (to.2 - to.0) * t
    }
}
