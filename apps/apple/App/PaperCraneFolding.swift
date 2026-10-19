import CoreGraphics
import Foundation
import simd

enum PaperCraneFace: Equatable {
    case white
    case color
}

enum PaperCraneEdge: Equatable {
    case edge
    case crease
    case hidden
}

struct PaperCranePose: Equatable {
    static let identity = PaperCranePose(rotation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), translation: .zero)

    let vector: SIMD4<Double>
    let translation: SIMD3<Double>

    init(rotation: simd_quatd, translation: SIMD3<Double>) {
        vector = rotation.normalized.vector
        self.translation = translation
    }

    var rotation: simd_quatd {
        simd_quatd(vector: vector)
    }

    static func turn(around origin: SIMD3<Double>, axis: SIMD3<Double>, angle: Double) -> PaperCranePose {
        let rotation = simd_quatd(angle: angle, axis: simd_normalize(axis))
        return PaperCranePose(rotation: rotation, translation: origin - rotation.act(origin))
    }

    static func carry(
        _ from: (SIMD3<Double>, SIMD3<Double>),
        to: (SIMD3<Double>, SIMD3<Double>),
        around origin: SIMD3<Double>,
    ) -> PaperCranePose {
        let rotation = simd_quatd(frame(to.0, to.1)) * simd_quatd(frame(from.0, from.1)).inverse
        return PaperCranePose(rotation: rotation, translation: origin - rotation.act(origin))
    }

    private static func frame(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> simd_double3x3 {
        let x = simd_normalize(a)
        let y = simd_normalize(b - x * simd_dot(x, b))
        return simd_double3x3(columns: (x, y, simd_cross(x, y)))
    }

    func apply(_ point: SIMD3<Double>) -> SIMD3<Double> {
        rotation.act(point) + translation
    }

    func then(_ next: PaperCranePose) -> PaperCranePose {
        PaperCranePose(rotation: next.rotation * rotation, translation: next.rotation.act(translation) + next.translation)
    }

    func mix(_ other: PaperCranePose, _ progress: Double) -> PaperCranePose {
        PaperCranePose(
            rotation: simd_slerp(rotation, other.rotation, progress),
            translation: translation + (other.translation - translation) * progress,
        )
    }
}

struct PaperCraneFacet: Equatable {
    var group: String
    var paper: [SIMD2<Double>]
    var points: [SIMD3<Double>]
    var layer: Double
    var edges: [PaperCraneEdge]

    var centroid: SIMD3<Double> {
        points.reduce(SIMD3<Double>.zero, +) / Double(max(1, points.count))
    }

    var paperSign: Double {
        PaperCraneGeometry.area(paper) >= 0 ? 1 : -1
    }

    var visibleFace: PaperCraneFace {
        face(of: points)
    }

    func face(of points: [SIMD3<Double>]) -> PaperCraneFace {
        PaperCraneGeometry.newell(points).z * paperSign >= 0 ? .white : .color
    }

    func moved(by pose: PaperCranePose) -> PaperCraneFacet {
        var facet = self
        facet.points = points.map(pose.apply)
        return facet
    }

    func place(_ paperPoint: SIMD2<Double>) -> SIMD3<Double> {
        let origin = paper[0]
        for index in 1..<max(1, paper.count - 1) {
            let u = paper[index] - origin
            for other in (index + 1)..<paper.count {
                let v = paper[other] - origin
                let determinant = u.x * v.y - u.y * v.x
                guard abs(determinant) > 0.000_000_1 else { continue }
                let offset = paperPoint - origin
                let s = (offset.x * v.y - offset.y * v.x) / determinant
                let t = (u.x * offset.y - u.y * offset.x) / determinant
                return points[0] + (points[index] - points[0]) * s + (points[other] - points[0]) * t
            }
        }
        return points.first ?? .zero
    }
}

struct PaperCraneCamera: Equatable {
    static let flat = PaperCraneCamera(yaw: 0, pitch: 0)

