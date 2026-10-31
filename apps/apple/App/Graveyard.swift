import CoreGraphics
import Foundation

struct GraveyardGrave: Equatable {
    enum Style: Equatable, CaseIterable {
        case rounded
        case cross
        case arch
        case slab
    }

    let row: Int
    let ground: CGPoint
    let scale: CGFloat
    let style: Style
    let tilt: Double
}

struct GraveyardLayout: Equatable {
    static let rows = [4, 3, 2]
    static let rowDepths: [CGFloat] = [0.69, 0.79, 0.91]
    static let rowScales: [CGFloat] = [0.6, 0.8, 1]
    static let jitter: [CGFloat] = [0.02, -0.03, 0.035, -0.015, -0.04, 0.02, 0.045, 0.03, -0.035]
    static let tilts: [Double] = [-0.06, 0.03, 0.08, -0.04, 0.05, -0.09, 0.02, -0.05, 0.07]
    static let styles: [GraveyardGrave.Style] = [.arch, .cross, .rounded, .slab, .rounded, .slab, .cross, .rounded, .arch]

    let size: CGSize
    let horizon: CGFloat
    let stoneWidth: CGFloat
    let moonCenter: CGPoint
    let moonRadius: CGFloat
    let graves: [GraveyardGrave]

    init(size: CGSize) {
        let width = max(0, size.width.isFinite ? size.width : 0)
        let height = max(0, size.height.isFinite ? size.height : 0)
        self.size = CGSize(width: width, height: height)
        horizon = height * 0.62
        stoneWidth = max(1, min(84, min(width, height * 0.62) * 0.2))
        moonRadius = max(1, min(70, min(width, height) * 0.13))
        moonCenter = CGPoint(x: width * 0.76, y: height * 0.42)
        var graves: [GraveyardGrave] = []
        for (row, count) in Self.rows.enumerated() {
            for column in 0..<count {
                let index = graves.count
                graves.append(GraveyardGrave(
                    row: row,
                    ground: CGPoint(
                        x: width * ((CGFloat(column) + 0.5) / CGFloat(count) + Self.jitter[index]),
                        y: height * Self.rowDepths[row],
                    ),
                    scale: Self.rowScales[row],
                    style: Self.styles[index],
                    tilt: Self.tilts[index],
                ))
            }
        }
        self.graves = graves
    }

    func hillY(at x: CGFloat) -> CGFloat {
        let unit = Double(x / max(1, size.width))
        return horizon - size.height * CGFloat(0.025 + 0.018 * sin(unit * 5.1 + 0.6) + 0.01 * sin(unit * 11.3))
    }

    func stoneSize(_ grave: GraveyardGrave) -> CGSize {
        CGSize(width: stoneWidth * grave.scale, height: stoneWidth * grave.scale * 1.3)
    }

    func ghostSize(_ grave: GraveyardGrave) -> CGSize {
        CGSize(width: stoneWidth * grave.scale * 0.95, height: stoneWidth * grave.scale * 1.2)
    }

    func emergence(_ grave: GraveyardGrave) -> CGPoint {
        CGPoint(x: grave.ground.x, y: grave.ground.y + stoneWidth * grave.scale * 0.14)
    }
}

struct GraveyardGhostPose: Equatable {
    let grave: Int
    let rise: Double
    let offset: CGVector
    let tilt: Double
    let facing: Double
    let arms: Double
}

struct GraveyardScene: Equatable {
    enum Mood: Equatable {
        case quiet
        case haunting
        case party
        case peace
    }

    let ghosts: [GraveyardGhostPose]
    let trembles: [Double]
    let party: Double
    let mood: Mood
}

struct Graveyard {
    struct Key: Equatable {
        let seed: UUID
        let size: CGSize
        let goalSeconds: Int
    }

    static let hauntInterval: TimeInterval = 60
    static let hauntDuration: TimeInterval = 5
    static let emergeDuration: TimeInterval = 0.9
    static let sinkDuration: TimeInterval = 0.9
    static let trembleDuration: TimeInterval = 1.2
    static let partyFade: TimeInterval = 1.5

    let key: Key
    let layout: GraveyardLayout
    let visits: [Int]
    private let phases: [Double]
    private let lineup: [Int]

    init(key: Key) {
        self.key = key
        let layout = GraveyardLayout(size: key.size)
        let count = layout.graves.count
        let haunts = max(0, Int((TimeInterval(max(0, key.goalSeconds)) / Self.hauntInterval).rounded(.up)) - 1)
        var random = Random(seed: key.seed)
        var visits: [Int] = []
        var previous = Int(random.next() % UInt64(count))
        for _ in 0..<haunts {
            previous = (previous + 1 + Int(random.next() % UInt64(count - 1))) % count
            visits.append(previous)
        }
        self.layout = layout
        self.visits = visits
        phases = (0..<count).map { _ in random.unit() * 2 * .pi }
        var lineup = Array(0..<count)
        for index in stride(from: count - 1, to: 0, by: -1) {
            lineup.swapAt(index, Int(random.next() % UInt64(index + 1)))
        }
        self.lineup = lineup
    }

