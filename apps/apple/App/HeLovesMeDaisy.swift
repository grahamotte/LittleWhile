import CoreGraphics
import Foundation

struct HeLovesMeLayout: Equatable {
    let size: CGSize
    let centerRadius: CGFloat
    let petalLength: CGFloat
    let petalWidth: CGFloat
    let groundLevel: CGFloat
    let moundHeight: CGFloat
    let stemBase: CGPoint
    let headCenter: CGPoint

    init(size: CGSize) {
        let width = max(0, size.width.isFinite ? size.width : 0)
        let height = max(0, size.height.isFinite ? size.height : 0)
        self.size = CGSize(width: width, height: height)
        centerRadius = max(1, min(44, min(width, height) * 0.075))
        petalLength = centerRadius * 2.6
        petalWidth = petalLength * 0.3
        groundLevel = height * 0.87
        moundHeight = height * 0.025
        stemBase = CGPoint(x: width / 2, y: groundLevel - moundHeight)
        headCenter = CGPoint(x: width / 2, y: height * 0.47)
    }

    func groundY(at x: CGFloat) -> CGFloat {
        let offset = (x - size.width / 2) / max(1, size.width * 0.45)
        return groundLevel - moundHeight * exp(-offset * offset)
    }

    func headCenter(sway: Double) -> CGPoint {
        let dx = headCenter.x - stemBase.x
        let dy = headCenter.y - stemBase.y
        return CGPoint(
            x: stemBase.x + dx * CGFloat(cos(sway)) - dy * CGFloat(sin(sway)),
            y: stemBase.y + dx * CGFloat(sin(sway)) + dy * CGFloat(cos(sway)),
        )
    }

    func slotCenter(head: CGPoint, angle: Double, scale: CGFloat = 1) -> CGPoint {
        let distance = centerRadius * 0.55 + petalLength * scale / 2
        return CGPoint(
            x: head.x + CGFloat(cos(angle)) * distance,
            y: head.y + CGFloat(sin(angle)) * distance,
        )
    }
}

struct HeLovesMePetalPose: Equatable {
    let center: CGPoint
    let angle: Double
    let scale: CGFloat
    let attached: Bool
}

struct HeLovesMeScene: Equatable {
    let headCenter: CGPoint
    let headAngle: Double
    let petals: [HeLovesMePetalPose]
    let fallen: Int
    let finished: Bool
    let dusk: Double
}

struct HeLovesMeDaisy {
    struct Key: Equatable {
        let seed: UUID
        let size: CGSize
        let goalSeconds: Int
    }

    static let petalCount = 21
    static let settleDuration: TimeInterval = 0.5
    static let trembleDuration: TimeInterval = 1.2
    static let duskFade: TimeInterval = 2.5

    let key: Key
    let layout: HeLovesMeLayout
    private let detachTimes: [TimeInterval]
    private let falls: [Fall]

    init(key: Key) {
        self.key = key
        let layout = HeLovesMeLayout(size: key.size)
        let goal = TimeInterval(max(0, key.goalSeconds))
        let detachTimes = (0..<Self.petalCount).map { goal * Double($0) / Double(Self.petalCount) }
        var random = Random(seed: key.seed)
        var pile = Pile(layout: layout)
        self.layout = layout
        self.detachTimes = detachTimes
        falls = detachTimes.indices.map { index in
            let sway = Self.sway(at: detachTimes[index], detachTimes: detachTimes)
            let angle = Self.slotAngle(index) + sway
            let unit = Double(layout.petalLength)
            return Fall(
                origin: layout.slotCenter(head: layout.headCenter(sway: sway), angle: angle),
                angle: angle,
                launch: CGVector(
                    dx: cos(angle) * unit * (0.8 + random.unit() * 0.8),
                    dy: sin(angle) * unit * 0.5 - unit * (0.4 + random.unit() * 0.5),
                ),
                terminalSpeed: CGFloat(unit * (1.3 + random.unit() * 0.5)),
                drift: CGFloat(unit * (random.unit() - 0.5) * 0.7),
                swayAmplitude: CGFloat(unit * (0.3 + random.unit() * 0.35)),
                swayFrequency: 2 + random.unit() * 1.4,
                swayPhase: random.unit() * 2 * .pi,
                spin: (random.unit() < 0.5 ? -1 : 1) * (0.4 + random.unit() * 1.1),
                restJitter: (random.unit() - 0.5) * 0.45,
                layout: layout,
                pile: &pile,
            )
        }
    }