    let yaw: Double
    let pitch: Double

    func apply(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let yawed = SIMD3(
            point.x * cos(yaw) + point.z * sin(yaw),
            point.y,
            -point.x * sin(yaw) + point.z * cos(yaw),
        )
        return SIMD3(
            yawed.x,
            yawed.y * cos(pitch) - yawed.z * sin(pitch),
            yawed.y * sin(pitch) + yawed.z * cos(pitch),
        )
    }

    func mix(_ other: PaperCraneCamera, _ progress: Double) -> PaperCraneCamera {
        PaperCraneCamera(yaw: yaw + (other.yaw - yaw) * progress, pitch: pitch + (other.pitch - pitch) * progress)
    }
}

struct PaperCranePiece: Equatable {
    let facet: PaperCraneFacet
    let body: Int?
    let window: ClosedRange<Double>
    let endLayer: Double
    let tucked: Bool
    var track: [[SIMD3<Double>]] = []

    func local(_ progress: Double) -> Double {
        let span = max(0.0001, window.upperBound - window.lowerBound)
        return PaperCraneGeometry.ease((progress - window.lowerBound) / span)
    }
}

struct PaperCraneHint: Equatable {
    struct Arrow: Equatable {
        let from: SIMD3<Double>
        let to: SIMD3<Double>
    }

    let creases: [[SIMD3<Double>]]
    let arrows: [Arrow]
    let mountain: Bool
    let turnOver: Bool
}

struct PaperCraneSeam: Equatable {
    let start: SIMD2<Double>
    let end: SIMD2<Double>
}

struct PaperCraneFold: Equatable {
    let pieces: [PaperCranePiece]
    let bodies: [[PaperCranePose]]
    let end: [PaperCraneFacet]
    let startCamera: PaperCraneCamera
    let endCamera: PaperCraneCamera
    let hint: PaperCraneHint
    let seams: [PaperCraneSeam]

    var start: [PaperCraneFacet] {
        pieces.map(\.facet)
    }

    func pose(_ index: Int, at progress: Double) -> PaperCranePose {
        let piece = pieces[index]
        guard let body = piece.body, let samples = bodies[safe: body], !samples.isEmpty else { return .identity }
        let position = piece.local(progress) * Double(samples.count - 1)
        let lower = min(samples.count - 1, max(0, Int(position.rounded(.down))))
        let upper = min(samples.count - 1, lower + 1)
        return samples[lower].mix(samples[upper], position - Double(lower))
    }

    func points(_ index: Int, at progress: Double) -> [SIMD3<Double>] {
        let piece = pieces[index]
        guard piece.track.count > 1 else {
            let pose = pose(index, at: progress)
            return piece.facet.points.map(pose.apply)
        }
        let position = piece.local(progress) * Double(piece.track.count - 1)
        let lower = min(piece.track.count - 1, max(0, Int(position.rounded(.down))))
        let upper = min(piece.track.count - 1, lower + 1)
        let mix = position - Double(lower)
        return zip(piece.track[lower], piece.track[upper]).map { $0 + ($1 - $0) * mix }
    }

    func layer(_ index: Int, at progress: Double) -> Double {
        let piece = pieces[index]
        return piece.facet.layer + (piece.endLayer - piece.facet.layer) * piece.local(progress)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum PaperCraneGeometry {
    static let epsilon = 0.000_001

    static func newell(_ points: [SIMD3<Double>]) -> SIMD3<Double> {
        var normal = SIMD3<Double>.zero
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }
        return normal
    }

    static func area(_ points: [SIMD3<Double>]) -> Double {
        simd_length(newell(points)) / 2
    }

    static func area(_ points: [SIMD2<Double>]) -> Double {
        var total = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            total += current.x * next.y - next.x * current.y
        }
        return total / 2
    }

    static func side(_ point: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let direction = SIMD2(b.x - a.x, b.y - a.y)
        let length = max(epsilon, simd_length(direction))
        return (direction.x * (point.y - a.y) - direction.y * (point.x - a.x)) / length
    }

