import CoreGraphics
import Foundation
import simd

struct PaperCranePolygon: Equatable {
    let points: [CGPoint]
    let edges: [PaperCraneEdge]
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
    static let resting: [Int] = {
        let fold = folds[folds.count - 1]
        let views = fold.end.map { $0.points.map { view($0, camera: fold.endCamera) } }
        let stacks = fold.end.indices.map { index in
            fold.end[index].layer * 0.001 * fold.endCamera.apply(stack(fold, index, at: 1).rotation.act(SIMD3(0, 0, 1))).z
        }
        return order(views, stacks: stacks, fixed: views.map { _ in false })
    }()
    static let sheet = PaperCraneWorkshop.sheet()
    static let pivot = SIMD3<Double>(0, 0.3, 0)
    static let perspective = 6.0
    static let light = simd_normalize(SIMD3<Double>(-0.45, -0.75, 1))
    static let longestFold: TimeInterval = 2.4
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

    static let minute: TimeInterval = 60
    static let folding = 5.0 / 6
    static let opening = 1.0 / 60

    static func segments(goalSeconds: Int) -> Int {
        goalSeconds <= 0 ? 0 : max(1, goalSeconds / Int(minute))
    }

    static func cranes(elapsed: TimeInterval, goalSeconds: Int, cycle: Int = 0) -> Int {
        let count = segments(goalSeconds: goalSeconds)
        guard count > 0 else { return 0 }
        let goal = TimeInterval(goalSeconds)
        let length = min(minute, goal)
        let focus = min(goal, max(0, elapsed.isFinite ? elapsed : 0))
        let reached = Int(((focus - length * folding) / length).rounded(.down)) + 1
        return max(0, cycle) * count + min(count, max(0, reached))
    }

    var length: TimeInterval {
        min(Self.minute, TimeInterval(max(0, key.goalSeconds)))
    }

    var span: TimeInterval {
        length * Self.folding
    }

    var interval: TimeInterval {
        (span - length * Self.opening) / TimeInterval(Self.foldCount)
    }

    var duration: TimeInterval {
        min(Self.longestFold, interval * 0.72)
    }

    func start(_ index: Int) -> TimeInterval {
        length * Self.opening + interval * TimeInterval(index + 1) - duration
    }

