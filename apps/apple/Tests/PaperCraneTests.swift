import CoreGraphics
import XCTest
@testable import App

final class PaperCraneTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)
    private let size = CGSize(width: 390, height: 844)
    private let goal = 1_500

    private var crane: PaperCrane {
        PaperCrane(key: PaperCrane.Key(size: size, top: 230, goalSeconds: goal))
    }

    func testLayoutPlacesASquareStageBelowTheClock() {
        let layout = PaperCraneLayout(size: size, top: 230)

        XCTAssertEqual(layout.frame.width, 312, accuracy: 0.0001)
        XCTAssertEqual(layout.frame.height, layout.frame.width)
        XCTAssertEqual(layout.frame.midX, 195, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(layout.frame.minY, 230)
        XCTAssertLessThanOrEqual(layout.frame.maxY, 844 * 0.88)
        XCTAssertEqual(PaperCraneLayout(size: CGSize(width: 1_024, height: 1_366), top: 200).frame.width, 420)
        XCTAssertEqual(PaperCraneLayout(size: CGSize(width: CGFloat.nan, height: -5), top: 10).frame.width, 0)
    }

    func testSheetStartsAsAWhiteSquare() {
        let sheet = PaperCraneWorkshop.sheet()

        XCTAssertEqual(sheet.map { PaperCraneGeometry.area($0.points) }.reduce(0, +), 2, accuracy: 0.0001)
        XCTAssertTrue(sheet.allSatisfy { $0.visibleFace == .white })
    }

    func testEveryFoldKeepsAllOfThePaper() {
        XCTAssertEqual(PaperCrane.foldCount, 15)
        for fold in PaperCrane.folds {
            for progress in [0.0, 1.0] {
                let area = fold.pieces.map { PaperCraneGeometry.area($0.points(at: progress)) }.reduce(0, +)
                XCTAssertEqual(area, 2, accuracy: 0.0001)
            }
            for piece in fold.pieces {
                if case .rotate = piece.move {
                    XCTAssertEqual(PaperCraneGeometry.area(piece.points(at: 0.5)), PaperCraneGeometry.area(piece.facet.points), accuracy: 0.0001)
                }
            }
        }
        for (fold, next) in zip(PaperCrane.folds, PaperCrane.folds.dropFirst()) {
            let before = fold.end.flatMap(\.points)
            let after = next.start.flatMap(\.points)
            for axis in [\SIMD3<Double>.x, \SIMD3<Double>.y, \SIMD3<Double>.z] {
                XCTAssertEqual(before.map { $0[keyPath: axis] }.min() ?? 0, after.map { $0[keyPath: axis] }.min() ?? 1, accuracy: 0.0001)
                XCTAssertEqual(before.map { $0[keyPath: axis] }.max() ?? 0, after.map { $0[keyPath: axis] }.max() ?? 1, accuracy: 0.0001)
            }
            XCTAssertEqual(fold.endCamera, next.startCamera)
        }
    }

    func testFinishedCraneIsColoredAllOverAndStandsInThreeDimensions() {
        let crane = PaperCrane.folds[PaperCrane.foldCount - 1].end

        XCTAssertTrue(crane.allSatisfy { $0.front == .color && $0.back == .color })
        XCTAssertTrue(Set(crane.map(\.group)).isSuperset(of: ["w1", "w2", "neck", "tail"]))
        XCTAssertGreaterThan(crane.flatMap(\.points).map(\.z).max() ?? 0, 0.3)
        XCTAssertLessThan(crane.flatMap(\.points).map(\.z).min() ?? 0, -0.3)
        let neck = crane.filter { $0.group == "neck" }.flatMap(\.points)
        let tail = crane.filter { $0.group == "tail" }.flatMap(\.points)
        XCTAssertLessThan(neck.map(\.x).min() ?? 0, -0.3)
        XCTAssertGreaterThan(tail.map(\.x).max() ?? 0, 0.3)
        XCTAssertLessThan(tail.map(\.y).min() ?? 0, 0)
        XCTAssertNotEqual(PaperCrane.folds[PaperCrane.foldCount - 1].endCamera, .flat)
    }

    func testFoldsAreSpreadEvenlyAndTheLastFinishesAtTheGoal() {
        let crane = crane

        XCTAssertEqual(crane.interval, 100, accuracy: 0.0001)
        XCTAssertEqual(crane.duration, PaperCrane.longestFold)
        XCTAssertEqual(crane.start(0), 100 - PaperCrane.longestFold, accuracy: 0.0001)
        XCTAssertEqual(crane.start(PaperCrane.foldCount - 1) + crane.duration, 1_500, accuracy: 0.0001)
        XCTAssertEqual(PaperCrane(key: PaperCrane.Key(size: size, top: 230, goalSeconds: 60)).duration, 2.4, accuracy: 0.0001)
    }

    func testFitsFrameEachStageAndCapTheZoom() {
        let crane = crane

        XCTAssertEqual(crane.fits.count, PaperCrane.foldCount + 1)
        XCTAssertEqual(crane.fits[0].scale, 312 / (2 * PaperCraneWorkshop.r), accuracy: 0.001)
        XCTAssertTrue(crane.fits.allSatisfy { $0.scale <= crane.fits[0].scale * 1.3 + 0.0001 })
        XCTAssertTrue(crane.fits.allSatisfy { $0.center == CGPoint(x: crane.layout.frame.midX, y: crane.layout.frame.midY) })
        let halfway = crane.fits[0].mix(crane.fits[1], 0.5)
        XCTAssertEqual(halfway.scale, (crane.fits[0].scale + crane.fits[1].scale) / 2, accuracy: 0.0001)
    }

    func testReadySheetShowsTheFirstInstruction() {
        let scene = crane.scene(elapsed: 0, restSeconds: 300, settled: false)

        XCTAssertEqual(scene.polygons.count, 2)
        XCTAssertTrue(scene.polygons.allSatisfy { $0.face == .white && $0.shadow.isEmpty })
        XCTAssertTrue(scene.polygons.allSatisfy { abs($0.shade - 1) < 0.0001 })
        XCTAssertEqual(scene.folded, 0)
        XCTAssertFalse(scene.finished)
        XCTAssertEqual(scene.standing, 0)
        XCTAssertEqual(scene.ground, .zero)
        XCTAssertEqual(scene.opacity, 1)
        XCTAssertEqual(scene.hint?.opacity, 1)
        XCTAssertEqual(scene.hint?.creases.count, 1)
        XCTAssertEqual(scene.hint?.arrows.count, 1)
        XCTAssertNil(scene.hint?.turnOver)
        let points = scene.polygons.flatMap(\.points)
        XCTAssertEqual(points.map(\.x).min() ?? 0, crane.layout.frame.minX, accuracy: 0.5)
        XCTAssertEqual(points.map(\.x).max() ?? 0, crane.layout.frame.maxX, accuracy: 0.5)
    }

    func testFoldingLiftsThePaperThenLaysItFlat() {
        let crane = crane
        let start = crane.start(0)

        let lifting = crane.scene(elapsed: start + crane.duration / 2, restSeconds: 300, settled: false)
        XCTAssertEqual(lifting.folded, 0)
        XCTAssertTrue(lifting.polygons.contains { !$0.shadow.isEmpty && $0.lift > 0 })

        let folded = crane.scene(elapsed: start + crane.duration + 1, restSeconds: 300, settled: false)
        XCTAssertEqual(folded.folded, 1)
        XCTAssertEqual(folded.polygons.last?.face, .color)
        XCTAssertTrue(folded.polygons.allSatisfy(\.shadow.isEmpty))
    }

    func testReducedMotionJumpsStraightToEachFold() {
        let crane = crane

        XCTAssertEqual(crane.scene(elapsed: crane.start(0) + 0.01, restSeconds: 300, settled: true).folded, 1)
        XCTAssertEqual(crane.scene(elapsed: crane.start(6) + 0.01, restSeconds: 300, settled: true).folded, 7)
        XCTAssertTrue(crane.scene(elapsed: crane.start(6) + 0.01, restSeconds: 300, settled: true).polygons.allSatisfy(\.shadow.isEmpty))
    }

    func testInstructionsAppearBeforeEachFoldAndFadeAsItStarts() {
        let crane = crane
        let start = crane.start(3)

        XCTAssertNil(crane.scene(elapsed: start - 30, restSeconds: 300, settled: false).hint)
        XCTAssertEqual(crane.scene(elapsed: start - 1, restSeconds: 300, settled: false).hint?.opacity, 1)
        XCTAssertNotNil(crane.scene(elapsed: start - 1, restSeconds: 300, settled: false).hint?.turnOver)
        let fading = crane.scene(elapsed: start + crane.duration * 0.2, restSeconds: 300, settled: false).hint?.opacity ?? 0
        XCTAssertGreaterThan(fading, 0)
        XCTAssertLessThan(fading, 1)
        XCTAssertNil(crane.scene(elapsed: start + crane.duration * 0.5, restSeconds: 300, settled: false).hint)
        XCTAssertNil(crane.scene(elapsed: start + 0.1, restSeconds: 300, settled: true).hint)
    }

    func testFinishedCraneHoversOverItsShadow() {
        let crane = crane
        let landing = crane.scene(elapsed: 1_500, restSeconds: 300, settled: false)
        let later = crane.scene(elapsed: 1_502, restSeconds: 300, settled: false)

        XCTAssertTrue(landing.finished)
        XCTAssertEqual(landing.folded, PaperCrane.foldCount)
        XCTAssertNil(landing.hint)
        XCTAssertEqual(landing.standing, 1)
        XCTAssertGreaterThan(landing.ground.width, 0)
        XCTAssertGreaterThan(landing.ground.minY, landing.polygons.flatMap(\.points).map(\.y).max() ?? 0)
        XCTAssertNotEqual(landing.polygons, later.polygons)
        XCTAssertEqual(crane.scene(elapsed: 1_502, restSeconds: 300, settled: true).polygons, landing.polygons)
        XCTAssertEqual(crane.scene(elapsed: 1_500, restSeconds: 0, settled: false).folded, PaperCrane.foldCount)
        XCTAssertTrue(PaperCrane(key: PaperCrane.Key(size: size, top: 230, goalSeconds: 0)).scene(elapsed: 0, restSeconds: 0, settled: false).finished)
    }

    func testLoopingCraneFliesAwayAndTheNextSheetFadesIn() {
        let crane = crane

        XCTAssertEqual(crane.scene(elapsed: 1_799.99, restSeconds: 300, settled: false).opacity, 1)
        XCTAssertLessThan(crane.scene(elapsed: 1_799.99, restSeconds: 300, settled: false, looping: true).opacity, 0.01)
        XCTAssertEqual(crane.scene(elapsed: 1_600, restSeconds: 300, settled: false, looping: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 0, restSeconds: 300, settled: false, arriving: true).opacity, 0)
        XCTAssertEqual(crane.scene(elapsed: PaperCrane.arrival, restSeconds: 300, settled: false, arriving: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 0, restSeconds: 300, settled: true, arriving: true).opacity, 1)
    }

    func testAnimationOnlyRunsWhilePaperMoves() {
        let crane = crane

        XCTAssertTrue(crane.moving(at: 0.5))
        XCTAssertFalse(crane.moving(at: 40))
        XCTAssertTrue(crane.moving(at: crane.start(2) - 2))
        XCTAssertTrue(crane.moving(at: crane.start(2) + 1))
        XCTAssertFalse(crane.moving(at: crane.start(2) + crane.duration + 5))
        XCTAssertTrue(crane.moving(at: 1_499.5))
        XCTAssertTrue(crane.moving(at: 1_700))
    }

    func testCaptionCountsFoldsAndCranes() {
        XCTAssertEqual(PaperCrane.caption(folded: 0, finished: false, started: false, cranes: 1), "a square of paper")
        XCTAssertEqual(PaperCrane.caption(folded: 0, finished: false, started: true, cranes: 1), "fold 1 of 15")
        XCTAssertEqual(PaperCrane.caption(folded: 14, finished: false, started: true, cranes: 1), "fold 15 of 15")
        XCTAssertEqual(PaperCrane.caption(folded: 15, finished: false, started: true, cranes: 1), "fold 15 of 15")
        XCTAssertEqual(PaperCrane.caption(folded: 15, finished: true, started: true, cranes: 1), "one of a thousand")
        XCTAssertEqual(PaperCrane.caption(folded: 15, finished: true, started: true, cranes: 3), "3 of a thousand")
    }

    func testElapsedFollowsRunningPausedAndLoopingSnapshots() {
        let ready = TimerSnapshot(run: FocusRun(createdAt: date, goalSeconds: 60), at: date)
        let running = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date), at: date.addingTimeInterval(10))
        let paused = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 20, goalSeconds: 60), at: date)
        let looping = TimerSnapshot(
            run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 60, resumedAt: date, loops: true),
            at: date.addingTimeInterval(119.5),
        )

        XCTAssertEqual(PaperCrane.elapsed(snapshot: ready, at: date.addingTimeInterval(500)), 0)
        XCTAssertEqual(PaperCrane.elapsed(snapshot: running, at: date.addingTimeInterval(10.25)), 10.25, accuracy: 0.0001)
        XCTAssertEqual(PaperCrane.elapsed(snapshot: running, at: date.addingTimeInterval(5)), 10, accuracy: 0.0001)
        XCTAssertEqual(PaperCrane.elapsed(snapshot: running, at: date.addingTimeInterval(500)), 60)
        XCTAssertEqual(PaperCrane.elapsed(snapshot: paused, at: date.addingTimeInterval(500)), 20)
        XCTAssertEqual(PaperCrane.elapsed(snapshot: looping, at: date.addingTimeInterval(120.5)), 0.5, accuracy: 0.0001)
    }
}