    static func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    static func contains(_ point: SIMD2<Double>, _ polygon: [SIMD3<Double>]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }

    static func cone(
        _ a: SIMD3<Double>,
        _ alpha: Double,
        _ b: SIMD3<Double>,
        _ beta: Double,
        near: SIMD3<Double>,
    ) -> SIMD3<Double> {
        let cosine = simd_dot(a, b)
        let normal = simd_cross(a, b)
        let length = simd_length(normal)
        guard length > 0.000_01 else { return simd_normalize(near) }
        let first = (cos(alpha) - cosine * cos(beta)) / (1 - cosine * cosine)
        let second = (cos(beta) - cosine * cos(alpha)) / (1 - cosine * cosine)
        let base = a * first + b * second
        let rest = max(0, 1 - simd_length_squared(base))
        let lift = normal / length * rest.squareRoot()
        let up = simd_normalize(base + lift)
        let down = simd_normalize(base - lift)
        return simd_dot(up, near) >= simd_dot(down, near) ? up : down
    }

    static func split(
        _ facet: PaperCraneFacet,
        _ a: SIMD3<Double>,
        _ b: SIMD3<Double>,
    ) -> (parts: [PaperCraneFacet], cut: (SIMD2<Double>, SIMD2<Double>)?) {
        let distances = facet.points.map { side($0, a, b) }
        guard distances.contains(where: { $0 > epsilon }), distances.contains(where: { $0 < -epsilon }) else {
            return ([facet], nil)
        }
        var cut: [SIMD2<Double>] = []
        let parts = [1.0, -1.0].compactMap { sign -> PaperCraneFacet? in
            var points: [SIMD3<Double>] = []
            var paper: [SIMD2<Double>] = []
            let count = facet.points.count
            for index in 0..<count {
                let next = (index + 1) % count
                let current = distances[index] * sign
                let following = distances[next] * sign
                if current >= -epsilon {
                    points.append(facet.points[index])
                    paper.append(facet.paper[index])
                    if sign > 0 && abs(current) <= epsilon {
                        cut.append(facet.paper[index])
                    }
                }
                if (current > epsilon && following < -epsilon) || (current < -epsilon && following > epsilon) {
                    let ratio = current / (current - following)
                    points.append(facet.points[index] + (facet.points[next] - facet.points[index]) * ratio)
                    let crossing = facet.paper[index] + (facet.paper[next] - facet.paper[index]) * ratio
                    paper.append(crossing)
                    if sign > 0 {
                        cut.append(crossing)
                    }
                }
            }
            guard points.count >= 3, area(points) > epsilon else { return nil }
            var piece = facet
            piece.points = points
            piece.paper = paper
            piece.edges = Array(repeating: .edge, count: points.count)
            return piece
        }
        let segment = cut.count >= 2 ? (cut[0], cut[cut.count - 1]) : nil
        return (parts, segment)
    }

    static func overlaps(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: SIMD2<Double>, _ s: SIMD2<Double>) -> Bool {
        let direction = q - p
        let length = simd_length(direction)
        guard length > epsilon else { return false }
        let unit = direction / length
        let crossR = unit.x * (r.y - p.y) - unit.y * (r.x - p.x)
        let crossS = unit.x * (s.y - p.y) - unit.y * (s.x - p.x)
        guard abs(crossR) < 0.000_01, abs(crossS) < 0.000_01 else { return false }
        let start = simd_dot(r - p, unit)
        let end = simd_dot(s - p, unit)
        return min(length, max(start, end)) - max(0, min(start, end)) > 0.000_01
    }
}

struct PaperCraneWorkshop {
    enum Layering {
        case keep
        case over
        case under
        case settle
        case flip
        case custom([Int: Double])
    }

    struct Motion {
        var facets: [Int]
        var samples: [PaperCranePose]
        var window: ClosedRange<Double> = 0...1
        var layering = Layering.keep
        var tucked = false
        var group: String?
        var crease: (SIMD3<Double>, SIMD3<Double>)?
        var arrow = true
        var track: [[SIMD3<Double>]] = []
    }

