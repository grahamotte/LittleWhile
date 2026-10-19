import CoreGraphics
import XCTest
import simd
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

    func testSheetStartsAsAWhiteSquareDiamond() {
        let sheet = PaperCraneWorkshop.sheet()

        XCTAssertEqual(sheet.count, 1)
        XCTAssertEqual(PaperCraneGeometry.area(sheet[0].points), 2, accuracy: 0.0001)
        XCTAssertEqual(sheet[0].visibleFace, .inside)
        XCTAssertEqual(sheet[0].edges, [.edge, .edge, .edge, .edge])
    }

    func testRigidFoldsNeverStretchThePaperAndTheFinalShapingOnlyFlexesIt() {
        XCTAssertEqual(PaperCrane.foldCount, 17)
        for (number, fold) in PaperCrane.folds.enumerated() {
            let shaping = number == PaperCrane.foldCount - 1
            for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                let area = fold.pieces.indices.map { PaperCraneGeometry.area(fold.points($0, at: progress)) }.reduce(0, +)
                XCTAssertEqual(area, 2, accuracy: shaping ? 0.05 : 0.0001)
            }
            for index in fold.pieces.indices {
                let start = fold.pieces[index].facet.points
                let moved = fold.points(index, at: 0.5)
                for corner in start.indices {
                    let next = (corner + 1) % start.count
                    XCTAssertEqual(simd_distance(moved[corner], moved[next]), simd_distance(start[corner], start[next]), accuracy: shaping ? 0.07 : 0.0001)
                }
            }
            XCTAssertEqual(fold.pieces.contains { !$0.track.isEmpty }, shaping)
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

    func testRigidFoldsNeverTearThePaperBeyondHiddenMirrorSeparations() {
        var mirrored = 0
        for fold in PaperCrane.folds.dropLast() {
            for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
                let posed = fold.pieces.indices.map { fold.pieces[$0].facet.moved(by: fold.pose($0, at: progress)) }
                for first in posed.indices {
                    for second in posed.indices where second > first && PaperCraneWorkshop.near(posed[first].paper, posed[second].paper) {
                        for (start, end) in shared(posed[first], posed[second]) {
                            for point in [start, end] {
                                let a = posed[first].place(point)
                                let b = posed[second].place(point)
                                if abs(a.x - b.x) < 0.000_1, abs(a.y - b.y) < 0.000_1, abs(a.z + b.z) < 0.000_1, abs(a.z) > 0.001 {
                                    mirrored += 1
                                } else {
                                    XCTAssertLessThan(simd_distance(a, b), 0.005)
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(mirrored, 0)
    }

    func testFinalShapingKeepsEverySharedCornerJoined() throws {
        let fold = try XCTUnwrap(PaperCrane.folds.last)
        for progress in [0.3, 0.7, 1.0] {
            var corners: [SIMD2<Int64>: SIMD3<Double>] = [:]
            for index in fold.pieces.indices {
                let points = fold.points(index, at: progress)
                for (paper, point) in zip(fold.pieces[index].facet.paper, points) {
                    let key = SIMD2(Int64((paper.x * 1_000_000).rounded()), Int64((paper.y * 1_000_000).rounded()))
                    if let known = corners[key] {
                        XCTAssertLessThan(simd_distance(known, point), 0.000_001)
                    } else {
                        corners[key] = point
                    }
                }
            }
        }
    }

    func testVisibilityDrawsNearerPaperLastAndKeepsStacksInOrder() {
        let back = [SIMD3<Double>(0, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 1, -1), SIMD3(0, 1, -1)]
        let tilted = [SIMD3<Double>(0.2, 0.2, 0), SIMD3(1.2, 0.2, 0.2), SIMD3(1.2, 1.2, 0.2), SIMD3(0.2, 1.2, 0)]
        XCTAssertEqual(PaperCrane.order([tilted, back], stacks: [0, 0], fixed: [false, false]), [1, 0])

        let square = [SIMD3<Double>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)]
        XCTAssertEqual(PaperCrane.order([square, square, square], stacks: [0.3, 0.1, 0.2], fixed: [false, false, false]), [1, 2, 0])
        XCTAssertEqual(PaperCrane.order([square, back], stacks: [-5, 0], fixed: [true, false]), [0, 1])
        XCTAssertEqual(PaperCrane.order([square, square.map { $0 + SIMD3(5, 0, 0) }], stacks: [0.2, 0.1], fixed: [false, false]), [1, 0])
    }

    private func shared(_ first: PaperCraneFacet, _ second: PaperCraneFacet) -> [(SIMD2<Double>, SIMD2<Double>)] {
        var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
        for corner in first.paper.indices {
            let p = first.paper[corner]
            let q = first.paper[(corner + 1) % first.paper.count]
            let direction = simd_normalize(q - p)
            let length = simd_distance(p, q)
            for other in second.paper.indices {
                let r = second.paper[other]
                let s = second.paper[(other + 1) % second.paper.count]
                guard PaperCraneGeometry.overlaps(p, q, r, s) else { continue }
                let lower = max(0, min(simd_dot(r - p, direction), simd_dot(s - p, direction)))
                let upper = min(length, max(simd_dot(r - p, direction), simd_dot(s - p, direction)))
                segments.append((p + direction * lower, p + direction * upper))
            }
        }
        return segments
    }

    func testEachBaseShowsTheOutsideOfThePaper() {
        let crane = crane
        func front(_ elapsed: TimeInterval) -> PaperCraneFace? {
            crane.scene(elapsed: elapsed, restSeconds: 300, settled: true).polygons.last?.face
        }

        XCTAssertEqual(front(0), .inside)
        XCTAssertEqual(front(crane.start(0) + 0.1), .outside)
        XCTAssertEqual(front(crane.start(4) + 0.1), .outside)
        XCTAssertEqual(front(crane.start(9) + 0.1), .outside)
        let finished = crane.scene(elapsed: crane.span + 1, restSeconds: 300, settled: true).polygons
        let paths = finished.map { polygon in
            let path = CGMutablePath()
            path.addLines(between: polygon.points)
            path.closeSubpath()
            return path
        }
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        var outside = 0
        var visible = 0
        for row in 0..<40 {
            for column in 0..<40 {
                let point = CGPoint(x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / 40, y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / 40)
                guard let top = paths.indices.last(where: { paths[$0].contains(point) }) else { continue }
                visible += 1
                if finished[top].face == .outside {
                    outside += 1
                }
            }
        }
        XCTAssertGreaterThan(Double(outside) / Double(visible), 0.85)
    }

    func testFinishedCraneSpreadsItsWingsAroundARaisedNeckAndTail() {
        let crane = PaperCrane.folds[PaperCrane.foldCount - 1].end
        let groups = Set(crane.map(\.group))

        XCTAssertTrue(groups.isSuperset(of: ["w1", "w2", "neck", "tail"]))
        XCTAssertGreaterThan(crane.filter { $0.group == "w1" }.flatMap(\.points).map(\.z).max() ?? 0, 0.3)
        XCTAssertLessThan(crane.filter { $0.group == "w2" }.flatMap(\.points).map(\.z).min() ?? 0, -0.3)
        let neck = crane.filter { $0.group == "neck" }.flatMap(\.points)
        let tail = crane.filter { $0.group == "tail" }.flatMap(\.points)
        XCTAssertLessThan(neck.map(\.x).min() ?? 0, -0.25)
        XCTAssertLessThan(neck.map(\.y).min() ?? 0, 0)
        XCTAssertGreaterThan(tail.map(\.x).max() ?? 0, 0.25)
        XCTAssertLessThan(tail.map(\.y).min() ?? 0, 0)
        XCTAssertNotEqual(PaperCrane.folds[PaperCrane.foldCount - 1].endCamera, .flat)
    }

    func testEachMinuteFoldsOneCraneWithTimeLeftToAdmireIt() {
        let crane = crane

        XCTAssertEqual(crane.length, 60)
        XCTAssertEqual(crane.span, 50, accuracy: 0.0001)
        XCTAssertEqual(crane.interval, 49.0 / 17, accuracy: 0.0001)
        XCTAssertEqual(crane.duration, 49.0 / 17 * 0.72, accuracy: 0.0001)
        XCTAssertEqual(crane.start(0) + crane.duration, 1 + crane.interval, accuracy: 0.0001)
        XCTAssertEqual(crane.start(PaperCrane.foldCount - 1) + crane.duration, 50, accuracy: 0.0001)
        let short = PaperCrane(key: PaperCrane.Key(size: size, top: 230, goalSeconds: 30))
        XCTAssertEqual(short.length, 30)
        XCTAssertEqual(short.span, 25, accuracy: 0.0001)
        XCTAssertEqual(PaperCrane.segments(goalSeconds: 1_500), 25)
        XCTAssertEqual(PaperCrane.segments(goalSeconds: 90), 1)
        XCTAssertEqual(PaperCrane.segments(goalSeconds: 30), 1)
        XCTAssertEqual(PaperCrane.segments(goalSeconds: 0), 0)
    }

    func testCranesCountAsEachOneIsFinishedButNeverDuringRest() {
        XCTAssertEqual(PaperCrane.cranes(elapsed: 0, goalSeconds: 1_500), 0)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 49.9, goalSeconds: 1_500), 0)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 50, goalSeconds: 1_500), 1)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 109.9, goalSeconds: 1_500), 1)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 110, goalSeconds: 1_500), 2)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 1_500, goalSeconds: 1_500), 25)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 1_790, goalSeconds: 1_500), 25)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 50, goalSeconds: 1_500, cycle: 2), 51)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 25, goalSeconds: 30), 1)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 100, goalSeconds: 90), 1)
        XCTAssertEqual(PaperCrane.cranes(elapsed: .nan, goalSeconds: 1_500), 0)
        XCTAssertEqual(PaperCrane.cranes(elapsed: 500, goalSeconds: 0), 0)
    }

    func testFitsFrameEachStageAndCapTheZoom() {
        let crane = crane

        XCTAssertEqual(crane.fits.count, PaperCrane.foldCount + 1)
        XCTAssertEqual(crane.fits[0].scale, 312 / 2, accuracy: 0.001)
        XCTAssertTrue(crane.fits.allSatisfy { $0.scale <= crane.fits[0].scale * 1.3 + 0.0001 })
        XCTAssertTrue(crane.fits.allSatisfy { $0.center == CGPoint(x: crane.layout.frame.midX, y: crane.layout.frame.midY) })
        let halfway = crane.fits[0].mix(crane.fits[1], 0.5)
        XCTAssertEqual(halfway.scale, (crane.fits[0].scale + crane.fits[1].scale) / 2, accuracy: 0.0001)
    }

    func testReadySheetShowsTheFirstInstruction() {
        let scene = crane.scene(elapsed: 0, restSeconds: 300, settled: false)

        XCTAssertEqual(scene.polygons.count, 1)
        XCTAssertEqual(scene.polygons[0].face, .inside)
        XCTAssertTrue(scene.polygons[0].shadow.isEmpty)
        XCTAssertEqual(scene.polygons[0].shade, 1, accuracy: 0.0001)
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

        let folded = crane.scene(elapsed: start + crane.duration + 0.3, restSeconds: 300, settled: false)
        XCTAssertEqual(folded.folded, 1)
        XCTAssertEqual(folded.polygons.count, 2)
        XCTAssertTrue(folded.polygons.allSatisfy(\.shadow.isEmpty))
    }

    func testSquashFoldOpensThePocketToShowTheInside() {
        let crane = crane
        let squashing = crane.scene(elapsed: crane.start(2) + crane.duration * 0.55, restSeconds: 300, settled: false)

        XCTAssertTrue(squashing.polygons.contains { $0.face == .inside })
        XCTAssertTrue(squashing.polygons.contains { !$0.shadow.isEmpty })
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

        XCTAssertNil(crane.scene(elapsed: start - 1.8, restSeconds: 300, settled: false).hint)
        XCTAssertEqual(crane.scene(elapsed: start - 0.1, restSeconds: 300, settled: false).hint?.opacity, 1)
        XCTAssertNotNil(crane.scene(elapsed: start - 0.1, restSeconds: 300, settled: false).hint?.turnOver)
        let fading = crane.scene(elapsed: start + crane.duration * 0.2, restSeconds: 300, settled: false).hint?.opacity ?? 0
        XCTAssertGreaterThan(fading, 0)
        XCTAssertLessThan(fading, 1)
        XCTAssertNil(crane.scene(elapsed: start + crane.duration * 0.5, restSeconds: 300, settled: false).hint)
        XCTAssertNil(crane.scene(elapsed: start + 0.1, restSeconds: 300, settled: true).hint)
        XCTAssertEqual(crane.scene(elapsed: crane.start(5) - 0.1, restSeconds: 300, settled: false).hint?.creases.count, 2)
        XCTAssertEqual(crane.scene(elapsed: 60.1, restSeconds: 300, settled: false).hint?.creases.count, 1)
    }

    func testFinishedCraneHoversOverItsShadow() {
        let crane = crane
        let landing = crane.scene(elapsed: 50, restSeconds: 300, settled: false)
        let later = crane.scene(elapsed: 52, restSeconds: 300, settled: false)

        XCTAssertTrue(landing.finished)
        XCTAssertEqual(landing.folded, PaperCrane.foldCount)
        XCTAssertNil(landing.hint)
        XCTAssertEqual(landing.standing, 1)
        XCTAssertGreaterThan(landing.ground.width, 0)
        XCTAssertGreaterThan(landing.ground.minY, landing.polygons.flatMap(\.points).map(\.y).max() ?? 0)
        XCTAssertNotEqual(landing.polygons, later.polygons)
        XCTAssertEqual(crane.scene(elapsed: 52, restSeconds: 300, settled: true).polygons, landing.polygons)
        XCTAssertFalse(crane.scene(elapsed: 49.9, restSeconds: 300, settled: false).finished)
        XCTAssertTrue(crane.scene(elapsed: 1_600, restSeconds: 300, settled: false).finished)
        XCTAssertEqual(crane.scene(elapsed: 1_500, restSeconds: 300, settled: false).polygons, crane.scene(elapsed: 1_500, restSeconds: 0, settled: false).polygons)
        XCTAssertTrue(PaperCrane(key: PaperCrane.Key(size: size, top: 230, goalSeconds: 0)).scene(elapsed: 0, restSeconds: 0, settled: false).finished)
    }

    func testEachCraneFliesOffAsTheNextSheetArrives() {
        let crane = crane

        XCTAssertEqual(crane.scene(elapsed: 55, restSeconds: 300, settled: false).opacity, 1)
        XCTAssertLessThan(crane.scene(elapsed: 59.99, restSeconds: 300, settled: false).opacity, 0.01)
        XCTAssertEqual(crane.scene(elapsed: 59.99, restSeconds: 300, settled: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 60, restSeconds: 300, settled: false).opacity, 0)
        XCTAssertFalse(crane.scene(elapsed: 60, restSeconds: 300, settled: false).finished)
        XCTAssertEqual(crane.scene(elapsed: 60 + PaperCrane.arrival, restSeconds: 300, settled: false).opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(crane.scene(elapsed: 1_499.99, restSeconds: 300, settled: false).opacity, 1)
        XCTAssertLessThan(crane.scene(elapsed: 1_499.99, restSeconds: 0, settled: false, looping: true).opacity, 0.01)
    }

    func testLoopingCraneFliesAwayAfterRestAndTheNextSheetFadesIn() {
        let crane = crane

        XCTAssertEqual(crane.scene(elapsed: 1_799.99, restSeconds: 300, settled: false).opacity, 1)
        XCTAssertLessThan(crane.scene(elapsed: 1_799.99, restSeconds: 300, settled: false, looping: true).opacity, 0.01)
        XCTAssertEqual(crane.scene(elapsed: 1_600, restSeconds: 300, settled: false, looping: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 0, restSeconds: 300, settled: false, arriving: true).opacity, 0)
        XCTAssertEqual(crane.scene(elapsed: PaperCrane.arrival, restSeconds: 300, settled: false, arriving: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 0, restSeconds: 300, settled: true, arriving: true).opacity, 1)
        XCTAssertEqual(crane.scene(elapsed: 0, restSeconds: 300, settled: false).opacity, 1)
    }

    func testCaptionFollowsTheFolding() {
        XCTAssertEqual(PaperCrane.caption(folded: 0, finished: false, started: false), "a square of paper")
        XCTAssertEqual(PaperCrane.caption(folded: 0, finished: false, started: true), "fold 1 of 17")
        XCTAssertEqual(PaperCrane.caption(folded: 16, finished: false, started: true), "fold 17 of 17")
        XCTAssertEqual(PaperCrane.caption(folded: 17, finished: false, started: true), "fold 17 of 17")
        XCTAssertEqual(PaperCrane.caption(folded: 17, finished: true, started: true), "a paper crane")
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