    static func slotAngle(_ index: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(index) / Double(petalCount)
    }

    static func caption(fallen: Int, finished: Bool) -> String {
        if finished {
            return "he loves me"
        }
        if fallen <= 0 {
            return "does he love me?"
        }
        return fallen.isMultiple(of: 2) ? "he loves me not" : "he loves me"
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

    func scene(elapsed rawElapsed: TimeInterval, restSeconds: Int, settled: Bool) -> HeLovesMeScene {
        let goal = TimeInterval(max(0, key.goalSeconds))
        let rest = TimeInterval(max(0, restSeconds))
        let elapsed = min(goal + rest, max(0, rawElapsed.isFinite ? rawElapsed : 0))
        if rest > 0 && elapsed >= goal {
            return restScene(elapsed: elapsed, goal: goal, rest: rest, settled: settled)
        }
        let sway = settled ? 0 : Self.sway(at: elapsed, detachTimes: detachTimes)
        let petals = detachTimes.indices.map { focusPose($0, at: elapsed, settled: settled) }
        return HeLovesMeScene(
            headCenter: layout.headCenter(sway: sway),
            headAngle: sway,
            petals: petals,
            fallen: petals.filter { !$0.attached }.count,
            finished: elapsed >= goal,
            dusk: 0,
        )
    }

    private func restScene(elapsed: TimeInterval, goal: TimeInterval, rest: TimeInterval, settled: Bool) -> HeLovesMeScene {
        let restElapsed = elapsed - goal
        let sway = settled ? 0 : Self.sway(at: elapsed, detachTimes: detachTimes)
        let spin = settled ? 0 : 0.21 * (restElapsed - 2 * (1 - exp(-restElapsed / 2)))
        let headAngle = sway + spin
        let head = layout.headCenter(sway: sway)
        let gap = min(0.2, rest * 0.3 / Double(Self.petalCount))
        let flight = max(0.001, min(1.6, rest * 0.35))
        let petals = detachTimes.indices.map { index -> HeLovesMePetalPose in
            let angle = Self.slotAngle(index) + headAngle
            let departAt = gap * Double(index)
            let time = restElapsed - departAt
            let swell = min(1, max(0, (time - flight) / 1.5))
            let scale = settled ? 1 : 1 + CGFloat(0.06 * swell * sin(restElapsed * 1.7 - Double(index) * 4 * .pi / Double(Self.petalCount)))
            let slot = HeLovesMePetalPose(
                center: layout.slotCenter(head: head, angle: angle, scale: scale),
                angle: angle,
                scale: scale,
                attached: true,
            )
            if settled || time >= flight {
                return slot
            }
            let start = focusPose(index, at: goal + min(restElapsed, departAt), settled: false)
            guard time > 0 else { return start }
            let progress = Self.smoothstep(time / flight)
            let outward = CGPoint(
                x: slot.center.x + CGFloat(cos(angle)) * layout.petalLength * 2.2,
                y: slot.center.y + CGFloat(sin(angle)) * layout.petalLength * 2.2 - layout.petalLength * 0.6,
            )
            let twirl = remainder(angle - start.angle, 2 * .pi) + (index.isMultiple(of: 2) ? 2 : -2) * .pi
            return HeLovesMePetalPose(
                center: Self.bezier(start.center, outward, slot.center, progress),
                angle: start.angle + twirl * progress,
                scale: start.scale + (slot.scale - start.scale) * CGFloat(progress),
                attached: false,
            )
        }
        let dusk = settled ? (restElapsed < rest ? 1 : 0) : Self.smoothstep(min(restElapsed, rest - restElapsed) / Self.duskFade)
        return HeLovesMeScene(
            headCenter: head,
            headAngle: headAngle,
            petals: petals,
            fallen: petals.filter { !$0.attached }.count,
            finished: true,
            dusk: dusk,
        )
    }

    private func focusPose(_ index: Int, at elapsed: TimeInterval, settled: Bool) -> HeLovesMePetalPose {
        let detachAt = detachTimes[index]
        guard elapsed > detachAt else {
            let sway = settled ? 0 : Self.sway(at: elapsed, detachTimes: detachTimes)
            var angle = Self.slotAngle(index) + sway
            if !settled {
                let ramp = max(0, 1 - (detachAt - elapsed) / Self.trembleDuration)
                angle += 0.07 * ramp * ramp * sin(elapsed * 31)
            }
            return HeLovesMePetalPose(
                center: layout.slotCenter(head: layout.headCenter(sway: sway), angle: angle),
                angle: angle,
                scale: 1,
                attached: true,
            )
        }
        let fall = falls[index]
        let time = elapsed - detachAt
        if settled || time >= fall.landedAfter + Self.settleDuration {
            return HeLovesMePetalPose(center: fall.restCenter, angle: fall.restAngle, scale: 1, attached: false)
        }
        if time >= fall.landedAfter {
            let progress = Self.smoothstep((time - fall.landedAfter) / Self.settleDuration)
            let landing = fall.position(after: fall.landedAfter)
            let landingAngle = fall.angle(after: fall.landedAfter)
            return HeLovesMePetalPose(
                center: CGPoint(
                    x: landing.x + (fall.restCenter.x - landing.x) * CGFloat(progress),
                    y: landing.y + (fall.restCenter.y - landing.y) * CGFloat(progress),
                ),
                angle: landingAngle + (fall.restAngle - landingAngle) * progress,
                scale: 1,
                attached: false,
            )
        }
        return HeLovesMePetalPose(center: fall.position(after: time), angle: fall.angle(after: time), scale: 1, attached: false)
    }

    private static func sway(at elapsed: TimeInterval, detachTimes: [TimeInterval]) -> Double {
        var angle = 0.028 * sin(elapsed * 0.83) + 0.011 * sin(elapsed * 2.17 + 1.3)
        if let index = detachTimes.lastIndex(where: { $0 < elapsed }) {
            let since = elapsed - detachTimes[index]
            let side: Double = cos(slotAngle(index)) > 0.01 ? -1 : 1
            angle += 0.05 * side * exp(-since / 0.5) * sin(since * 10)
        }
        return angle
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(1, max(0, value.isFinite ? value : 0))
        return x * x * (3 - 2 * x)
    }

    private static func bezier(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, _ progress: Double) -> CGPoint {
        let t = CGFloat(progress)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
            y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y,
        )
    }