    static let sampleCount = 60

    private(set) var facets: [PaperCraneFacet]
    private(set) var seams: [(SIMD2<Double>, SIMD2<Double>)] = []
    private(set) var folds: [PaperCraneFold] = []
    private var camera = PaperCraneCamera.flat

    init(facets: [PaperCraneFacet]) {
        self.facets = facets
    }

    func stack(at point: SIMD2<Double>) -> [Int] {
        facets.indices
            .filter { PaperCraneGeometry.contains(point, facets[$0].points) }
            .sorted { facets[$0].layer > facets[$1].layer }
    }

    mutating func regroup(_ group: String, _ indices: [Int]) {
        for index in indices {
            facets[index].group = group
        }
    }

    @discardableResult
    mutating func cut(_ indices: [Int], _ a: SIMD3<Double>, _ b: SIMD3<Double>, seam: Bool = false) -> [Int] {
        var result: [Int] = []
        for index in indices {
            let (parts, segment) = PaperCraneGeometry.split(facets[index], a, b)
            facets[index] = parts[0]
            result.append(index)
            for part in parts.dropFirst() {
                facets.append(part)
                result.append(facets.count - 1)
            }
            if seam, parts.count > 1, let segment {
                seams.append(segment)
            }
        }
        return result
    }

    mutating func component(
        at point: SIMD2<Double>,
        depth: Int = 0,
        line a: SIMD3<Double>,
        _ b: SIMD3<Double>,
        barriers: [(SIMD3<Double>, SIMD3<Double>)] = [],
    ) -> [Int] {
        let stack = stack(at: point)
        guard let seed = stack[safe: depth < 0 ? stack.count + depth : depth] else { return [] }
        let sign: Double = PaperCraneGeometry.side(SIMD3(point.x, point.y, 0), a, b) >= 0 ? 1 : -1
        var members = Set<Int>()
        var queue = [seed]
        while let index = queue.popLast() {
            guard !members.contains(index) else { continue }
            let (parts, _) = PaperCraneGeometry.split(facets[index], a, b)
            if parts.count == 2 {
                let keep = PaperCraneGeometry.side(parts[0].centroid, a, b) * sign > 0 ? 0 : 1
                facets[index] = parts[keep]
                facets.append(parts[1 - keep])
            }
            members.insert(index)
            for other in facets.indices where !members.contains(other) && other != index {
                let link = link(index, other, fold: (a, b), barriers: barriers)
                if link.joined {
                    queue.append(other)
                } else {
                    seams += link.held
                }
            }
        }
        return members.sorted()
    }

    private func link(
        _ index: Int,
        _ other: Int,
        fold: (SIMD3<Double>, SIMD3<Double>),
        barriers: [(SIMD3<Double>, SIMD3<Double>)],
    ) -> (joined: Bool, held: [(SIMD2<Double>, SIMD2<Double>)]) {
        let facet = facets[index]
        let neighbor = facets[other]
        guard Self.near(facet.paper, neighbor.paper) else { return (false, []) }
        func lies(_ start: SIMD3<Double>, _ end: SIMD3<Double>, on line: (SIMD3<Double>, SIMD3<Double>)) -> Bool {
            abs(PaperCraneGeometry.side(start, line.0, line.1)) < 0.000_01
                && abs(PaperCraneGeometry.side(end, line.0, line.1)) < 0.000_01
                && abs(start.z) < 0.000_01 && abs(end.z) < 0.000_01
        }
        var held: [(SIMD2<Double>, SIMD2<Double>)] = []
        for edge in facet.paper.indices {
            let next = (edge + 1) % facet.paper.count
            let touches = neighbor.paper.indices.contains { corner in
                PaperCraneGeometry.overlaps(facet.paper[edge], facet.paper[next], neighbor.paper[corner], neighbor.paper[(corner + 1) % neighbor.paper.count])
            }
            guard touches, !lies(facet.points[edge], facet.points[next], on: fold) else { continue }
            if barriers.contains(where: { lies(facet.points[edge], facet.points[next], on: $0) }) {
                held.append((facet.paper[edge], facet.paper[next]))
            } else {
                return (true, [])
            }
        }
        return (false, held)
    }

