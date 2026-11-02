import Foundation

struct PlaneLeg: Equatable {
    let from: Int
    let to: Int
    let kilometers: Double
}

struct PlaneFlight: Equatable {
    enum Stage: Equatable {
        case boarding
        case flying
        case landed
    }

    let stage: Stage
    let leg: Int
    let progress: Double
    let legProgress: Double
    let position: PlaneVector
    let heading: PlaneVector
    let altitude: Double
    let remainingKilometers: Double
}

struct PlaneTrip {
    struct Key: Equatable {
        let seed: UUID
        let goalSeconds: Int
        let cycle: Int
    }

    static let earthRadius = 6_371.0
    static let equatorSeconds: TimeInterval = 2 * 60 * 60
    static let bucketSeconds: TimeInterval = 5 * 60
    static let longestLegSeconds: TimeInterval = 55 * 60
    static let shortestHop = 300.0
    static let climb = 0.12

    let key: Key
    let cities: [PlaneCity]
    let legs: [PlaneLeg]

    init(key: Key, cities: [PlaneCity] = PlaneAtlas.cities) {
        self.key = key
        self.cities = cities
        let points = cities.map(\.point)
        let goal = TimeInterval(max(0, key.goalSeconds))
        let count = Self.legCount(goalSeconds: goal)
        let target = Self.bucket(goal / Double(count))
        var random = Random(seed: key.seed)
        var legs: [PlaneLeg] = []
        guard points.count > 1 else {
            self.legs = []
            return
        }
        for _ in 0...max(0, key.cycle) {
            var trip: [PlaneLeg] = []
            for _ in 0..<count {
                let origin = trip.last?.to ?? legs.last?.to
                let visited = Set(trip.map(\.from) + [origin].compactMap { $0 })
                var best = Double.infinity
                var candidates: [PlaneLeg] = []
                let origins = origin.map { [$0] } ?? Array(points.indices)
                for from in origins {
                    for to in points.indices where to != from && !visited.contains(to) {
                        let kilometers = points[from].angle(to: points[to]) * Self.earthRadius
                        guard kilometers >= Self.shortestHop else { continue }
                        let miss = abs(Self.bucket(Self.seconds(kilometers: kilometers)) - target)
                        if miss < best {
                            best = miss
                            candidates = [PlaneLeg(from: from, to: to, kilometers: kilometers)]
                        } else if miss == best {
                            candidates.append(PlaneLeg(from: from, to: to, kilometers: kilometers))
                        }
                    }
                }
                guard !candidates.isEmpty else { break }
                trip.append(candidates[Int(random.next() % UInt64(candidates.count))])
            }
            legs = trip
        }
        self.legs = legs
    }

    static func seconds(kilometers: Double) -> TimeInterval {
        kilometers / (2 * .pi * earthRadius) * equatorSeconds
    }

    static func bucket(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return (max(0, seconds) / bucketSeconds).rounded() * bucketSeconds
    }

    static func legCount(goalSeconds: TimeInterval) -> Int {
        guard goalSeconds.isFinite, goalSeconds > longestLegSeconds else { return 1 }
        return Int((goalSeconds / longestLegSeconds).rounded(.up))
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

    var kilometers: Double {
        legs.reduce(0) { $0 + $1.kilometers }
    }

    var stops: [PlaneCity] {
        guard let first = legs.first else { return [] }
        return [cities[first.from]] + legs.map { cities[$0.to] }
    }

    static func showsFlight(status: TimerSnapshot.Status) -> Bool {
        status == .running || status == .paused
    }

    func flight(elapsed rawElapsed: TimeInterval) -> PlaneFlight? {
        guard let first = legs.first, let last = legs.last else { return nil }
        let goal = TimeInterval(max(0, key.goalSeconds))
        let elapsed = rawElapsed.isFinite ? max(0, rawElapsed) : 0
        let total = kilometers
        if elapsed <= 0 && goal > 0 {
            return flight(.boarding, leg: 0, progress: 0, along: 0, total: total, of: first)
        }
        if goal <= 0 || elapsed >= goal {
            return flight(.landed, leg: legs.count - 1, progress: 1, along: 1, total: total, of: last)
        }
        let progress = elapsed / goal
        var travelled = progress * total
        for (index, leg) in legs.enumerated() {
            if travelled <= leg.kilometers || index == legs.count - 1 {
                let along = leg.kilometers > 0 ? min(1, travelled / leg.kilometers) : 1
                return flight(.flying, leg: index, progress: progress, along: along, total: total, of: leg)
            }
            travelled -= leg.kilometers
        }
        return nil
    }

    static func caption(flight: PlaneFlight?, trip: PlaneTrip) -> String {
        guard let flight else { return "" }
        switch flight.stage {
        case .boarding:
            return "now boarding"
        case .flying:
            let kilometers = Int(flight.remainingKilometers.rounded())
            return "\(kilometers.formatted(.number.grouping(.automatic))) km to go"
        case .landed:
            return "welcome to \(trip.stops.last?.name ?? "")"
        }
    }

    static func route(flight: PlaneFlight?, trip: PlaneTrip) -> String {
        guard let flight, trip.legs.indices.contains(flight.leg) else { return "" }
        let leg = trip.legs[flight.leg]
        return "\(trip.cities[leg.from].name) → \(trip.cities[leg.to].name)"
    }

    private func flight(_ stage: PlaneFlight.Stage, leg index: Int, progress: Double, along: Double, total: Double, of leg: PlaneLeg) -> PlaneFlight {
        let start = cities[leg.from].point
        let end = cities[leg.to].point
        let position = PlaneVector.slerp(start, end, along)
        let axis = start.cross(end)
        let heading = axis.length > 1e-9 ? axis.normalized.cross(position).normalized : PlaneVector(x: 0, y: 0, z: 1)
        let lift = min(along, 1 - along) / Self.climb
        let altitude = stage == .flying ? Self.smoothstep(lift) : 0
        let flown = legs.prefix(index).reduce(0) { $0 + $1.kilometers } + leg.kilometers * along
        return PlaneFlight(
            stage: stage,
            leg: index,
            progress: progress,
            legProgress: along,
            position: position,
            heading: heading,
            altitude: altitude,
            remainingKilometers: max(0, total - flown),
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * (3 - 2 * x)
    }

    private struct Random {
        var state: UInt64

        init(seed: UUID) {
            state = seed.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }
}