    static func caption(folded: Int, finished: Bool, started: Bool) -> String {
        if finished {
            return "a paper crane"
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
        let count = Self.segments(goalSeconds: key.goalSeconds)
        guard count > 0 else { return hover(time: 0, away: 0, settled: settled) }

        if elapsed >= goal {
            var away = 0.0
            if looping && !settled && rest > 0 {
                away = PaperCraneGeometry.ease((elapsed - (goal + rest - Self.departure)) / Self.departure)
            }
            return hover(time: elapsed - TimeInterval(count - 1) * length - span, away: away, settled: settled)
        }

        let segment = min(count - 1, Int(elapsed / length))
        let within = elapsed - TimeInterval(segment) * length
        if within >= span {
            let flies = !settled && (segment < count - 1 || (looping && rest <= 0))
            let away = flies ? PaperCraneGeometry.ease((within - (length - Self.departure)) / Self.departure) : 0
            return hover(time: within - span, away: away, settled: settled)
        }
        return folding(within, settled: settled, arriving: !settled && (segment > 0 || arriving))
    }

    private func folding(_ elapsed: TimeInterval, settled: Bool, arriving: Bool) -> PaperCraneScene {
        let count = Self.foldCount
        let current = (0..<count).last { start($0) <= elapsed }
        var facets = Self.sheet.map { Posed(facet: $0, points: $0.points, layer: $0.layer, tucked: false, stack: .identity) }
        var camera = PaperCraneCamera.flat
        var fit = fits[0]
        var folded = 0
        if let current {
            let fold = Self.folds[current]
            let progress = settled ? 1 : min(1, (elapsed - start(current)) / max(0.001, duration))
            let eased = PaperCraneGeometry.ease(progress)
            if progress >= 1 {
                facets = fold.end.indices.map { index in
                    let facet = fold.end[index]
                    return Posed(facet: facet, points: facet.points, layer: facet.layer, tucked: false, stack: Self.stack(fold, index, at: 1))
                }
            } else {
                facets = fold.pieces.indices.map { index in
                    let piece = fold.pieces[index]
                    return Posed(
                        facet: piece.facet,
                        points: fold.points(index, at: progress),
                        layer: piece.tucked ? piece.endLayer : fold.layer(index, at: progress),
                        tucked: piece.tucked,
                        stack: Self.stack(fold, index, at: progress),
                    )
                }
            }
            camera = fold.startCamera.mix(fold.endCamera, eased)
            fit = fits[current].mix(fits[current + 1], eased)
            folded = progress >= 1 ? current + 1 : current
        }

        let standing = min(1, abs(camera.pitch) / max(0.001, abs(Self.folds[count - 1].endCamera.pitch)))
        let polygons = render(facets, camera: camera, fit: fit, standing: standing, offset: .zero)
        return PaperCraneScene(
            polygons: polygons,
            hint: hint(elapsed: elapsed, settled: settled),
            folded: folded,
            finished: false,
            standing: standing,
            ground: ground(polygons, standing: standing),
            opacity: arriving ? PaperCraneGeometry.ease(elapsed / Self.arrival) : 1,
        )
    }

    private func hover(time rawTime: TimeInterval, away: Double, settled: Bool) -> PaperCraneScene {
        let fold = Self.folds[Self.foldCount - 1]
        let time = settled ? 0 : max(0, rawTime)
        let lift = CGFloat(sin(time * 1.1)) * 0.022 * CGFloat(min(1, time / 1.5))
        let camera = PaperCraneCamera(yaw: fold.endCamera.yaw + 0.12 * sin(time * 0.37), pitch: fold.endCamera.pitch)
        let facets = fold.end.indices.map { index in
            let facet = fold.end[index]
            return Posed(facet: facet, points: facet.points, layer: facet.layer, tucked: false, stack: Self.stack(fold, index, at: 1))
        }
        let base = fits[fits.count - 1]
        let offset = CGPoint(
            x: CGFloat(away * away) * layout.size.width * 0.45,
            y: (-lift - CGFloat(away * away) * 1.4) * base.scale,
        )
        let polygons = render(facets, camera: camera, fit: base, standing: 1, offset: offset, order: Self.resting)
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
        let stack: PaperCranePose
    }

    private static func stack(_ fold: PaperCraneFold, _ index: Int, at progress: Double) -> PaperCranePose {
        let piece = fold.pieces[index]
        return piece.endLayer == piece.facet.layer ? fold.pose(index, at: progress) : .identity
    }

    private static func view(_ point: SIMD3<Double>, camera: PaperCraneCamera) -> SIMD3<Double> {
        camera.apply(point - pivot) + pivot
    }

    private static func project(_ point: SIMD3<Double>, camera: PaperCraneCamera) -> CGPoint {
        let viewed = view(point, camera: camera)
        let factor = perspective / max(0.5, perspective - viewed.z)
        return CGPoint(x: pivot.x + (viewed.x - pivot.x) * factor, y: pivot.y + (viewed.y - pivot.y) * factor)
    }

    private func render(_ facets: [Posed], camera: PaperCraneCamera, fit: Fit, standing: Double, offset: CGPoint, order fixedOrder: [Int]? = nil) -> [PaperCranePolygon] {
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: fit.center.x + (point.x - fit.origin.x) * fit.scale + offset.x,
                y: fit.center.y + (point.y - fit.origin.y) * fit.scale + offset.y,
            )
        }

        let drop = pow(1 - standing, 4)
        let views = facets.map { $0.points.map { Self.view($0, camera: camera) } }
        let stacks = facets.map { posed -> Double in
            let thickness = camera.apply(posed.stack.rotation.act(SIMD3(0, 0, 1))).z
            return posed.layer * 0.001 * (posed.tucked ? 1 : thickness)
        }
        let order = fixedOrder ?? Self.order(views, stacks: stacks, fixed: facets.map(\.tucked))