    static func near(_ a: [SIMD2<Double>], _ b: [SIMD2<Double>]) -> Bool {
        let tolerance = 0.000_1
        let aMin = a.reduce(SIMD2(Double.infinity, .infinity)) { simd_min($0, $1) }
        let aMax = a.reduce(SIMD2(-Double.infinity, -.infinity)) { simd_max($0, $1) }
        let bMin = b.reduce(SIMD2(Double.infinity, .infinity)) { simd_min($0, $1) }
        let bMax = b.reduce(SIMD2(-Double.infinity, -.infinity)) { simd_max($0, $1) }
        return aMin.x <= bMax.x + tolerance && bMin.x <= aMax.x + tolerance && aMin.y <= bMax.y + tolerance && bMin.y <= aMax.y + tolerance
    }

    func center(_ indices: [Int], pose: PaperCranePose = .identity) -> SIMD3<Double> {
        var total = SIMD3<Double>.zero
        var weight = 0.0
        for index in indices {
            let facet = facets[index]
            let area = PaperCraneGeometry.area(facet.points)
            total += pose.apply(facet.centroid) * area
            weight += area
        }
        return weight > 0 ? total / weight : .zero
    }

    func fold(
        _ indices: [Int],
        _ a: SIMD3<Double>,
        _ b: SIMD3<Double>,
        mountain: Bool = false,
        angle: Double = .pi,
    ) -> [PaperCranePose] {
        let axis = simd_normalize(b - a)
        let middle = center(indices)
        let probe = PaperCranePose.turn(around: a, axis: axis, angle: .pi / 2).apply(middle)
        let rising = probe.z > middle.z
        let turn = angle * (rising == mountain ? -1 : 1)
        return Self.samples { PaperCranePose.turn(around: a, axis: axis, angle: turn * $0) }
    }

    static func samples(_ pose: (Double) -> PaperCranePose) -> [PaperCranePose] {
        (0...sampleCount).map { pose(Double($0) / Double(sampleCount)) }
    }

