import CoreGraphics
import XCTest
@testable import LittleWhileCore

final class GraveyardTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)
    private let size = CGSize(width: 390, height: 844)
    private let seed = UUID(uuidString: "6D2B79F5-0C1A-4E3B-9C8D-7A6F5E4D3C2B")!
    private let goal = 1_500

    private var graveyard: Graveyard {
        Graveyard(key: Graveyard.Key(seed: seed, size: size, goalSeconds: goal))
    }

    func testLayoutPlacesNineGravesInRowsThatGrowTowardTheViewer() {
        let layout = GraveyardLayout(size: size)

        XCTAssertEqual(layout.graves.count, 9)
        XCTAssertEqual(layout.graves.map(\.row), [0, 0, 0, 0, 1, 1, 1, 2, 2])
        XCTAssertEqual(layout.stoneWidth, 78, accuracy: 0.0001)
        XCTAssertEqual(layout.horizon, 844 * 0.62, accuracy: 0.0001)
        for (back, front) in zip(layout.graves, layout.graves.dropFirst()) where back.row < front.row {
            XCTAssertLessThan(back.ground.y, front.ground.y)
            XCTAssertLessThan(back.scale, front.scale)
        }
        for grave in layout.graves {
            XCTAssertGreaterThan(grave.ground.x, 0)
            XCTAssertLessThan(grave.ground.x, size.width)
            XCTAssertGreaterThan(grave.ground.y, layout.horizon)
            XCTAssertLessThan(grave.ground.y, size.height)
        }
        XCTAssertEqual(Set(layout.graves.map(\.style)).count, GraveyardGrave.Style.allCases.count)
    }

    func testStonesAndGhostsScaleWithTheirRowAndGhostsEmergeInFrontOfTheStone() {
        let layout = GraveyardLayout(size: size)
        let front = layout.graves[8]
        let back = layout.graves[0]

        XCTAssertEqual(layout.stoneSize(front), CGSize(width: 78, height: 78 * 1.3))
        XCTAssertEqual(layout.stoneSize(back).width, 78 * 0.6, accuracy: 0.0001)
        XCTAssertEqual(layout.ghostSize(front).height, 78 * 1.2, accuracy: 0.0001)
        XCTAssertEqual(layout.emergence(front).x, front.ground.x)
        XCTAssertGreaterThan(layout.emergence(front).y, front.ground.y)
    }

    func testLargeScreensCapTheStoneSizeAndHillsStayAboveTheHorizon() {
        let layout = GraveyardLayout(size: CGSize(width: 1_024, height: 1_366))

        XCTAssertEqual(layout.stoneWidth, 84)
        XCTAssertEqual(layout.moonRadius, 70)
        for step in 0...20 {
            XCTAssertLessThan(layout.hillY(at: 1_024 * CGFloat(step) / 20), layout.horizon)
        }
    }

    func testDegenerateSizesStillProduceAUsableLayout() {
        let layout = GraveyardLayout(size: CGSize(width: CGFloat.nan, height: -10))

        XCTAssertEqual(layout.size, .zero)
        XCTAssertEqual(layout.stoneWidth, 1)
        XCTAssertEqual(layout.graves.count, 9)
    }

    func testOneGhostVisitsAtARandomMomentInEveryMinuteOfFocus() {
        let visits = graveyard.visits

        XCTAssertEqual(visits.count, 25)
        XCTAssertTrue(visits.allSatisfy { (0..<9).contains($0.grave) })
        for (minute, visit) in visits.enumerated() {
            XCTAssertGreaterThanOrEqual(visit.start, Double(minute) * 60 + Graveyard.hauntMargin)
            XCTAssertLessThanOrEqual(visit.start + Graveyard.hauntDuration, Double(minute + 1) * 60 - 1)
        }
        for (previous, next) in zip(visits, visits.dropFirst()) {
            XCTAssertNotEqual(previous.grave, next.grave)
        }
        XCTAssertGreaterThan(Set(visits.map(\.grave)).count, 5)
        XCTAssertGreaterThan(Set(visits.map { Int($0.start.truncatingRemainder(dividingBy: 60)) }).count, 8)
        XCTAssertEqual(visits, graveyard.visits)
        XCTAssertNotEqual(visits, Graveyard(key: Graveyard.Key(seed: UUID(), size: size, goalSeconds: goal)).visits)
    }

    func testShortAndUnevenGoalsScheduleOnlyTheGhostsThatFit() {
        let minute = Graveyard(key: Graveyard.Key(seed: seed, size: size, goalSeconds: 60)).visits
        XCTAssertEqual(minute.count, 1)
        XCTAssertGreaterThanOrEqual(minute[0].start, 5)
        XCTAssertLessThanOrEqual(minute[0].start, 54)

        let uneven = Graveyard(key: Graveyard.Key(seed: seed, size: size, goalSeconds: 90)).visits
        XCTAssertEqual(uneven.count, 2)
        XCTAssertLessThanOrEqual(uneven[1].start + Graveyard.hauntDuration, 89)

        XCTAssertEqual(Graveyard(key: Graveyard.Key(seed: seed, size: size, goalSeconds: 10)).visits.count, 0)
        XCTAssertEqual(Graveyard(key: Graveyard.Key(seed: seed, size: size, goalSeconds: 0)).visits.count, 0)
    }

    func testGraveyardIsQuietBetweenHauntings() {
        let graveyard = graveyard
        let first = graveyard.visits[0].start

        for elapsed in [0, 4.9, first - 0.1, first + 5.1, 59.9] {
            let scene = graveyard.scene(elapsed: elapsed, restSeconds: 300, settled: false)
            XCTAssertTrue(scene.ghosts.isEmpty, "\(elapsed)")
            XCTAssertEqual(scene.mood, .quiet)
            XCTAssertEqual(scene.party, 0)
        }
    }

    func testAGhostPopsUpForFiveSecondsAndSinksBackIn() {
        let graveyard = graveyard
        let visit = graveyard.visits[0]

        let rising = graveyard.scene(elapsed: visit.start + 0.3, restSeconds: 300, settled: false)
        XCTAssertEqual(rising.ghosts.map(\.grave), [visit.grave])
        XCTAssertEqual(rising.ghosts[0].age, 0.3, accuracy: 0.0001)
        XCTAssertEqual(rising.mood, .haunting)
        XCTAssertGreaterThan(rising.ghosts[0].rise, 0)
        XCTAssertLessThan(rising.ghosts[0].rise, 1.2)

        XCTAssertEqual(graveyard.scene(elapsed: visit.start + 2.5, restSeconds: 300, settled: false).ghosts[0].rise, 1)
        XCTAssertEqual(graveyard.scene(elapsed: visit.start + 1.5, restSeconds: 300, settled: false).ghosts[0].arms, 1, accuracy: 0.0001)

        let sinking = graveyard.scene(elapsed: visit.start + 4.6, restSeconds: 300, settled: false)
        XCTAssertLessThan(sinking.ghosts[0].rise, 0.5)
        XCTAssertGreaterThan(sinking.ghosts[0].rise, 0)

        for later in [graveyard.visits[1], graveyard.visits[24]] {
            XCTAssertEqual(graveyard.scene(elapsed: later.start + 1, restSeconds: 300, settled: false).ghosts.map(\.grave), [later.grave])
        }
    }

    func testTheGraveTremblesJustBeforeItsGhostAppears() {
        let graveyard = graveyard
        let visit = graveyard.visits[0]

        XCTAssertTrue(graveyard.scene(elapsed: visit.start - 2, restSeconds: 300, settled: false).trembles.allSatisfy { $0 == 0 })
        let scene = graveyard.scene(elapsed: visit.start - 0.45, restSeconds: 300, settled: false)
        XCTAssertNotEqual(scene.trembles[visit.grave], 0)
        XCTAssertEqual(scene.trembles.filter { $0 != 0 }.count, 1)
        XCTAssertTrue(graveyard.scene(elapsed: visit.start - 0.45, restSeconds: 300, settled: true).trembles.allSatisfy { $0 == 0 })
    }

    func testReducedMotionShowsTheVisitingGhostStill() {
        let ghost = graveyard.scene(elapsed: graveyard.visits[0].start + 0.1, restSeconds: 300, settled: true).ghosts[0]

        XCTAssertEqual(ghost.rise, 1)
        XCTAssertEqual(ghost.offset, .zero)
        XCTAssertEqual(ghost.tilt, 0)
        XCTAssertEqual(ghost.facing, 1)
    }

    func testEveryGhostComesOutToPartyDuringRest() {
        let graveyard = graveyard
        let start = TimeInterval(goal)

        let arriving = graveyard.scene(elapsed: start + 0.3, restSeconds: 300, settled: false)
        XCTAssertEqual(arriving.mood, .party)
        XCTAssertGreaterThan(arriving.ghosts.count, 0)
        XCTAssertLessThan(arriving.ghosts.count, 9)

        let party = graveyard.scene(elapsed: start + 60, restSeconds: 300, settled: false)
        XCTAssertEqual(Set(party.ghosts.map(\.grave)), Set(0..<9))
        XCTAssertEqual(party.party, 1)
        XCTAssertTrue(party.ghosts.allSatisfy { $0.rise > 0.99 })
        XCTAssertTrue(party.ghosts.allSatisfy { $0.offset.dy < 0 })
        XCTAssertGreaterThan(Set(party.ghosts.map(\.offset.dx)).count, 1)
        XCTAssertTrue(party.trembles.allSatisfy { $0 == 0 })
    }

    func testPartyGhostsSinkBackAtTheEndOfRestAndTheGraveyardRestsInPeace() {
        let graveyard = graveyard
        let end = TimeInterval(goal + 300)

        let winding = graveyard.scene(elapsed: end - 0.5, restSeconds: 300, settled: false)
        XCTAssertEqual(winding.mood, .party)
        XCTAssertTrue(winding.ghosts.allSatisfy { $0.rise < 1 })
        XCTAssertLessThan(winding.party, 1)

        let done = graveyard.scene(elapsed: end, restSeconds: 300, settled: false)
        XCTAssertTrue(done.ghosts.isEmpty)
        XCTAssertEqual(done.mood, .peace)
        XCTAssertEqual(done.party, 0)
        XCTAssertEqual(graveyard.scene(elapsed: end + 100, restSeconds: 300, settled: false), done)
    }

    func testReducedMotionPartyHasEveryGhostOutAndStill() {
        let scene = graveyard.scene(elapsed: TimeInterval(goal) + 0.1, restSeconds: 300, settled: true)

        XCTAssertEqual(scene.ghosts.count, 9)
        XCTAssertEqual(scene.party, 1)
        XCTAssertTrue(scene.ghosts.allSatisfy { $0.rise == 1 && $0.offset == .zero })
    }

    func testFinishingWithoutRestLeavesEveryGhostOut() {
        let scene = graveyard.scene(elapsed: TimeInterval(goal), restSeconds: 0, settled: false)

        XCTAssertEqual(scene.ghosts.count, 9)
        XCTAssertEqual(scene.mood, .party)
    }

    func testInvalidElapsedTimesAreClamped() {
        XCTAssertEqual(graveyard.scene(elapsed: .nan, restSeconds: 300, settled: false).mood, .quiet)
        XCTAssertEqual(graveyard.scene(elapsed: -50, restSeconds: 300, settled: false).mood, .quiet)
        XCTAssertEqual(graveyard.scene(elapsed: .infinity, restSeconds: 300, settled: false).mood, .quiet)
    }

    func testCaptionsFollowTheMood() {
        XCTAssertEqual(Graveyard.caption(mood: .quiet), "all is quiet")
        XCTAssertEqual(Graveyard.caption(mood: .haunting), "boo!")
        XCTAssertEqual(Graveyard.caption(mood: .party), "ghost party!")
        XCTAssertEqual(Graveyard.caption(mood: .peace), "rest in peace")
    }

    func testElapsedFollowsTheSnapshot() {
        let ready = TimerSnapshot(run: FocusRun(createdAt: date, goalSeconds: 60), at: date)
        let running = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date), at: date.addingTimeInterval(10))
        let paused = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 20, goalSeconds: 60), at: date)
        let looping = TimerSnapshot(
            run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 60, resumedAt: date, loops: true),
            at: date.addingTimeInterval(119.5),
        )

        XCTAssertEqual(Graveyard.elapsed(snapshot: ready, at: date.addingTimeInterval(500)), 0)
        XCTAssertEqual(Graveyard.elapsed(snapshot: running, at: date.addingTimeInterval(10.25)), 10.25, accuracy: 0.0001)
        XCTAssertEqual(Graveyard.elapsed(snapshot: running, at: date.addingTimeInterval(5)), 10, accuracy: 0.0001)
        XCTAssertEqual(Graveyard.elapsed(snapshot: running, at: date.addingTimeInterval(500)), 60)
        XCTAssertEqual(Graveyard.elapsed(snapshot: paused, at: date.addingTimeInterval(500)), 20)
        XCTAssertEqual(Graveyard.elapsed(snapshot: looping, at: date.addingTimeInterval(120.5)), 0.5, accuracy: 0.0001)
    }
}