        return order.map { facets[$0] }.map { posed in
            let viewed = posed.points.map { Self.view($0, camera: camera) }
            var normal = PaperCraneGeometry.newell(viewed)
            let length = simd_length(normal)
            normal = length > 0.000_001 ? normal / length : SIMD3(0, 0, 1)
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
                edges: posed.facet.edges,
                face: posed.facet.face(of: viewed),
                shade: shade,
                shadow: shadow,
                lift: CGFloat(lift) * fit.scale,
            )
        }
    }

    static func order(_ polygons: [[SIMD3<Double>]], stacks: [Double], fixed: [Bool]) -> [Int] {
        let count = polygons.count
        let planes = polygons.map(plane)
        let flat = polygons.map { $0.map { SIMD2($0.x, $0.y) } }
        let depths = polygons.map { $0.reduce(SIMD3<Double>.zero, +).z / Double(max(1, $0.count)) }
        let keys = depths.indices.map { fixed[$0] ? stacks[$0] : depths[$0] + stacks[$0] }
        let boxes = flat.map { points in
            (points.reduce(SIMD2(Double.infinity, .infinity)) { simd_min($0, $1) }, points.reduce(SIMD2(-Double.infinity, -.infinity)) { simd_max($0, $1) })
        }
        func inside(_ point: SIMD2<Double>, _ polygon: [SIMD2<Double>]) -> Bool {
            PaperCraneGeometry.contains(point, polygon.map { SIMD3($0.x, $0.y, 0) })
        }
        func depth(_ index: Int, at point: SIMD2<Double>) -> Double? {
            let (normal, offset) = planes[index]
            guard abs(normal.z) > 0.05 else { return nil }
            return (offset - normal.x * point.x - normal.y * point.y) / normal.z
        }
        var after = Array(repeating: [Int](), count: count)
        var blockers = Array(repeating: 0, count: count)
        for first in 0..<count {
            for second in (first + 1)..<count {
                let lower = simd_max(boxes[first].0, boxes[second].0)
                let upper = simd_min(boxes[first].1, boxes[second].1)
                guard lower.x < upper.x, lower.y < upper.y else { continue }
                let coplanar = simd_dot(planes[first].0, planes[second].0) > 0.995 && abs(planes[first].1 - planes[second].1) < 0.02
                if coplanar, !fixed[first], !fixed[second], stacks[first] != stacks[second] {
                    let (back, front) = stacks[first] < stacks[second] ? (first, second) : (second, first)
                    after[back].append(front)
                    blockers[front] += 1
                    continue
                }
                if fixed[first] || fixed[second] {
                    let (back, front) = keys[first] < keys[second] ? (first, second) : (second, first)
                    after[back].append(front)
                    blockers[front] += 1
                    continue
                }
                var differences: [Double] = []
                for row in 0..<6 {
                    for column in 0..<6 {
                        let point = lower + (upper - lower) * SIMD2((Double(column) + 0.5) / 6, (Double(row) + 0.5) / 6)
                        guard inside(point, flat[first]), inside(point, flat[second]),
                              let near = depth(first, at: point), let far = depth(second, at: point) else { continue }
                        differences.append(near - far)
                    }
                }
                guard let low = differences.min(), let high = differences.max() else { continue }
                let firstBehind: Bool
                if high < -0.003 {
                    firstBehind = true
                } else if low > 0.003 {
                    firstBehind = false
                } else {
                    continue
                }
                let (back, front) = firstBehind ? (first, second) : (second, first)
                after[back].append(front)
                blockers[front] += 1
            }
        }
        var remaining = Set(0..<count)
        var result: [Int] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { blockers[$0] == 0 }
            let next = ready.isEmpty
                ? remaining.min { (blockers[$0], keys[$0]) < (blockers[$1], keys[$1]) } ?? 0
                : ready.min { keys[$0] < keys[$1] } ?? 0
            remaining.remove(next)
            result.append(next)
            for front in after[next] where remaining.contains(front) {
                blockers[front] -= 1
            }
        }
        return result
    }

    private static func plane(_ points: [SIMD3<Double>]) -> (SIMD3<Double>, Double) {
        let center = points.reduce(SIMD3<Double>.zero, +) / Double(max(1, points.count))
        var normal = PaperCraneGeometry.newell(points)
        let length = simd_length(normal)
        normal = length > 0.000_001 ? normal / length : SIMD3(0, 0, 1)
        if normal.z < 0 || (normal.z == 0 && normal.y < 0) {
            normal = -normal
        }
        return (normal, simd_dot(normal, center))
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
    static let origin = SIMD3<Double>(0, 0, 0)
    static let bottom = SIMD3<Double>(0, 1, 0)
    static let kiteLeft = SIMD3(-k, k, 0)
    static let kiteRight = SIMD3(k, k, 0)
    static let pocket = 0.95
    static let lean = 0.24
    static let drop = Double.pi / 2 + lean - 0.35
    static let hinge = 0.3
    static let neckRise = 72.0
    static let tailRise = 62.0

    static func sheet() -> [PaperCraneFacet] {
        let corners = [SIMD2<Double>(0, -1), SIMD2(1, 0), SIMD2(0, 1), SIMD2(-1, 0)]
        let sheet = PaperCraneFacet(
            group: "sheet",
            paper: corners,
            points: corners.map { SIMD3($0.x, $0.y, 0) },
            layer: 0,
            edges: Array(repeating: .edge, count: 4),
        )
        return styled([sheet], seams: [])
    }

    static func crane() -> [PaperCraneFold] {
        let east = SIMD3<Double>(1, 0, 0)
        let west = SIMD3<Double>(-1, 0, 0)
        let narrow = tan(.pi / 16) * (1 - k)

        var workshop = PaperCraneWorkshop(facets: sheet())

        let top = workshop.component(at: SIMD2(0, -0.5), line: west, east)
        workshop.perform([Motion(facets: top, samples: workshop.fold(top, west, east), layering: .over, crease: (west, east))])

        let half = workshop.component(at: SIMD2(-0.5, 0.25), line: origin, bottom)
        workshop.perform([Motion(facets: half, samples: workshop.fold(half, origin, bottom), layering: .over, crease: (origin, bottom))])

        workshop.squash(at: SIMD2(0.6, 0.2), spine: east)
        workshop.turnOver()
        workshop.squash(at: SIMD2(-0.6, 0.2), spine: west)

        workshop.kites()
        workshop.petal()
        workshop.turnOver()
        workshop.kites()
        workshop.petal()

        workshop.narrow(narrow)
        workshop.turnOver()
        workshop.narrow(narrow)

        for (sign, name) in [(-1.0, "neck"), (1.0, "tail")] {
            let rise = (name == "neck" ? Self.neckRise : Self.tailRise) * .pi / 180
            let height = Self.hinge
            let target = sign < 0 ? .pi + rise : 2 * .pi - rise
            let leg = .pi / 2 - sign * 0.06
            let angle = (target + leg) / 2
            let a = SIMD3(0, height, 0)
            let b = a + SIMD3(cos(angle), sin(angle), 0) * -sign
            workshop.reverse(at: SIMD2(sign * 0.02, 0.85), a, b, side: sign, group: name, opening: Self.pocket)
        }

        let neck = workshop.facets.filter { $0.group == "neck" }
        let tip = neck.flatMap(\.points).min { $0.y < $1.y } ?? origin
        let base = SIMD3(-0.05, Self.hinge + 0.06, 0)
        let along = simd_normalize(tip - base)
        let crossingPoint = tip - along * 0.17
        let headAngle = atan2(along.y, along.x) - 0.8
        let headDirection = SIMD3(cos(headAngle), sin(headAngle), 0)
        let probe = tip - along * 0.05
        workshop.reverse(at: SIMD2(probe.x, probe.y), crossingPoint - headDirection * 0.2, crossingPoint + headDirection * 0.2, side: -1, group: "neck", opening: 0)

        workshop.spread()

        return workshop.folds
    }

    mutating func turnOver() {
        let all = Array(facets.indices)
        let samples = Self.samples { progress in
            PaperCranePose.turn(around: Self.origin, axis: SIMD3(0, 1, 0), angle: .pi * progress)
                .then(PaperCranePose(rotation: PaperCranePose.identity.rotation, translation: SIMD3(0, 0, 0.35 * sin(.pi * progress))))
        }
        perform([Motion(facets: all, samples: samples, layering: .flip, arrow: false)], turnOver: true)
    }

    mutating func squash(at point: SIMD2<Double>, spine: SIMD3<Double>) {
        let hinge = Self.bottom
        let crease = simd_normalize(hinge + spine)
        let flap = cut(component(at: point, line: Self.origin, hinge), Self.origin, crease)
        let layers = flap.map { facets[$0].layer }
        let middle = ((layers.min() ?? 0) + (layers.max() ?? 0)) / 2
        let hingeSide = PaperCraneGeometry.side(hinge * 0.5 + spine * 0.1, Self.origin, crease)
        func group(top: Bool, nearHinge: Bool) -> [Int] {
            flap.filter { index in
                (facets[index].layer > middle) == top
                    && (PaperCraneGeometry.side(facets[index].centroid, Self.origin, crease) * hingeSide > 0) == nearHinge
            }
        }

        let up = SIMD3<Double>(0, 0, 1)
        let lift = PaperCranePose.turn(around: Self.origin, axis: hinge, angle: .pi / 2)
        let raise = simd_dot(lift.rotation.act(spine), up) > 0 ? 1.0 : -1.0
        let split = 0.42
        let c = cos(Double.pi / 4)
        var poses: [[PaperCranePose]] = Array(repeating: [], count: 4)
        for step in 0...Self.sampleCount {
            let u = Double(step) / Double(Self.sampleCount)
            if u < split {
                let pose = PaperCranePose.turn(around: Self.origin, axis: hinge, angle: raise * .pi / 2 * u / split)
                for index in poses.indices {
                    poses[index].append(pose)
                }
                continue
            }
            let gamma = (1 - (u - split) / (1 - split)) * .pi / 2
            let height = c * tan(gamma / 2)
            let reach = max(0, 1 - c * c - height * height).squareRoot()
            let spineNow = hinge * cos(gamma) + up * sin(gamma)
            let topCrease = hinge * c + up * height - spine * reach
            let bottomCrease = hinge * c + up * height + spine * reach
            poses[0].append(.carry((hinge, crease), to: (hinge, topCrease), around: Self.origin))
            poses[1].append(.carry((crease, spine), to: (topCrease, spineNow), around: Self.origin))
            poses[2].append(.carry((spine, crease), to: (spineNow, bottomCrease), around: Self.origin))
            poses[3].append(.carry((crease, hinge), to: (bottomCrease, hinge), around: Self.origin))
        }

        let groups = [group(top: true, nearHinge: true), group(top: true, nearHinge: false), group(top: false, nearHinge: false), group(top: false, nearHinge: true)]
        let layering = settled(Array(zip(groups, poses)))
        perform(zip(groups, poses).enumerated().map { index, entry in
            Motion(
                facets: entry.0,
                samples: entry.1,
                layering: .custom(layering),
                crease: index == 0 ? (Self.origin, crease) : nil,
                arrow: index == 1,
            )
        })
    }

    mutating func kites() {
        for sign in [-1.0, 1.0] {
            let half = facets.indices.filter { facets[$0].centroid.x * sign > 0 && facets[$0].centroid.y > 0 }
            let ceiling = half.map { facets[$0].layer }.max() ?? 0
            regroup("face", half.filter { abs(facets[$0].layer - ceiling) < 0.000_1 })
        }

        var motions: [Motion] = []
        for (corner, point, window) in [(Self.kiteLeft, SIMD2(-0.42, 0.52), 0.0...0.62), (Self.kiteRight, SIMD2(0.42, 0.52), 0.38...1.0)] {
            let flap = component(at: point, line: corner, Self.bottom)
            let layers = flap.map { facets[$0].layer }
            let middle = ((layers.min() ?? 0) + (layers.max() ?? 0)) / 2
            regroup("kiteTop", flap.filter { facets[$0].layer > middle })
            regroup("kiteInner", flap.filter { facets[$0].layer <= middle })
            motions.append(Motion(
                facets: flap,
                samples: fold(flap, corner, Self.bottom),
                window: window,
                layering: .over,
                crease: (corner, Self.bottom),
            ))
        }
        perform(motions)
    }

    mutating func petal() {
        let face = facets.indices.filter { facets[$0].group == "face" }
        cut(face, Self.kiteLeft, Self.kiteRight)
        let center = facets.indices.filter { facets[$0].group == "face" && facets[$0].centroid.y > Self.k }
        let axis = simd_normalize(Self.kiteRight - Self.kiteLeft)
        let split = 0.35
        let probe = PaperCranePose.turn(around: Self.kiteLeft, axis: axis, angle: .pi / 2).apply(Self.bottom).z > 0 ? 1.0 : -1.0

        var motions: [Motion] = []
        var layeringEntries: [([Int], [PaperCranePose])] = []
        var centerPoses: [PaperCranePose] = []
        for step in 0...Self.sampleCount {
            let u = Double(step) / Double(Self.sampleCount)
            let theta = max(0, (u - split) / (1 - split)) * .pi
            centerPoses.append(.turn(around: Self.kiteLeft, axis: axis, angle: probe * theta))
        }
        layeringEntries.append((center, centerPoses))

        for (corner, edge) in [(Self.kiteLeft, SIMD3(-0.5, 0.5, 0)), (Self.kiteRight, SIMD3(0.5, 0.5, 0))] {
            let sideSign: Double = corner.x < 0 ? -1 : 1
            let topFlap = facets.indices.filter { facets[$0].group == "kiteTop" && facets[$0].centroid.x * sideSign > 0 }
            let innerFlap = facets.indices.filter { facets[$0].group == "kiteInner" && facets[$0].centroid.x * sideSign > 0 }
            let unfold = fold(topFlap + innerFlap, corner, Self.bottom)
            let kite = simd_normalize(Self.bottom - corner)
            let book = simd_normalize(edge - corner)
            let opening = acos(simd_dot(kite, book))
            var topPoses: [PaperCranePose] = []
            var innerPoses: [PaperCranePose] = []
            var previous = book
            for step in 0...Self.sampleCount {
                let u = Double(step) / Double(Self.sampleCount)
                if u < split {
                    let pose = unfold[Int((u / split * Double(Self.sampleCount)).rounded())]
                    topPoses.append(pose)
                    innerPoses.append(pose)
                    continue
                }
                let turned = centerPoses[step].rotation.act(kite)
                let fold = PaperCraneGeometry.cone(turned, opening, kite, opening, near: previous + SIMD3(0, 0, 0.25))
                previous = fold
                let settled = unfold[unfold.count - 1]
                topPoses.append(settled.then(.carry((kite, book), to: (turned, fold), around: corner)))
                innerPoses.append(settled.then(.carry((book, kite), to: (fold, kite), around: corner)))
            }
            layeringEntries.append((topFlap, topPoses))
            layeringEntries.append((innerFlap, innerPoses))
        }

        let layering = settled(layeringEntries)
        motions.append(Motion(facets: center, samples: centerPoses, layering: .custom(layering), group: "wing", crease: (Self.kiteLeft, Self.kiteRight)))
        for (index, entry) in layeringEntries.dropFirst().enumerated() {
            motions.append(Motion(
                facets: entry.0,
                samples: entry.1,
                layering: .custom(layering),
                group: index.isMultiple(of: 2) ? "wing" : "inner",
                arrow: false,
            ))
        }
        perform(motions)
        regroup("body", facets.indices.filter { facets[$0].group == "face" })
    }

    mutating func narrow(_ narrow: Double) {
        let left = SIMD3(-narrow, Self.k, 0)
        let right = SIMD3(narrow, Self.k, 0)
        let leftFlap = component(at: SIMD2(-0.12, 0.62), line: Self.bottom, left)
        let rightFlap = component(at: SIMD2(0.12, 0.62), line: Self.bottom, right)
        perform([
            Motion(facets: leftFlap, samples: fold(leftFlap, Self.bottom, left), window: 0...0.6, layering: .over, crease: (Self.bottom, left)),
            Motion(facets: rightFlap, samples: fold(rightFlap, Self.bottom, right), window: 0.4...1, layering: .over, crease: (Self.bottom, right)),
        ])
    }

    mutating func reverse(at point: SIMD2<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>, side: Double, group: String, opening amount: Double) {
        let leg = component(at: point, line: a, b)
        let spine = (Self.origin, Self.bottom)
        let seed = SIMD2(side * 0.08, 0.05)
        let front = Set(component(at: seed, line: spine.0, spine.1))
        let back = Set(component(at: seed, depth: -1, line: spine.0, spine.1))
        let legFront = leg.filter { front.contains($0) }
        let legBack = leg.filter { back.contains($0) }
        let bodyFront = front.subtracting(leg).sorted()
        let bodyBack = back.subtracting(leg).sorted()

        let layers = leg.map { facets[$0].layer }
        let middle = ((layers.min() ?? 0) + (layers.max() ?? 0)) / 2
        let ahead = legFront.sorted { facets[$0].layer > facets[$1].layer }
        let behind = legBack.sorted { facets[$0].layer < facets[$1].layer }
        let frontFloor = ahead.map { facets[$0].layer }.min() ?? middle
        let backCeiling = behind.map { facets[$0].layer }.max() ?? middle
        var tucked: [Int: Double] = [:]
        for (rank, index) in ahead.enumerated() {
            tucked[index] = frontFloor - 0.000_1 * Double(ahead.count - rank)
        }
        for (rank, index) in behind.enumerated() {
            tucked[index] = backCeiling + 0.000_1 * Double(behind.count - rank)
        }

        let up = SIMD3<Double>(0, 1, 0)
        let bodyCenter = center(bodyFront)
        let opening = PaperCranePose.turn(around: Self.origin, axis: up, angle: 0.3).apply(bodyCenter).z > bodyCenter.z ? 1.0 : -1.0
        let hinge = simd_normalize(b - a)
        let legCenter = center(legFront)
        let inward = PaperCranePose.turn(around: a, axis: hinge, angle: 0.3).apply(legCenter).z < legCenter.z ? 1.0 : -1.0
        var poses: [[PaperCranePose]] = Array(repeating: [], count: 4)
        for step in 0...Self.sampleCount {
            let u = Double(step) / Double(Self.sampleCount)
            let spread = amount * sin(.pi * u)
            let openFront = PaperCranePose.turn(around: Self.origin, axis: up, angle: opening * spread)
            let openBack = PaperCranePose.turn(around: Self.origin, axis: up, angle: -opening * spread)
            poses[0].append(openFront)
            poses[1].append(openBack)
            poses[2].append(PaperCranePose.turn(around: a, axis: hinge, angle: inward * .pi * u).then(openFront))
            poses[3].append(PaperCranePose.turn(around: a, axis: hinge, angle: -inward * .pi * u).then(openBack))
        }
        perform([
            Motion(facets: bodyFront, samples: poses[0], arrow: false),
            Motion(facets: bodyBack, samples: poses[1], arrow: false),
            Motion(facets: legFront, samples: poses[2], layering: .custom(tucked), tucked: true, group: group, crease: (a, b)),
            Motion(facets: legBack, samples: poses[3], layering: .custom(tucked), tucked: true, group: group, arrow: false),
        ])
    }

    mutating func spread() {
        let diagonals = [(SIMD2<Double>(0, -1), SIMD2<Double>(0, 1)), (SIMD2<Double>(-1, 0), SIMD2<Double>(1, 0))]
        let mirror = diagonals.max { matches($0) < matches($1) } ?? diagonals[0]
        let axis = mirror.1 - mirror.0
        func paperCenter(_ index: Int) -> SIMD2<Double> {
            facets[index].paper.reduce(SIMD2<Double>.zero, +) / Double(facets[index].paper.count)
        }
        let front = paperCenter(stack(at: SIMD2(0, -0.2)).first ?? 0)
        func side(_ point: SIMD2<Double>) -> Double {
            axis.x * (point.y - mirror.0.y) - axis.y * (point.x - mirror.0.x)
        }
        func onFront(_ index: Int) -> Bool {
            side(paperCenter(index)) * side(front) > 0
        }
        func touches(_ index: Int, _ point: SIMD3<Double>) -> Bool {
            facets[index].points.contains { simd_distance($0, point) < 0.000_01 }
        }
        let tip = SIMD3<Double>(0, 2 * Self.k - 1, 0)
        let corners = [mirror.0, mirror.1]
        let neckCorner = corners.first { corner in
            facets.contains { $0.group == "neck" && $0.paper.contains { simd_distance($0, corner) < 0.000_01 } }
        } ?? mirror.0
        let faces = facets.indices.filter { facets[$0].group == "body" && touches($0, Self.origin) }
        let wings = facets.indices.filter { touches($0, tip) }

        let across = SIMD3<Double>(1, 0, 0)
        let faceFront = faces.filter(onFront)
        let wingFront = wings.filter(onFront)
        let faceCenter = center(faceFront)
        let tilt = PaperCranePose.turn(around: Self.origin, axis: across, angle: 0.2).apply(faceCenter).z > faceCenter.z ? 1.0 : -1.0
        let wingCenter = center(wingFront)
        let lower = PaperCranePose.turn(around: Self.kiteLeft, axis: across, angle: 0.2).apply(wingCenter).z > wingCenter.z ? 1.0 : -1.0
        func face(_ sign: Double) -> (Double) -> PaperCranePose {
            { PaperCranePose.turn(around: Self.origin, axis: across, angle: sign * tilt * Self.lean * $0) }
        }
        func wing(_ sign: Double) -> (Double) -> PaperCranePose {
            { PaperCranePose.turn(around: Self.kiteLeft, axis: across, angle: sign * lower * Self.drop * $0).then(face(sign)($0)) }
        }
        settle(
            drivers: [
                Driver(facets: faceFront, pose: face(1), group: nil),
                Driver(facets: faces.filter { !onFront($0) }, pose: face(-1), group: nil),
                Driver(facets: wingFront, pose: wing(1), group: "w1", crease: (Self.kiteRight, Self.kiteLeft), arrow: true),
                Driver(facets: wings.filter { !onFront($0) }, pose: wing(-1), group: "w2"),
            ],
            mirror: mirror,
            front: front,
            camera: PaperCraneCamera(yaw: 0.95, pitch: -0.42),
            closed: facets.indices.filter { ["neck", "tail"].contains(facets[$0].group) },
            bias: { point in
                let along = simd_dot(point - mirror.0, simd_normalize(axis))
                let offset = point - mirror.0 - simd_normalize(axis) * along
                guard simd_length(offset) < 0.000_01, simd_length(point) > 0.01, simd_length(point) < 0.42 else { return .zero }
                return SIMD3(simd_dot(point, neckCorner) > 0 ? -0.03 : 0.03, 0, 0)
            },
        )
    }

    private func matches(_ line: (SIMD2<Double>, SIMD2<Double>)) -> Int {
        let unit = simd_normalize(line.1 - line.0)
        var count = 0
        for facet in facets {
            for point in facet.paper {
                let offset = point - line.0
                let image = line.0 + unit * (2 * simd_dot(offset, unit)) - offset
                guard let other = facets.first(where: { candidate in
                    candidate.paper.contains { simd_distance($0, image) < 0.000_01 }
                }) else { continue }
                let here = facet.place(point)
                let there = other.place(image)
                if simd_distance(SIMD2(here.x, here.y), SIMD2(there.x, there.y)) < 0.000_1 {
                    count += 1
                }
            }
        }
        return count
    }

    func settled(_ entries: [([Int], [PaperCranePose])]) -> [Int: Double] {
        let moving = Set(entries.flatMap(\.0))
        let ceiling = facets.indices.filter { !moving.contains($0) }.map { facets[$0].layer }.max() ?? 0
        let heights = entries.flatMap { indices, poses -> [(Int, Double)] in
            let probe = poses[Int(Double(poses.count - 1) * 0.97)]
            return indices.map { ($0, probe.apply(facets[$0].centroid + SIMD3(0, 0, facets[$0].layer * 0.001)).z) }
        }
        var layers: [Int: Double] = [:]
        for (rank, entry) in heights.sorted(by: { $0.1 < $1.1 }).enumerated() {
            layers[entry.0] = ceiling + 0.01 * Double(rank + 1)
        }
        return layers
    }
}
