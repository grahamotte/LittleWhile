import SwiftUI

struct PlaneVector: Equatable {
    var x: Double
    var y: Double
    var z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(latitude: Double, longitude: Double) {
        let latitude = latitude * .pi / 180
        let longitude = longitude * .pi / 180
        self.init(x: cos(latitude) * cos(longitude), y: cos(latitude) * sin(longitude), z: sin(latitude))
    }

    var latitude: Double {
        asin(min(1, max(-1, normalized.z))) * 180 / .pi
    }

    var longitude: Double {
        abs(x) < 1e-12 && abs(y) < 1e-12 ? 0 : atan2(y, x) * 180 / .pi
    }

    var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    var normalized: PlaneVector {
        let length = length
        guard length > 1e-12, length.isFinite else { return PlaneVector(x: 1, y: 0, z: 0) }
        return self * (1 / length)
    }

    func dot(_ other: PlaneVector) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: PlaneVector) -> PlaneVector {
        PlaneVector(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
    }

    func angle(to other: PlaneVector) -> Double {
        atan2(cross(other).length, dot(other))
    }

    static func + (left: PlaneVector, right: PlaneVector) -> PlaneVector {
        PlaneVector(x: left.x + right.x, y: left.y + right.y, z: left.z + right.z)
    }

    static func - (left: PlaneVector, right: PlaneVector) -> PlaneVector {
        PlaneVector(x: left.x - right.x, y: left.y - right.y, z: left.z - right.z)
    }

    static func * (vector: PlaneVector, scale: Double) -> PlaneVector {
        PlaneVector(x: vector.x * scale, y: vector.y * scale, z: vector.z * scale)
    }

    static func slerp(_ start: PlaneVector, _ end: PlaneVector, _ fraction: Double) -> PlaneVector {
        let angle = start.angle(to: end)
        guard angle > 1e-9 else { return start }
        guard angle < .pi - 1e-6 else { return (start * (1 - fraction) + end * fraction).normalized }
        let sine = sin(angle)
        return start * (sin((1 - fraction) * angle) / sine) + end * (sin(fraction * angle) / sine)
    }
}

struct PlaneCamera: Equatable {
    static let maximumLatitude = 80.0
    static let idleDelay: TimeInterval = 3
    static let returnDuration: TimeInterval = 1.2
    static let idle = PlaneCamera(latitude: 25, longitude: 15)

    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ vector: PlaneVector) {
        self.init(latitude: vector.latitude, longitude: vector.longitude)
    }

    var vector: PlaneVector {
        PlaneVector(latitude: latitude, longitude: longitude)
    }

    func dragged(by translation: CGSize, radius: CGFloat) -> PlaneCamera {
        guard radius > 0, translation.width.isFinite, translation.height.isFinite else { return self }
        let latitude = latitude + Double(translation.height / radius) * 180 / .pi
        let longitude = longitude - Double(translation.width / radius) * 180 / .pi
        return PlaneCamera(
            latitude: min(Self.maximumLatitude, max(-Self.maximumLatitude, latitude)),
            longitude: remainder(longitude, 360),
        )
    }

    static func returning(from manual: PlaneCamera, to follow: PlaneCamera, idle: TimeInterval, duration: TimeInterval = returnDuration) -> PlaneCamera? {
        let idle = idle.isFinite ? max(0, idle) : idleDelay + duration
        guard idle < idleDelay + duration else { return nil }
        guard idle > idleDelay else { return manual }
        let progress = min(1, (idle - idleDelay) / max(0.001, duration))
        let eased = progress * progress * (3 - 2 * progress)
        return PlaneCamera(PlaneVector.slerp(manual.vector, follow.vector, eased))
    }
}

enum PlaneDaylight {
    static let tilt = 23.44
    static let twilight = 22 * Double.pi / 180
    static let dawn = sin(twilight)
    static let dusk = -sin(twilight)

    static func sun(at date: Date) -> PlaneVector {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        let hours = (seconds < 0 ? seconds + 86_400 : seconds) / 3_600
        let declination = tilt * sin(2 * .pi * (day - 81) / 365)
        return PlaneVector(latitude: declination, longitude: remainder(180 - hours * 15, 360))
    }

    static func night(at point: PlaneVector, sun: PlaneVector) -> Double {
        let progress = min(1, max(0, (dawn - point.dot(sun)) / (dawn - dusk)))
        return progress * progress * (3 - 2 * progress)
    }
}

struct PlaneGlobe {
    let center: CGPoint
    let radius: CGFloat
    let camera: PlaneCamera
    private let east: PlaneVector
    private let north: PlaneVector
    private let forward: PlaneVector

    init(center: CGPoint, radius: CGFloat, camera: PlaneCamera) {
        self.center = center
        self.radius = max(0, radius.isFinite ? radius : 0)
        self.camera = camera
        let latitude = camera.latitude * .pi / 180
        let longitude = camera.longitude * .pi / 180
        forward = camera.vector
        east = PlaneVector(x: -sin(longitude), y: cos(longitude), z: 0)
        north = PlaneVector(x: -sin(latitude) * cos(longitude), y: -sin(latitude) * sin(longitude), z: cos(latitude))
    }

    func depth(_ point: PlaneVector) -> Double {
        forward.dot(point)
    }

    func project(_ point: PlaneVector, altitude: Double = 0) -> CGPoint {
        let scale = radius * CGFloat(1 + altitude)
        return CGPoint(x: center.x + scale * CGFloat(east.dot(point)), y: center.y - scale * CGFloat(north.dot(point)))
    }