    static func caption(mood: GraveyardScene.Mood) -> String {
        switch mood {
        case .quiet: "all is quiet"
        case .haunting: "boo!"
        case .party: "ghost party!"
        case .peace: "rest in peace"
        }
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

    func scene(elapsed rawElapsed: TimeInterval, restSeconds: Int, settled: Bool) -> GraveyardScene {
        let goal = TimeInterval(max(0, key.goalSeconds))
        let rest = TimeInterval(max(0, restSeconds))
        let elapsed = min(goal + rest, max(0, rawElapsed.isFinite ? rawElapsed : 0))
        let quiet = Array(repeating: 0.0, count: layout.graves.count)
        if elapsed >= goal {
            if rest <= 0 {
                return partyScene(at: 0, rest: 0, settled: true)
            }
            if elapsed < goal + rest {
                return partyScene(at: elapsed - goal, rest: rest, settled: settled)
            }
            return GraveyardScene(ghosts: [], trembles: quiet, party: 0, mood: .peace)
        }

        var trembles = quiet
        var ghosts: [GraveyardGhostPose] = []
        for (index, grave) in visits.enumerated() {
            let start = Self.hauntInterval * Double(index + 1)
            let time = elapsed - start
            if !settled && time < 0 && time > -Self.trembleDuration {
                let ramp = 1 + time / Self.trembleDuration
                trembles[grave] = 0.06 * ramp * ramp * sin(elapsed * 31)
            }
            guard time >= 0, time < Self.hauntDuration else { continue }
            ghosts.append(hauntPose(grave: grave, at: time, settled: settled))
        }
        return GraveyardScene(ghosts: ghosts, trembles: trembles, party: 0, mood: ghosts.isEmpty ? .quiet : .haunting)
    }

    private func hauntPose(grave: Int, at time: TimeInterval, settled: Bool) -> GraveyardGhostPose {
        guard !settled else {
            return GraveyardGhostPose(grave: grave, rise: 1, offset: .zero, tilt: 0, facing: 1, arms: 1)
        }
        let rise: Double
        if time < Self.emergeDuration {
            rise = Self.backOut(time / Self.emergeDuration)
        } else if time > Self.hauntDuration - Self.sinkDuration {
            let progress = (time - (Self.hauntDuration - Self.sinkDuration)) / Self.sinkDuration
            rise = 1 - Self.smoothstep(progress)
        } else {
            rise = 1
        }
        let size = layout.ghostSize(layout.graves[grave])
        let boo = Self.smoothstep(time / 0.6) * (1 - Self.smoothstep((time - 2.6) / 0.6))
        return GraveyardGhostPose(
            grave: grave,
            rise: rise,
            offset: CGVector(dx: 0, dy: -size.height * 0.05 * CGFloat(sin(time * 3))),
            tilt: 0.08 * sin(time * 2.3),
            facing: 1,
            arms: boo,
        )
    }

    private func partyScene(at time: TimeInterval, rest: TimeInterval, settled: Bool) -> GraveyardScene {
        let count = layout.graves.count
        let stagger = min(0.25, rest * 0.25 / Double(count))
        let lead = min(Self.sinkDuration * 1.5, rest * 0.15)
        let fade = min(Self.partyFade, rest / 2)
        let party = settled ? 1 : Self.smoothstep(min(time, rest - time) / max(0.001, fade))
        let ghosts = lineup.enumerated().compactMap { order, grave -> GraveyardGhostPose? in
            guard !settled else {
                return GraveyardGhostPose(grave: grave, rise: 1, offset: .zero, tilt: 0, facing: 1, arms: 0.6)
            }
            let local = time - stagger * Double(order)
            guard local > 0 else { return nil }
            let emerge = Self.backOut(local / Self.emergeDuration)
            let sink = 1 - Self.smoothstep((time - (rest - lead)) / max(0.001, lead))
            let rise = emerge * sink
            guard rise > 0 else { return nil }
            let phase = phases[grave]
            let size = layout.ghostSize(layout.graves[grave])
            let groove = Self.smoothstep((local - Self.emergeDuration) / 1.2) * sink
            let period = 5 + Double(grave % 3)
            let spin = (local + phase).truncatingRemainder(dividingBy: period)
            return GraveyardGhostPose(
                grave: grave,
                rise: rise,
                offset: CGVector(
                    dx: size.width * 0.35 * CGFloat(groove * sin(time * 1.7 + phase)),
                    dy: -size.height * CGFloat(groove * (0.22 + 0.12 * sin(time * 0.9 + phase) + 0.07 * sin(time * 4.2 + phase))),
                ),
                tilt: groove * 0.22 * sin(time * 3.4 + phase),
                facing: spin < 0.8 ? cos(2 * .pi * spin / 0.8) : 1,
                arms: 0.5 + 0.5 * sin(time * 6 + phase),
            )
        }
        return GraveyardScene(ghosts: ghosts, trembles: Array(repeating: 0, count: count), party: party, mood: .party)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * (3 - 2 * x)
    }

    private static func backOut(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0)) - 1
        return 1 + x * x * (2.7 * x + 1.7)
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

        mutating func unit() -> Double {
            Double(next() >> 11) / 9_007_199_254_740_992
        }
    }
}