    private struct Fall {
        static let drag: TimeInterval = 0.45
        static let longestFall: TimeInterval = 12

        let origin: CGPoint
        let initialAngle: Double
        let launch: CGVector
        let terminalSpeed: CGFloat
        let drift: CGFloat
        let swayAmplitude: CGFloat
        let swayFrequency: Double
        let swayPhase: Double
        let spin: Double
        private(set) var landedAfter: TimeInterval = 0
        private(set) var restCenter: CGPoint = .zero
        private(set) var restAngle: Double = 0

        init(
            origin: CGPoint,
            angle: Double,
            launch: CGVector,
            terminalSpeed: CGFloat,
            drift: CGFloat,
            swayAmplitude: CGFloat,
            swayFrequency: Double,
            swayPhase: Double,
            spin: Double,
            restJitter: Double,
            layout: HeLovesMeLayout,
            pile: inout Pile,
        ) {
            self.origin = origin
            initialAngle = angle
            self.launch = launch
            self.terminalSpeed = terminalSpeed
            self.drift = drift
            self.swayAmplitude = swayAmplitude
            self.swayFrequency = swayFrequency
            self.swayPhase = swayPhase
            self.spin = spin

            let thickness = layout.petalWidth * 0.18
            func surface(_ x: CGFloat) -> CGFloat {
                layout.groundY(at: x) - pile.height(at: x) - thickness
            }
            let step: TimeInterval = 1.0 / 30
            var landed = Self.longestFall
            var time = step
            while time <= Self.longestFall {
                let point = position(after: time)
                if point.y >= surface(point.x) {
                    var lower = time - step
                    var upper = time
                    for _ in 0..<16 {
                        let middle = (lower + upper) / 2
                        let probe = position(after: middle)
                        if probe.y >= surface(probe.x) {
                            upper = middle
                        } else {
                            lower = middle
                        }
                    }
                    landed = upper
                    break
                }
                time += step
            }
            landedAfter = landed

            let width = layout.size.width
            let half = layout.petalLength / 2
            let minimumX = min(half, width / 2)
            let maximumX = max(width - half, width / 2)
            let slideStep = max(0.5, layout.petalWidth * 0.5)
            var x = min(maximumX, max(minimumX, position(after: landed).x))
            for _ in 0..<40 {
                let here = surface(x)
                let left = surface(max(minimumX, x - slideStep))
                let right = surface(min(maximumX, x + slideStep))
                let threshold = slideStep * 0.55
                if left - here > threshold && left >= right {
                    x = max(minimumX, x - slideStep)
                } else if right - here > threshold {
                    x = min(maximumX, x + slideStep)
                } else {
                    break
                }
            }
            let slope = atan2(Double(surface(x + half) - surface(x - half)), Double(max(1, half * 2)))
            let landingAngle = self.angle(after: landed)
            restCenter = CGPoint(x: x, y: surface(x))
            restAngle = (landingAngle / .pi).rounded() * .pi + slope + restJitter
            pile.add(at: x, peak: layout.petalWidth * 0.4, radius: half)
        }