    func screenVector(_ vector: PlaneVector) -> CGVector {
        CGVector(dx: CGFloat(east.dot(vector)), dy: -CGFloat(north.dot(vector)))
    }

    func limb(_ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y - radius * CGFloat(sin(angle)))
    }

    func landPath(_ ring: [PlaneVector]) -> Path {
        var path = Path()
        guard ring.count > 2, let first = ring.firstIndex(where: { depth($0) > 0 }) else { return path }
        let ordered = Array(ring[first...] + ring[..<first])
        var outline: [(east: Double, north: Double, visible: Bool)] = []
        for (index, start) in ordered.enumerated() {
            let end = ordered[(index + 1) % ordered.count]
            let startDepth = depth(start)
            let endDepth = depth(end)
            outline.append((east.dot(start), north.dot(start), startDepth > 0))
            if (startDepth > 0) != (endDepth > 0) {
                let crossing = start + (end - start) * (startDepth / (startDepth - endDepth))
                outline.append((east.dot(crossing), north.dot(crossing), false))
            }
        }

        struct Run {
            var start: Int
            var end: Int
            var sweep: Double
            var nearest: Double
        }
        var runs: [Run] = []
        var winding = 0.0
        for index in outline.indices {
            let point = outline[index]
            let next = outline[(index + 1) % outline.count]
            let delta = remainder(atan2(next.north, next.east) - atan2(point.north, point.east), 2 * .pi)
            winding += delta
            guard !point.visible else { continue }
            let radius = (point.east * point.east + point.north * point.north).squareRoot()
            if let last = runs.last, last.end == index - 1 {
                runs[runs.count - 1].end = index
                runs[runs.count - 1].nearest = min(last.nearest, radius)
            } else {
                runs.append(Run(start: index, end: index, sweep: 0, nearest: radius))
            }
            if !next.visible {
                runs[runs.count - 1].sweep += delta
            }
        }
        if winding > .pi, let closest = runs.indices.min(by: { runs[$0].nearest < runs[$1].nearest }) {
            runs[closest].sweep -= 2 * .pi
        }

        path.move(to: project(ordered[0]))
        var index = 1
        while index < outline.count {
            if let run = runs.first(where: { $0.start == index }) {
                let angle = atan2(outline[index].north, outline[index].east)
                let steps = max(1, Int((abs(run.sweep) / 0.1).rounded(.up)))
                for step in 0...steps {
                    path.addLine(to: limb(angle + run.sweep * Double(step) / Double(steps)))
                }
                index = run.end + 1
            } else {
                let point = outline[index]
                path.addLine(to: CGPoint(x: center.x + radius * CGFloat(point.east), y: center.y - radius * CGFloat(point.north)))
                index += 1
            }
        }
        path.closeSubpath()
        return path
    }

    func capPath(around center: PlaneVector, radius angle: Double) -> Path {
        let center = center.normalized
        let reference = abs(center.z) < 0.9 ? PlaneVector(x: 0, y: 0, z: 1) : PlaneVector(x: 1, y: 0, z: 0)
        let first = reference.cross(center).normalized
        let second = center.cross(first)
        let ring = stride(from: 0.0, to: 360, by: 3).map { degrees -> PlaneVector in
            let turn = -degrees * .pi / 180
            return center * cos(angle) + (first * cos(turn) + second * sin(turn)) * sin(angle)
        }
        return landPath(ring)
    }

    func nightPath(sun: PlaneVector, radius angle: Double) -> Path {
        guard angle > .pi / 2 else { return capPath(around: sun * -1, radius: angle) }
        var path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.addPath(capPath(around: sun, radius: .pi - angle))
        return path
    }

    func linePath(_ points: [PlaneVector], altitude: Double = 0) -> Path {
        var path = Path()
        var drawing = false
        for (index, point) in points.enumerated() {
            let visible = depth(point) > 0
            if visible {
                if drawing {
                    path.addLine(to: project(point, altitude: altitude))
                } else if index > 0 {
                    path.move(to: project(crossing(points[index - 1], point), altitude: altitude))
                    path.addLine(to: project(point, altitude: altitude))
                } else {
                    path.move(to: project(point, altitude: altitude))
                }
            } else if drawing {
                path.addLine(to: project(crossing(points[index - 1], point), altitude: altitude))
            }
            drawing = visible
        }
        return path
    }

    static func arc(from start: PlaneVector, to end: PlaneVector, fraction: Double = 1, maximumStep: Double = PlaneAtlas.maximumStep) -> [PlaneVector] {
        let fraction = min(1, max(0, fraction.isFinite ? fraction : 0))
        let angle = start.angle(to: end) * fraction
        let steps = max(1, Int((angle / maximumStep).rounded(.up)))
        return (0...steps).map { PlaneVector.slerp(start, end, fraction * Double($0) / Double(steps)) }
    }

    static func parallel(latitude: Double) -> [PlaneVector] {
        stride(from: -180.0, through: 180, by: 4).map { PlaneVector(latitude: latitude, longitude: $0) }
    }

    static func meridian(longitude: Double) -> [PlaneVector] {
        stride(from: -90.0, through: 90, by: 4).map { PlaneVector(latitude: $0, longitude: longitude) }
    }

    private func crossing(_ start: PlaneVector, _ end: PlaneVector) -> PlaneVector {
        let startDepth = depth(start)
        let endDepth = depth(end)
        guard startDepth != endDepth else { return start }
        return (start + (end - start) * (startDepth / (startDepth - endDepth))).normalized
    }
}