    mutating func perform(_ motions: [Motion], camera next: PaperCraneCamera? = nil, turnOver: Bool = false) {
        var layers = facets.map(\.layer)
        var groups = facets.map(\.group)
        var bodies: [[PaperCranePose]] = []
        var owners: [Int: (body: Int, window: ClosedRange<Double>, tucked: Bool)] = [:]
        var tracks: [Int: [[SIMD3<Double>]]] = [:]
        var creases: [[SIMD3<Double>]] = []
        var arrows: [PaperCraneHint.Arrow] = []
        var mountain = false

        for motion in motions where !motion.facets.isEmpty {
            let body = bodies.count
            bodies.append(motion.samples)
            let moving = Set(motion.facets)
            for index in motion.facets {
                owners[index] = (body, motion.window, motion.tucked)
                if !motion.track.isEmpty {
                    tracks[index] = motion.track
                }
                if let group = motion.group {
                    groups[index] = group
                }
            }
            let still = facets.indices.filter { !moving.contains($0) }.map { layers[$0] }
            let ceiling = still.max() ?? 0
            let floor = still.min() ?? 0
            let descending = motion.facets.sorted { layers[$0] > layers[$1] }
            switch motion.layering {
            case .keep:
                break
            case .over:
                for (rank, index) in descending.enumerated() {
                    layers[index] = ceiling + 0.01 * Double(rank + 1)
                }
            case .under:
                for (rank, index) in descending.enumerated() {
                    layers[index] = floor - 0.01 * Double(descending.count - rank)
                }
            case .settle:
                let probe = motion.samples[Int(Double(motion.samples.count - 1) * 0.97)]
                let heights = motion.facets.map { index in
                    (index, probe.apply(facets[index].centroid + SIMD3(0, 0, layers[index] * 0.001)).z)
                }
                for (rank, entry) in heights.sorted(by: { $0.1 < $1.1 }).enumerated() {
                    layers[entry.0] = ceiling + 0.01 * Double(rank + 1)
                }
            case .flip:
                for index in motion.facets {
                    layers[index] = -layers[index]
                }
            case let .custom(values):
                for index in motion.facets {
                    layers[index] = values[index] ?? layers[index]
                }
            }
            if let (a, b) = motion.crease {
                creases.append(crease(a, b, along: motion.facets))
                let middle = center(motion.facets)
                mountain = mountain || motion.samples[motion.samples.count / 2].apply(middle).z < middle.z
            }
            if motion.arrow, let last = motion.samples.last {
                arrows.append(PaperCraneHint.Arrow(from: center(motion.facets), to: center(motion.facets, pose: last)))
            }
        }

        let start = Self.styled(facets, seams: seams)
        let pieces = start.indices.map { index in
            PaperCranePiece(
                facet: start[index],
                body: owners[index]?.body,
                window: owners[index]?.window ?? 0...1,
                endLayer: layers[index],
                tucked: owners[index]?.tucked ?? false,
                track: tracks[index] ?? [],
            )
        }
        let moved = pieces.indices.map { index -> PaperCraneFacet in
            var facet = pieces[index].facet
            if let last = pieces[index].track.last {
                facet.points = last
            } else if let body = pieces[index].body, let last = bodies[body].last {
                facet = facet.moved(by: last)
            }
            facet.layer = layers[index]
            facet.group = groups[index]
            return facet
        }
        let end = Self.styled(moved, seams: seams)
        let endCamera = next ?? camera
        folds.append(PaperCraneFold(
            pieces: pieces,
            bodies: bodies,
            end: end,
            startCamera: camera,
            endCamera: endCamera,
            hint: PaperCraneHint(creases: creases, arrows: arrows, mountain: mountain, turnOver: turnOver),
            seams: seams.map { PaperCraneSeam(start: $0.0, end: $0.1) },
        ))
        facets = end
        camera = endCamera
    }

    struct Driver {
        let facets: [Int]
        let pose: (Double) -> PaperCranePose
        let group: String?
        var crease: (SIMD3<Double>, SIMD3<Double>)?
        var arrow = false
    }

