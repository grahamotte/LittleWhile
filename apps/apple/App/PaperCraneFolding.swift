import CoreGraphics
import Foundation
import simd

enum PaperCraneFace: Equatable {
    case white
    case color
}

struct PaperCraneFacet: Equatable {
    var group: String
    var points: [SIMD3<Double>]
    var strokes: [Bool]
    var layer: Double
    var front: PaperCraneFace
    var back: PaperCraneFace

    var centroid: SIMD3<Double> {
        points.reduce(SIMD3<Double>.zero, +) / Double(max(1, points.count))
    }

    var visibleFace: PaperCraneFace {
        PaperCraneGeometry.newell(points).z >= 0 ? front : back
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

enum PaperCraneMove: Equatable {
    case still
    case rotate(origin: SIMD3<Double>, axis: SIMD3<Double>, angle: Double)
    case morph(via: [SIMD3<Double>], to: [SIMD3<Double>])
    case swing(pivot: SIMD3<Double>, angle: Double, to: [SIMD3<Double>])
}

struct PaperCranePiece: Equatable {
    let facet: PaperCraneFacet
    let move: PaperCraneMove
    let window: ClosedRange<Double>
    let endLayer: Double
    let tucked: Bool

    func progress(_ fold: Double) -> Double {
        let span = max(0.0001, window.upperBound - window.lowerBound)
        return PaperCraneGeometry.ease((fold - window.lowerBound) / span)
    }

    func points(at fold: Double) -> [SIMD3<Double>] {
        let t = progress(fold)
        switch move {
        case .still:
            return facet.points
        case let .rotate(origin, axis, angle):
            return facet.points.map { PaperCraneGeometry.rotate($0, origin: origin, axis: axis, angle: angle * t) }
        case let .morph(via, to):
            return facet.points.indices.map { index in
                let start = facet.points[index]
                let end = to[index]
                let control = via[index] * 2 - (start + end) / 2
                let inverse = 1 - t
                return start * (inverse * inverse) + control * (2 * inverse * t) + end * (t * t)
            }
        case let .swing(pivot, angle, to):
            return facet.points.indices.map { index in
                let point = facet.points[index]
                let full = PaperCraneGeometry.rotate(point, origin: pivot, axis: SIMD3(0, 0, 1), angle: angle)
                return PaperCraneGeometry.rotate(point, origin: pivot, axis: SIMD3(0, 0, 1), angle: angle * t) + (to[index] - full) * t
            }
        }
    }

    func layer(at fold: Double) -> Double {
        facet.layer + (endLayer - facet.layer) * progress(fold)
    }

    var end: PaperCraneFacet {
        var facet = facet
        facet.points = points(at: 1)
        facet.layer = endLayer
        if case .swing = move {
            swap(&facet.front, &facet.back)
        }
        return facet
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

struct PaperCraneFold: Equatable {
    let pieces: [PaperCranePiece]
    let startCamera: PaperCraneCamera
    let endCamera: PaperCraneCamera
    let hint: PaperCraneHint

    var start: [PaperCraneFacet] {
        pieces.map(\.facet)
    }

    var end: [PaperCraneFacet] {
        pieces.map(\.end)
    }
}

enum PaperCraneGeometry {
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

    static func rotate(_ point: SIMD3<Double>, origin: SIMD3<Double>, axis: SIMD3<Double>, angle: Double) -> SIMD3<Double> {
        let vector = point - origin
        let cosine = cos(angle)
        return origin + vector * cosine + simd_cross(axis, vector) * sin(angle) + axis * simd_dot(axis, vector) * (1 - cosine)
    }

    static func reflect(_ point: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        let axis = simd_normalize(SIMD3(b.x - a.x, b.y - a.y, 0))
        let vector = SIMD3(point.x - a.x, point.y - a.y, 0)
        let along = axis * simd_dot(axis, vector)
        let mirrored = along * 2 - vector
        return SIMD3(a.x + mirrored.x, a.y + mirrored.y, point.z)
    }

    static func side(_ point: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
    }

    static func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    static func split(
        _ facet: PaperCraneFacet,
        _ a: SIMD3<Double>,
        _ b: SIMD3<Double>,
        crease: Bool,
    ) -> [PaperCraneFacet] {
        let length = simd_length(SIMD2(b.x - a.x, b.y - a.y))
        let distances = facet.points.map { side($0, a, b) / max(0.000_001, length) }
        let epsilon = 0.000_001
        guard distances.contains(where: { $0 > epsilon }), distances.contains(where: { $0 < -epsilon }) else {
            return [facet]
        }
        return [1.0, -1.0].compactMap { sign in
            var points: [SIMD3<Double>] = []
            var strokes: [Bool] = []
            let count = facet.points.count
            for index in 0..<count {
                let next = (index + 1) % count
                let current = distances[index] * sign
                let following = distances[next] * sign
                let currentIn = current >= -epsilon
                let followingIn = following >= -epsilon
                if currentIn {
                    points.append(facet.points[index])
                    if abs(current) <= epsilon && following < -epsilon {
                        strokes.append(crease)
                    } else {
                        strokes.append(facet.strokes[index])
                    }
                }
                if (current > epsilon && following < -epsilon) || (current < -epsilon && following > epsilon) {
                    let ratio = current / (current - following)
                    let point = facet.points[index] + (facet.points[next] - facet.points[index]) * ratio
                    points.append(point)
                    strokes.append(currentIn ? crease : facet.strokes[index])
                }
            }
            guard points.count >= 3, area(points) > 0.000_001 else { return nil }
            var piece = facet
            piece.points = points
            piece.strokes = strokes
            return piece
        }
    }
}

struct PaperCraneWorkshop {
    enum Layering {
        case top
        case bottom
        case keep
        case value(Double)
    }

    enum Kind {
        case fold(SIMD3<Double>, SIMD3<Double>, mountain: Bool, angle: Double, layering: Layering)
        case morph(to: (SIMD3<Double>) -> SIMD3<Double>, via: (SIMD3<Double>, SIMD3<Double>) -> SIMD3<Double>)
        case swing(SIMD3<Double>, SIMD3<Double>, pivot: SIMD3<Double>, turn: Double)
        case turnOver
    }

    struct Action {
        let select: (PaperCraneFacet) -> Bool
        let kind: Kind
        var window: ClosedRange<Double> = 0...1
        var regroup: String?
        var arrow = true
    }

    private(set) var facets: [PaperCraneFacet]
    private(set) var folds: [PaperCraneFold] = []
    private var camera = PaperCraneCamera.flat

    init(facets: [PaperCraneFacet]) {
        self.facets = facets
    }

    mutating func cut(_ a: SIMD3<Double>, _ b: SIMD3<Double>, crease: Bool = false, where select: (PaperCraneFacet) -> Bool) {
        facets = facets.flatMap { select($0) ? PaperCraneGeometry.split($0, a, b, crease: crease) : [$0] }
    }

    mutating func paint(_ face: PaperCraneFace, where select: (PaperCraneFacet) -> Bool) {
        for index in facets.indices where select(facets[index]) {
            facets[index].front = face
            facets[index].back = face
        }
    }

    mutating func regroup(_ group: String, where select: (PaperCraneFacet) -> Bool) {
        for index in facets.indices where select(facets[index]) {
            facets[index].group = group
        }
    }

    mutating func perform(_ actions: [Action], camera next: PaperCraneCamera? = nil) {
        var moves = Array(repeating: PaperCraneMove.still, count: facets.count)
        var windows = Array(repeating: 0.0...1.0, count: facets.count)
        var layers = facets.map(\.layer)
        var tucked = Array(repeating: false, count: facets.count)
        var groups = facets.map(\.group)
        var strokes = facets.map(\.strokes)
        var creases: [[SIMD3<Double>]] = []
        var arrows: [PaperCraneHint.Arrow] = []
        var mountain = false
        var turnOver = false
        var taken = Set<Int>()

        for action in actions {
            let chosen = facets.indices.filter { !taken.contains($0) && action.select(facets[$0]) }
            guard !chosen.isEmpty else { continue }
            taken.formUnion(chosen)
            let still = facets.indices.filter { !chosen.contains($0) }
            let startCenter = Self.center(chosen.map { facets[$0] })

            switch action.kind {
            case let .fold(a, b, isMountain, angle, layering):
                let axis = simd_normalize(SIMD3(b.x - a.x, b.y - a.y, 0))
                let offset = startCenter - a
                let lift = axis.x * offset.y - axis.y * offset.x
                let direction: Double = (lift >= 0 ? 1 : -1) * (isMountain ? -1 : 1)
                let ordered = chosen.sorted { facets[$0].layer > facets[$1].layer }
                let ceiling = still.map { layers[$0] }.max() ?? 0
                let floor = still.map { layers[$0] }.min() ?? 0
                for (rank, index) in ordered.enumerated() {
                    moves[index] = .rotate(origin: a, axis: axis, angle: angle * direction)
                    switch layering {
                    case .top:
                        layers[index] = ceiling + 0.01 * Double(rank + 1)
                    case .bottom:
                        layers[index] = floor - 0.01 * Double(ordered.count - rank)
                    case .keep:
                        break
                    case let .value(value):
                        layers[index] = value + 0.001 * Double(rank)
                    }
                }
                for index in facets.indices where chosen.contains(index) || abs(angle) > 3 {
                    let points = facets[index].points
                    for edge in points.indices {
                        let next = points[(edge + 1) % points.count]
                        if abs(PaperCraneGeometry.side(points[edge], a, b)) < 0.000_01 && abs(PaperCraneGeometry.side(next, a, b)) < 0.000_01 {
                            strokes[index][edge] = true
                        }
                    }
                }
                if action.arrow {
                    creases.append(Self.crease(a, b, along: chosen.map { facets[$0] }))
                    mountain = mountain || isMountain
                }
            case let .morph(map, via):
                for index in chosen {
                    let points = facets[index].points
                    let targets = points.map(map)
                    moves[index] = .morph(via: zip(points, targets).map(via), to: targets)
                }
            case let .swing(a, b, pivot, turn):
                let mirrored = PaperCraneGeometry.reflect(startCenter, a, b)
                var angle = atan2(mirrored.y - pivot.y, mirrored.x - pivot.x) - atan2(startCenter.y - pivot.y, startCenter.x - pivot.x)
                while angle * turn <= 0 {
                    angle += turn > 0 ? 2 * .pi : -2 * .pi
                }
                while abs(angle) > 2 * .pi {
                    angle -= turn > 0 ? 2 * .pi : -2 * .pi
                }
                for index in chosen {
                    moves[index] = .swing(pivot: pivot, angle: angle, to: facets[index].points.map { PaperCraneGeometry.reflect($0, a, b) })
                    tucked[index] = true
                }
                creases.append(Self.crease(a, b, along: chosen.map { facets[$0] }))
            case .turnOver:
                let xs = facets.flatMap { $0.points.map(\.x) }
                let middle = ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
                for index in chosen {
                    moves[index] = .rotate(origin: SIMD3(middle, 0, 0), axis: SIMD3(0, 1, 0), angle: .pi)
                    layers[index] = -facets[index].layer
                }
                turnOver = true
            }

            for index in chosen {
                windows[index] = action.window
                if let group = action.regroup {
                    groups[index] = group
                }
            }

            if action.arrow, !turnOver {
                let ends = chosen.map { index in
                    PaperCranePiece(facet: facets[index], move: moves[index], window: 0...1, endLayer: layers[index], tucked: false).end
                }
                arrows.append(PaperCraneHint.Arrow(from: startCenter, to: Self.center(ends)))
            }
        }

        let pieces = facets.indices.map { index in
            var facet = facets[index]
            facet.strokes = strokes[index]
            return PaperCranePiece(facet: facet, move: moves[index], window: windows[index], endLayer: layers[index], tucked: tucked[index])
        }
        let endCamera = next ?? camera
        let fold = PaperCraneFold(
            pieces: pieces,
            startCamera: camera,
            endCamera: endCamera,
            hint: PaperCraneHint(creases: creases, arrows: arrows, mountain: mountain, turnOver: turnOver),
        )
        folds.append(fold)
        facets = fold.end.enumerated().map { index, facet in
            var facet = facet
            facet.group = groups[index]
            return facet
        }
        camera = endCamera
    }

    private static func center(_ facets: [PaperCraneFacet]) -> SIMD3<Double> {
        var total = SIMD3<Double>.zero
        var weight = 0.0
        for facet in facets {
            let area = PaperCraneGeometry.area(facet.points)
            total += facet.centroid * area
            weight += area
        }
        return weight > 0 ? total / weight : .zero
    }

    private static func crease(_ a: SIMD3<Double>, _ b: SIMD3<Double>, along facets: [PaperCraneFacet]) -> [SIMD3<Double>] {
        let axis = simd_normalize(SIMD3(b.x - a.x, b.y - a.y, 0))
        let points = facets.flatMap(\.points)
        let near = points.filter { abs(PaperCraneGeometry.side($0, a, b)) < 0.000_01 }
        let candidates = near.count >= 2 ? near : points
        let projections = candidates.map { simd_dot($0 - a, axis) }
        let lower = projections.min() ?? 0
        let upper = projections.max() ?? 0
        return [a + axis * lower, a + axis * upper]
    }
}