        func position(after time: TimeInterval) -> CGPoint {
            let t = max(0, time)
            let decay = CGFloat(Self.drag * (1 - exp(-t / Self.drag)))
            let sway = CGFloat(sin(swayFrequency * t + swayPhase) - sin(swayPhase))
            return CGPoint(
                x: origin.x + launch.dx * decay + drift * CGFloat(t) + swayAmplitude * sway,
                y: origin.y + terminalSpeed * CGFloat(t) - (terminalSpeed - launch.dy) * decay,
            )
        }

        func angle(after time: TimeInterval) -> Double {
            let t = max(0, time)
            return initialAngle + spin * t + 0.45 * (cos(swayFrequency * t + swayPhase) - cos(swayPhase))
        }
    }

    private struct Pile {
        let binWidth: CGFloat
        var heights: [CGFloat]

        init(layout: HeLovesMeLayout) {
            binWidth = max(1, layout.size.width / 96)
            heights = Array(repeating: 0, count: 97)
        }

        func height(at x: CGFloat) -> CGFloat {
            let position = min(CGFloat(heights.count - 1), max(0, x.isFinite ? x / binWidth : 0))
            let lower = Int(position.rounded(.down))
            let upper = min(heights.count - 1, lower + 1)
            let fraction = position - CGFloat(lower)
            return heights[lower] * (1 - fraction) + heights[upper] * fraction
        }

        mutating func add(at x: CGFloat, peak: CGFloat, radius: CGFloat) {
            guard radius > 0 else { return }
            for index in heights.indices {
                let distance = abs(CGFloat(index) * binWidth - x)
                if distance < radius {
                    heights[index] += peak * (1 - distance / radius)
                }
            }
        }
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