    mutating func settle(
        drivers: [Driver],
        mirror: (SIMD2<Double>, SIMD2<Double>),
        front: SIMD2<Double>,
        camera next: PaperCraneCamera,
        closed: [Int] = [],
        bias: (SIMD2<Double>) -> SIMD3<Double> = { _ in .zero },
        iterations: Int = 24,
    ) {
        var keys: [SIMD2<Int64>: Int] = [:]
        var papers: [SIMD2<Double>] = []
        func node(_ point: SIMD2<Double>) -> Int {
            let key = SIMD2(Int64((point.x * 1_000_000).rounded()), Int64((point.y * 1_000_000).rounded()))
            if let index = keys[key] {
                return index
            }
            keys[key] = papers.count
            papers.append(point)
            return papers.count - 1
        }
        for facet in facets {
            for point in facet.paper {
                _ = node(point)
            }
        }
        let loops = facets.map { facet -> [Int] in
            var loop: [Int] = []
            for corner in facet.paper.indices {
                let start = facet.paper[corner]
                let end = facet.paper[(corner + 1) % facet.paper.count]
                loop.append(node(start))
                let direction = end - start
                let length = simd_length_squared(direction)
                guard length > 0 else { continue }
                let inside = papers.indices.compactMap { index -> (Int, Double)? in
                    let offset = papers[index] - start
                    let along = simd_dot(offset, direction) / length
                    let cross = abs(offset.x * direction.y - offset.y * direction.x) / length.squareRoot()
                    return along > 0.000_001 && along < 0.999_999 && cross < 0.000_001 ? (index, along) : nil
                }
                loop += inside.sorted { $0.1 < $1.1 }.map(\.0)
            }
            return loop
        }
        for index in facets.indices {
            let loop = loops[index]
            facets[index].points = loop.map { facets[index].place(papers[$0]) }
            facets[index].paper = loop.map { papers[$0] }
            facets[index].edges = Array(repeating: .edge, count: loop.count)
        }
        let rests = facets.map(\.points)
        var positions = papers.map { _ in SIMD3<Double>.zero }
        for index in facets.indices {
            for (corner, point) in zip(loops[index], rests[index]) {
                positions[corner] = point
            }
        }

        let axis = mirror.1 - mirror.0
        func reflect(_ point: SIMD2<Double>) -> SIMD2<Double> {
            let unit = simd_normalize(axis)
            let offset = point - mirror.0
            return mirror.0 + unit * (2 * simd_dot(offset, unit)) - offset
        }
        func sideOf(_ point: SIMD2<Double>) -> Double {
            axis.x * (point.y - mirror.0.y) - axis.y * (point.x - mirror.0.x)
        }
        let frontSign: Double = sideOf(front) >= 0 ? 1 : -1
        let partners = papers.map { point -> Int? in
            let image = reflect(point)
            return papers.indices.min { simd_distance(papers[$0], image) < simd_distance(papers[$1], image) }
                .flatMap { simd_distance(papers[$0], image) < 0.000_01 ? $0 : nil }
        }
        let fronts = papers.map { sideOf($0) * frontSign > 0.000_001 }

        var owner: [Int: Int] = [:]
        for (index, driver) in drivers.enumerated() {
            for facet in driver.facets {
                owner[facet] = index
            }
        }
        var pinch = Array(repeating: false, count: papers.count)
        for index in closed {
            for corner in loops[index] {
                pinch[corner] = true
            }
        }
        var rotations = facets.map { _ in simd_quatd(ix: 0, iy: 0, iz: 0, r: 1) }
        var samples = facets.map { _ in [PaperCranePose]() }
        var tracks = facets.map { _ in [[SIMD3<Double>]]() }

        func fit(_ index: Int) -> PaperCranePose {
            let rest = rests[index]
            let current = loops[index].map { positions[$0] }
            let restCenter = rest.reduce(SIMD3<Double>.zero, +) / Double(rest.count)
            let currentCenter = current.reduce(SIMD3<Double>.zero, +) / Double(current.count)
            var matrix = simd_double3x3()
            for (r, x) in zip(rest, current) {
                let a = x - currentCenter
                let b = r - restCenter
                matrix.columns.0 += a * b.x
                matrix.columns.1 += a * b.y
                matrix.columns.2 += a * b.z
            }
            var rotation = rotations[index]
            for _ in 0..<12 {
                let basis = simd_double3x3(rotation)
                let torque = simd_cross(basis.columns.0, matrix.columns.0) + simd_cross(basis.columns.1, matrix.columns.1) + simd_cross(basis.columns.2, matrix.columns.2)
                let scale = abs(simd_dot(basis.columns.0, matrix.columns.0) + simd_dot(basis.columns.1, matrix.columns.1) + simd_dot(basis.columns.2, matrix.columns.2)) + 0.000_000_001
                let omega = torque / scale
                let angle = simd_length(omega)
                guard angle > 0.000_000_001 else { break }
                rotation = (simd_quatd(angle: angle, axis: omega / angle) * rotation).normalized
            }
            rotations[index] = rotation
            return PaperCranePose(rotation: rotation, translation: currentCenter - rotation.act(restCenter))
        }

        for step in 0...Self.sampleCount {
            let progress = Double(step) / Double(Self.sampleCount)
            let poses = drivers.map { $0.pose(progress) }
            if step == 1 {
                for index in positions.indices {
                    positions[index] += bias(papers[index])
                }
            }
            var current = facets.indices.map { _ in PaperCranePose.identity }
            for _ in 0..<(step == 0 ? 1 : iterations) {
                var sums = positions.map { _ in SIMD3<Double>.zero }
                var weights = positions.map { _ in 0.0 }
                for index in facets.indices {
                    let pose: PaperCranePose
                    let weight: Double
                    if let driver = owner[index] {
                        pose = poses[driver]
                        weight = 40
                    } else {
                        pose = step == 0 ? .identity : fit(index)
                        weight = 1
                    }
                    current[index] = pose
                    for (corner, rest) in zip(loops[index], rests[index]) {
                        sums[corner] += pose.apply(rest) * weight
                        weights[corner] += weight
                    }
                }
                for index in positions.indices where weights[index] > 0 {
                    positions[index] = sums[index] / weights[index]
                    if pinch[index] {
                        positions[index].z *= 1 - progress
                    }
                }
                for index in positions.indices {
                    guard let partner = partners[index] else { continue }
                    if partner == index {
                        positions[index].z = 0
                        continue
                    }
                    let mirrored = SIMD3(positions[partner].x, positions[partner].y, -positions[partner].z)
                    var average = (positions[index] + mirrored) / 2
                    if fronts[index] {
                        average.z = max(0, average.z)
                    } else if fronts[partner] {
                        average.z = min(0, average.z)
                    }
                    positions[index] = average
                    positions[partner] = SIMD3(average.x, average.y, -average.z)
                }
            }
            for index in facets.indices {
                samples[index].append(owner[index] == nil && step > 0 ? fit(index) : current[index])
                tracks[index].append(loops[index].map { positions[$0] })
            }
        }

        var motions = facets.indices.map { index in
            Motion(facets: [index], samples: samples[index], group: owner[index].flatMap { drivers[$0].group }, arrow: false, track: tracks[index])
        }
        for driver in drivers {
            guard let first = driver.facets.first else { continue }
            motions[first].crease = driver.crease
            motions[first].arrow = driver.arrow
        }
        perform(motions, camera: next)
    }

