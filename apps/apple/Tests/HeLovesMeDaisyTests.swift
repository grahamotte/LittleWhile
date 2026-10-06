import CoreGraphics
import XCTest
@testable import App

final class HeLovesMeDaisyTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)
    private let size = CGSize(width: 390, height: 844)
    private let seed = UUID(uuidString: "6D2B79F5-0C1A-4E3B-9C8D-7A6F5E4D3C2B")!
    private let goal = 1_500

    private var daisy: HeLovesMeDaisy {
        HeLovesMeDaisy(key: HeLovesMeDaisy.Key(seed: seed, size: size, goalSeconds: goal))
    }

    private var interval: TimeInterval {
        TimeInterval(goal) / TimeInterval(HeLovesMeDaisy.petalCount)
    }

    func testLayoutPlacesTheHeadAboveAGentleMoundAndStartsPetalsAtTheTop() {
        let layout = HeLovesMeLayout(size: size)

        XCTAssertEqual(layout.headCenter, CGPoint(x: 195, y: 844 * 0.47))
        XCTAssertEqual(layout.centerRadius, 29.25, accuracy: 0.0001)
        XCTAssertEqual(layout.petalLength, layout.centerRadius * 2.6, accuracy: 0.0001)
        XCTAssertLessThan(layout.groundY(at: 195), layout.groundY(at: 20))
        XCTAssertEqual(layout.groundY(at: 195), layout.stemBase.y, accuracy: 0.0001)
        XCTAssertEqual(layout.groundY(at: 100), layout.groundY(at: 290), accuracy: 0.0001)
        XCTAssertEqual(HeLovesMeDaisy.slotAngle(0), -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(HeLovesMeDaisy.slotAngle(HeLovesMeDaisy.petalCount), 3 * .pi / 2, accuracy: 0.0001)
        let top = layout.slotCenter(head: layout.headCenter, angle: -.pi / 2)
        XCTAssertEqual(top.x, layout.headCenter.x, accuracy: 0.0001)
        XCTAssertEqual(top.y, layout.headCenter.y - layout.centerRadius * 0.55 - layout.petalLength / 2, accuracy: 0.0001)
    }

    func testLargeScreensCapTheFlowerSize() {
        XCTAssertEqual(HeLovesMeLayout(size: CGSize(width: 1_024, height: 1_366)).centerRadius, 44)
    }

    func testSwayRotatesTheHeadAroundTheStemBase() {
        let layout = HeLovesMeLayout(size: size)
        let tilted = layout.headCenter(sway: 0.1)
        let original = hypot(layout.headCenter.x - layout.stemBase.x, layout.headCenter.y - layout.stemBase.y)

        XCTAssertEqual(layout.headCenter(sway: 0), layout.headCenter)
        XCTAssertGreaterThan(tilted.x, layout.headCenter.x)
        XCTAssertEqual(hypot(tilted.x - layout.stemBase.x, tilted.y - layout.stemBase.y), original, accuracy: 0.0001)
    }

    func testReadyDaisyHasEveryPetalAndAsksTheQuestion() {
        let scene = daisy.scene(elapsed: 0, restSeconds: 300, settled: false)

        XCTAssertEqual(scene.petals.count, 21)
        XCTAssertTrue(scene.petals.allSatisfy(\.attached))
        XCTAssertEqual(scene.fallen, 0)
        XCTAssertFalse(scene.finished)
        XCTAssertEqual(scene.dusk, 0)
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: scene.fallen, finished: scene.finished), "does he love me?")
    }

    func testPetalsFallOneAtATimeAroundTheFlower() {
        let daisy = daisy

        XCTAssertEqual(daisy.scene(elapsed: 0.01, restSeconds: 0, settled: false).fallen, 1)
        XCTAssertFalse(daisy.scene(elapsed: 0.01, restSeconds: 0, settled: false).petals[0].attached)
        XCTAssertTrue(daisy.scene(elapsed: 0.01, restSeconds: 0, settled: false).petals[1].attached)
        XCTAssertEqual(daisy.scene(elapsed: interval, restSeconds: 0, settled: false).fallen, 1)
        XCTAssertEqual(daisy.scene(elapsed: interval + 0.01, restSeconds: 0, settled: false).fallen, 2)
        XCTAssertEqual(daisy.scene(elapsed: interval * 10.5, restSeconds: 0, settled: false).fallen, 11)
        XCTAssertEqual(daisy.scene(elapsed: TimeInterval(goal) - 0.01, restSeconds: 0, settled: false).fallen, 21)
    }

    func testCaptionAlternatesAndEndsWithLove() {
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 0, finished: false), "does he love me?")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 1, finished: false), "he loves me")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 2, finished: false), "he loves me not")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 20, finished: false), "he loves me not")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: HeLovesMeDaisy.petalCount, finished: false), "he loves me")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 4, finished: true), "he loves me")
        XCTAssertEqual(HeLovesMeDaisy.caption(fallen: 0, finished: true), "he loves me")
    }

    func testFallingPetalPopsAwayThenFloatsDownWhileSpinning() {
        let daisy = daisy
        let start = daisy.scene(elapsed: interval * 5, restSeconds: 0, settled: false).petals[5]
        let early = daisy.scene(elapsed: interval * 5 + 0.1, restSeconds: 0, settled: false).petals[5]
        let later = daisy.scene(elapsed: interval * 5 + 1.5, restSeconds: 0, settled: false).petals[5]

        XCTAssertTrue(start.attached)
        XCTAssertFalse(early.attached)
        XCTAssertLessThan(hypot(early.center.x - start.center.x, early.center.y - start.center.y), daisy.layout.petalLength * 0.5)
        XCTAssertGreaterThan(later.center.y, early.center.y + daisy.layout.petalLength)
        XCTAssertNotEqual(later.angle, early.angle, accuracy: 0.01)
    }

    func testDetachedPetalsSettleOnTheGroundIntoAPile() {
        let daisy = daisy
        let layout = daisy.layout
        let scene = daisy.scene(elapsed: TimeInterval(goal), restSeconds: 0, settled: false)
        var stacked = 0

        XCTAssertTrue(scene.finished)
        XCTAssertEqual(scene.fallen, 21)
        for pose in scene.petals {
            let ground = layout.groundY(at: pose.center.x)
            XCTAssertLessThan(pose.center.y, ground)
            XCTAssertGreaterThan(pose.center.y, layout.headCenter.y + layout.petalLength)
            XCTAssertGreaterThanOrEqual(pose.center.x, layout.petalLength / 2)
            XCTAssertLessThanOrEqual(pose.center.x, layout.size.width - layout.petalLength / 2)
            XCTAssertLessThan(abs(remainder(pose.angle, .pi)), 0.9)
            if ground - pose.center.y > layout.petalWidth * 0.4 {
                stacked += 1
            }
        }
        XCTAssertGreaterThan(stacked, 0)
    }

    func testLandingEasesIntoTheRestingPose() {
        let daisy = daisy
        var previous = daisy.scene(elapsed: 0.01, restSeconds: 0, settled: false).petals[0]
        var largestStep: CGFloat = 0
        var elapsed = 0.01
        while elapsed < 15 {
            elapsed += 1.0 / 60
            let pose = daisy.scene(elapsed: elapsed, restSeconds: 0, settled: false).petals[0]
            largestStep = max(largestStep, hypot(pose.center.x - previous.center.x, pose.center.y - previous.center.y))
            previous = pose
        }
        let settled = daisy.scene(elapsed: 15, restSeconds: 0, settled: true).petals[0]

        XCTAssertLessThan(largestStep, daisy.layout.petalLength * 0.15)
        XCTAssertEqual(previous, settled)
    }

    func testPetalTremblesJustBeforeItIsPlucked() {
        let daisy = daisy
        let calm = daisy.scene(elapsed: interval * 3 - 5, restSeconds: 0, settled: false)
        let nervous = daisy.scene(elapsed: interval * 3 - 0.05, restSeconds: 0, settled: false)
        let still = daisy.scene(elapsed: interval * 3 - 0.05, restSeconds: 0, settled: true)

        XCTAssertEqual(calm.petals[3].angle - calm.headAngle, HeLovesMeDaisy.slotAngle(3), accuracy: 0.0001)
        XCTAssertNotEqual(nervous.petals[3].angle - nervous.headAngle, HeLovesMeDaisy.slotAngle(3), accuracy: 0.001)
        XCTAssertEqual(nervous.petals[4].angle - nervous.headAngle, HeLovesMeDaisy.slotAngle(4), accuracy: 0.0001)
        XCTAssertEqual(still.petals[3].angle, HeLovesMeDaisy.slotAngle(3), accuracy: 0.0001)
        XCTAssertEqual(still.headAngle, 0)
    }

    func testPluckingMakesTheFlowerRecoil() {
        let daisy = daisy
        let before = daisy.scene(elapsed: interval * 6 - 0.001, restSeconds: 0, settled: false).headAngle
        let after = daisy.scene(elapsed: interval * 6 + 0.15, restSeconds: 0, settled: false).headAngle
        let calm = daisy.scene(elapsed: interval * 6 + 5, restSeconds: 0, settled: false).headAngle
        let ambient = 0.028 + 0.011

        XCTAssertGreaterThan(abs(after - before), 0.02)
        XCTAssertLessThanOrEqual(abs(calm), ambient + 0.001)
    }

    func testSameRunIsDeterministicAndDifferentRunsFallDifferently() {
        let other = HeLovesMeDaisy(key: HeLovesMeDaisy.Key(seed: UUID(), size: size, goalSeconds: goal))

        XCTAssertEqual(
            daisy.scene(elapsed: 900, restSeconds: 0, settled: false),
            daisy.scene(elapsed: 900, restSeconds: 0, settled: false),
        )
        XCTAssertNotEqual(
            daisy.scene(elapsed: 900, restSeconds: 0, settled: true).petals[0].center,
            other.scene(elapsed: 900, restSeconds: 0, settled: true).petals[0].center,
        )
    }

    func testReducedMotionShowsPetalsAlreadyRestingAndAStillFlower() {
        let daisy = daisy
        let scene = daisy.scene(elapsed: interval * 4 + 0.1, restSeconds: 0, settled: true)
        let resting = daisy.scene(elapsed: TimeInterval(goal), restSeconds: 0, settled: false)

        XCTAssertEqual(scene.fallen, 5)
        XCTAssertEqual(scene.headAngle, 0)
        XCTAssertEqual(scene.headCenter, daisy.layout.headCenter)
        XCTAssertEqual(scene.petals[4], resting.petals[4])
    }

    func testRestBeginsExactlyWhereFocusEnded() {
        let daisy = daisy
        let focus = daisy.scene(elapsed: TimeInterval(goal) - 0.000_001, restSeconds: 300, settled: false)
        let rest = daisy.scene(elapsed: TimeInterval(goal), restSeconds: 300, settled: false)

        XCTAssertTrue(rest.finished)
        XCTAssertEqual(rest.dusk, 0)
        XCTAssertEqual(rest.fallen, 21)
        XCTAssertEqual(rest.headAngle, focus.headAngle, accuracy: 0.0001)
        for (lhs, rhs) in zip(focus.petals, rest.petals) {
            XCTAssertEqual(lhs.center.x, rhs.center.x, accuracy: 0.01)
            XCTAssertEqual(lhs.center.y, rhs.center.y, accuracy: 0.01)
        }
    }

    func testPetalsFlyBackSmoothlyDuringRest() {
        let daisy = daisy
        var previous = daisy.scene(elapsed: TimeInterval(goal), restSeconds: 300, settled: false)
        var largestStep: CGFloat = 0
        var sawFlight = false
        var elapsed = TimeInterval(goal)
        while elapsed < TimeInterval(goal) + 8 {
            elapsed += 1.0 / 60
            let scene = daisy.scene(elapsed: elapsed, restSeconds: 300, settled: false)
            for (lhs, rhs) in zip(previous.petals, scene.petals) {
                largestStep = max(largestStep, hypot(lhs.center.x - rhs.center.x, lhs.center.y - rhs.center.y))
            }
            sawFlight = sawFlight || scene.petals.contains { !$0.attached } && scene.fallen < 21
            previous = scene
        }

        XCTAssertTrue(sawFlight)
        XCTAssertLessThan(largestStep, daisy.layout.petalLength * 0.4)
        XCTAssertTrue(previous.petals.allSatisfy(\.attached))
        XCTAssertEqual(previous.fallen, 0)
    }

    func testRestingDaisyTurnsBreathesAndGlowsAtDusk() {
        let daisy = daisy
        let layout = daisy.layout
        let early = daisy.scene(elapsed: TimeInterval(goal) + 20, restSeconds: 300, settled: false)
        let later = daisy.scene(elapsed: TimeInterval(goal) + 30, restSeconds: 300, settled: false)

        XCTAssertEqual(early.dusk, 1)
        XCTAssertGreaterThan(later.headAngle - early.headAngle, 1.5)
        XCTAssertTrue(early.petals.allSatisfy(\.attached))
        XCTAssertGreaterThan(Set(early.petals.map(\.scale)).count, 1)
        for (index, pose) in early.petals.enumerated() {
            let distance = hypot(pose.center.x - early.headCenter.x, pose.center.y - early.headCenter.y)
            XCTAssertEqual(distance, layout.centerRadius * 0.55 + layout.petalLength * pose.scale / 2, accuracy: 0.0001)
            XCTAssertEqual(pose.angle, HeLovesMeDaisy.slotAngle(index) + early.headAngle, accuracy: 0.0001)
            XCTAssertEqual(pose.scale, 1, accuracy: 0.0601)
        }
    }

    func testDuskFadesBackToDayAsRestEnds() {
        let daisy = daisy
        let end = daisy.scene(elapsed: TimeInterval(goal + 300), restSeconds: 300, settled: false)
        let settledEnd = daisy.scene(elapsed: TimeInterval(goal + 300), restSeconds: 300, settled: true)
        let settledMiddle = daisy.scene(elapsed: TimeInterval(goal) + 1, restSeconds: 300, settled: true)

        XCTAssertEqual(end.dusk, 0)
        XCTAssertTrue(end.petals.allSatisfy(\.attached))
        XCTAssertEqual(settledEnd.dusk, 0)
        XCTAssertEqual(settledMiddle.dusk, 1)
        XCTAssertTrue(settledMiddle.petals.allSatisfy(\.attached))
        XCTAssertEqual(settledMiddle.headAngle, 0)
    }

    func testOutOfRangeElapsedIsClamped() {
        let daisy = daisy

        XCTAssertEqual(daisy.scene(elapsed: -5, restSeconds: 0, settled: false), daisy.scene(elapsed: 0, restSeconds: 0, settled: false))
        XCTAssertEqual(daisy.scene(elapsed: .nan, restSeconds: 0, settled: false), daisy.scene(elapsed: 0, restSeconds: 0, settled: false))
        XCTAssertEqual(
            daisy.scene(elapsed: 99_999, restSeconds: 60, settled: false),
            daisy.scene(elapsed: TimeInterval(goal + 60), restSeconds: 60, settled: false),
        )
    }

    func testEmptyLayoutStaysFinite() {
        let empty = HeLovesMeDaisy(key: HeLovesMeDaisy.Key(seed: seed, size: .zero, goalSeconds: 60))
        let scene = empty.scene(elapsed: 30, restSeconds: 60, settled: false)

        XCTAssertTrue(scene.petals.allSatisfy { $0.center.x.isFinite && $0.center.y.isFinite && $0.angle.isFinite })
    }

    func testElapsedFollowsTheSnapshot() {
        let ready = TimerSnapshot(run: FocusRun(createdAt: date, goalSeconds: 60), at: date)
        let running = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date), at: date.addingTimeInterval(10))
        let paused = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 20, goalSeconds: 60), at: date)
        let looping = TimerSnapshot(
            run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 60, resumedAt: date, loops: true),
            at: date.addingTimeInterval(119.5),
        )

        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: ready, at: date.addingTimeInterval(500)), 0)
        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: running, at: date.addingTimeInterval(10.25)), 10.25, accuracy: 0.0001)
        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: running, at: date.addingTimeInterval(5)), 10, accuracy: 0.0001)
        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: running, at: date.addingTimeInterval(500)), 60)
        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: paused, at: date.addingTimeInterval(500)), 20)
        XCTAssertEqual(HeLovesMeDaisy.elapsed(snapshot: looping, at: date.addingTimeInterval(120.5)), 0.5, accuracy: 0.0001)
    }
}