    private func crease(_ a: SIMD3<Double>, _ b: SIMD3<Double>, along indices: [Int]) -> [SIMD3<Double>] {
        let axis = simd_normalize(b - a)
        let points = indices.flatMap { facets[$0].points }
        let near = points.filter { abs(PaperCraneGeometry.side($0, a, b)) < 0.000_01 && abs($0.z) < 0.000_01 }
        let candidates = near.count >= 2 ? near : [a, b]
        let projections = candidates.map { simd_dot($0 - a, axis) }
        return [a + axis * (projections.min() ?? 0), a + axis * (projections.max() ?? 0)]
    }

    static func styled(_ facets: [PaperCraneFacet], seams: [(SIMD2<Double>, SIMD2<Double>)]) -> [PaperCraneFacet] {
        facets.indices.map { index in
            var facet = facets[index]
            facet.edges = facet.paper.indices.map { edge in
                let p = facet.paper[edge]
                let q = facet.paper[(edge + 1) % facet.paper.count]
                var shared = false
                var folded = false
                for other in facets.indices where other != index && near(facet.paper, facets[other].paper) {
                    let neighbor = facets[other]
                    let touches = neighbor.paper.indices.contains { corner in
                        PaperCraneGeometry.overlaps(p, q, neighbor.paper[corner], neighbor.paper[(corner + 1) % neighbor.paper.count])
                    }
                    guard touches else { continue }
                    shared = true
                    let probe = neighbor.paper.reduce(SIMD2<Double>.zero, +) / Double(neighbor.paper.count)
                    if simd_distance(facet.place(probe), neighbor.place(probe)) > 0.000_01 {
                        folded = true
                    }
                }
                if !shared || folded {
                    return .edge
                }
                let hidden = seams.contains { PaperCraneGeometry.overlaps($0.0, $0.1, p, q) }
                return hidden ? .hidden : .crease
            }
            return facet
        }
    }
}
