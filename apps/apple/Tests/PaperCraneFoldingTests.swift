import XCTest
import simd
@testable import App

final class PaperCraneFoldingTests: XCTestCase {
    private func assertPoint(_ point: SIMD3<Double>, _ expected: SIMD3<Double>, accuracy: Double = 0.0001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.z, expected.z, accuracy: accuracy, file: file, line: line)
    }

    private func facet(_ corners: [SIMD2<Double>], layer: Double = 0, group: String = "sheet") -> PaperCraneFacet {
        PaperCraneFacet(
            group: group,
            paper: corners,
            points: corners.map { SIMD3($0.x, $0.y, 0) },
            layer: layer,
            edges: Array(repeating: .edge, count: corners.count),
        )
    }

    private let square = [SIMD2<Double>(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]

    func testPosesTurnCarryChainAndBlend() {
        let quarter = PaperCranePose.turn(around: SIMD3(1, 0, 0), axis: SIMD3(0, 0, 1), angle: .pi / 2)
        assertPoint(quarter.apply(SIMD3(2, 0, 0)), SIMD3(1, 1, 0))
        assertPoint(quarter.apply(SIMD3(1, 0, 0)), SIMD3(1, 0, 0))

        let carried = PaperCranePose.carry((SIMD3(1, 0, 0), SIMD3(0, 1, 0)), to: (SIMD3(0, 1, 0), SIMD3(-1, 0, 0)), around: SIMD3(0, 0, 0))
        assertPoint(carried.apply(SIMD3(1, 0, 0)), SIMD3(0, 1, 0))
        assertPoint(carried.apply(SIMD3(0, 0, 1)), SIMD3(0, 0, 1))

        let chained = quarter.then(quarter)
        assertPoint(chained.apply(SIMD3(2, 0, 0)), SIMD3(0, 0, 0))
        let halfway = PaperCranePose.identity.mix(quarter, 0.5)
        XCTAssertEqual(halfway.rotation.angle, .pi / 4, accuracy: 0.0001)
        assertPoint(halfway.translation, quarter.translation * 0.5)
        XCTAssertEqual(PaperCranePose.identity.mix(quarter, 1), quarter)
        assertPoint(PaperCranePose.identity.apply(SIMD3(3, 4, 5)), SIMD3(3, 4, 5))
    }

    func testFacetsKnowWhichSideOfThePaperFacesTheViewer() {
        let sheet = facet(square)
        XCTAssertEqual(sheet.paperSign, 1)
        XCTAssertEqual(sheet.visibleFace, .white)
        XCTAssertEqual(facet(square.reversed()).visibleFace, .white)

        let flipped = sheet.moved(by: .turn(around: .zero, axis: SIMD3(0, 1, 0), angle: .pi))
        XCTAssertEqual(flipped.visibleFace, .color)
        assertPoint(flipped.place(SIMD2(1, 1)), SIMD3(-1, 1, 0))
        assertPoint(sheet.place(SIMD2(0.25, 0.5)), SIMD3(0.25, 0.5, 0))
        XCTAssertEqual(sheet.centroid, SIMD3(0.5, 0.5, 0))
    }

    func testGeometryMeasuresAndLocatesPoints() {
        XCTAssertEqual(PaperCraneGeometry.area(square), 1, accuracy: 0.0001)
        XCTAssertEqual(PaperCraneGeometry.area(square.map { SIMD3($0.x, $0.y, 0) }), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(PaperCraneGeometry.newell(square.map { SIMD3($0.x, $0.y, 0) }).z, 0)
        XCTAssertEqual(PaperCraneGeometry.side(SIMD3(0, 2, 0), .zero, SIMD3(1, 0, 0)), 2, accuracy: 0.0001)
        XCTAssertTrue(PaperCraneGeometry.contains(SIMD2(0.5, 0.5), facet(square).points))
        XCTAssertFalse(PaperCraneGeometry.contains(SIMD2(1.5, 0.5), facet(square).points))
        XCTAssertTrue(PaperCraneGeometry.overlaps(SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 0), SIMD2(2, 0)))
        XCTAssertFalse(PaperCraneGeometry.overlaps(SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 0), SIMD2(2, 0)))
        XCTAssertFalse(PaperCraneGeometry.overlaps(SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 0.1), SIMD2(1, 0.1)))
    }

    func testEaseStartsAndEndsAtRestAndClampsBadInput() {
        XCTAssertEqual(PaperCraneGeometry.ease(0), 0)
        XCTAssertEqual(PaperCraneGeometry.ease(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PaperCraneGeometry.ease(1), 1)
        XCTAssertEqual(PaperCraneGeometry.ease(-2), 0)
        XCTAssertEqual(PaperCraneGeometry.ease(3), 1)
        XCTAssertEqual(PaperCraneGeometry.ease(.nan), 0)
    }

    func testConeFindsTheRayAtBothAnglesNearestTheHint() {
        let a = SIMD3<Double>(1, 0, 0)
        let b = SIMD3<Double>(0, 1, 0)
        let up = PaperCraneGeometry.cone(a, .pi / 3, b, .pi / 3, near: SIMD3(0, 0, 1))
        let down = PaperCraneGeometry.cone(a, .pi / 3, b, .pi / 3, near: SIMD3(0, 0, -1))

        XCTAssertEqual(simd_dot(up, a), 0.5, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(up, b), 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(up.z, 0)
        XCTAssertLessThan(down.z, 0)
        assertPoint(PaperCraneGeometry.cone(a, 0.3, a, 0.3, near: SIMD3(0, 2, 0)), SIMD3(0, 1, 0))
    }

    func testSplittingKeepsPaperCoordinatesAndReportsTheCut() {
        let (parts, cut) = PaperCraneGeometry.split(facet(square), SIMD3(0.25, -1, 0), SIMD3(0.25, 2, 0))

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.map { PaperCraneGeometry.area($0.paper) }.map(abs).reduce(0, +), 1, accuracy: 0.0001)
        for part in parts {
            XCTAssertEqual(part.paper.count, part.points.count)
            for (paper, point) in zip(part.paper, part.points) {
                assertPoint(point, SIMD3(paper.x, paper.y, 0))
            }
        }
        XCTAssertEqual(cut?.0.x ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(cut?.1.x ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(PaperCraneGeometry.split(facet(square), SIMD3(2, 0, 0), SIMD3(2, 1, 0)).parts, [facet(square)])
        XCTAssertNil(PaperCraneGeometry.split(facet(square), SIMD3(1, 0, 0), SIMD3(1, 1, 0)).cut)
    }

    func testComponentFollowsPaperUntilItReachesTheFoldOrABarrier() {
        var stacked = PaperCraneWorkshop(facets: [facet(square), facet([SIMD2(1, 0), SIMD2(2, 0), SIMD2(2, 1), SIMD2(1, 1)], layer: 1)])
        let flap = stacked.component(at: SIMD2(1.8, 0.5), line: SIMD3(1.5, 0, 0), SIMD3(1.5, 1, 0))
        XCTAssertEqual(flap, [1])
        XCTAssertEqual(stacked.facets.count, 3)

        var joined = PaperCraneWorkshop(facets: [facet(square), facet([SIMD2(1, 0), SIMD2(2, 0), SIMD2(2, 1), SIMD2(1, 1)])])
        XCTAssertEqual(joined.component(at: SIMD2(1.8, 0.5), line: SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0)).count, 2)

        var blocked = PaperCraneWorkshop(facets: [facet(square), facet([SIMD2(1, 0), SIMD2(2, 0), SIMD2(2, 1), SIMD2(1, 1)])])
        let held = blocked.component(at: SIMD2(1.8, 0.5), line: SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0), barriers: [(SIMD3(1, 0, 0), SIMD3(1, 1, 0))])
        XCTAssertEqual(held, [1])
        XCTAssertEqual(blocked.seams.count, 1)

        var lower = facet(square, layer: 0)
        lower.paper = lower.paper.map { $0 + SIMD2(5, 0) }
        var layered = PaperCraneWorkshop(facets: [lower, facet(square, layer: 1)])
        XCTAssertEqual(layered.stack(at: SIMD2(0.5, 0.5)), [1, 0])
        XCTAssertEqual(layered.component(at: SIMD2(0.5, 0.5), depth: -1, line: SIMD3(2, 0, 0), SIMD3(2, 1, 0)), [0])
        XCTAssertTrue(layered.component(at: SIMD2(5, 5), line: SIMD3(2, 0, 0), SIMD3(2, 1, 0)).isEmpty)
    }

    func testValleyAndMountainFoldsLiftTowardAndAwayFromTheViewer() {
        var workshop = PaperCraneWorkshop(facets: [facet(square)])
        let flap = workshop.component(at: SIMD2(0.8, 0.5), line: SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0))
        let valley = workshop.fold(flap, SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0))
        let mountain = workshop.fold(flap, SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0), mountain: true)
        let center = workshop.center(flap)

        XCTAssertEqual(valley.count, PaperCraneWorkshop.sampleCount + 1)
        XCTAssertGreaterThan(valley[valley.count / 2].apply(center).z, 0.1)
        XCTAssertLessThan(mountain[mountain.count / 2].apply(center).z, -0.1)
        assertPoint(valley[valley.count - 1].apply(center), SIMD3(0.25, 0.5, 0))
        XCTAssertEqual(workshop.center(flap, pose: valley[valley.count - 1]).x, 0.25, accuracy: 0.0001)
    }

    func testPerformStacksFoldedFlapsAndRecordsHints() {
        var workshop = PaperCraneWorkshop(facets: [facet(square)])
        let line = (SIMD3<Double>(0.5, 0, 0), SIMD3<Double>(0.5, 1, 0))
        let flap = workshop.component(at: SIMD2(0.8, 0.5), line: line.0, line.1)
        workshop.perform([.init(facets: flap, samples: workshop.fold(flap, line.0, line.1), window: 0.2...0.8, layering: .over, group: "flap", crease: line)])

        let fold = workshop.folds[0]
        let moving = fold.pieces.firstIndex { $0.body != nil } ?? 0
        let still = 1 - moving
        XCTAssertGreaterThan(fold.end[moving].layer, fold.end[still].layer)
        XCTAssertEqual(fold.end[moving].group, "flap")
        XCTAssertEqual(fold.end[moving].visibleFace, .color)
        XCTAssertEqual(fold.points(moving, at: 0.1), fold.pieces[moving].facet.points)
        XCTAssertEqual(fold.layer(moving, at: 0), fold.pieces[moving].facet.layer)
        XCTAssertEqual(fold.layer(moving, at: 1), fold.pieces[moving].endLayer)
        XCTAssertEqual(fold.pose(still, at: 0.5), .identity)
        XCTAssertEqual(fold.start.count, 2)
        XCTAssertEqual(fold.hint.creases.count, 1)
        XCTAssertEqual(fold.hint.creases[0][0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(fold.hint.arrows.count, 1)
        XCTAssertGreaterThan(fold.hint.arrows[0].from.x, fold.hint.arrows[0].to.x)
        XCTAssertFalse(fold.hint.mountain)
        XCTAssertFalse(fold.hint.turnOver)
        XCTAssertTrue(fold.end[moving].edges.contains(.edge))
    }

    func testLayeringRulesPlaceMovedPaperAboveBelowOrWhereTold() {
        let line = (SIMD3<Double>(0.5, 0, 0), SIMD3<Double>(0.5, 1, 0))
        func layers(_ layering: PaperCraneWorkshop.Layering, mountain: Bool = false) -> (moving: Double, still: Double) {
            var workshop = PaperCraneWorkshop(facets: [facet(square, layer: 0.3)])
            let flap = workshop.component(at: SIMD2(0.8, 0.5), line: line.0, line.1)
            workshop.perform([.init(facets: flap, samples: workshop.fold(flap, line.0, line.1, mountain: mountain), layering: layering, crease: line)])
            let fold = workshop.folds[0]
            let moving = fold.pieces.firstIndex { $0.body != nil } ?? 0
            return (fold.end[moving].layer, fold.end[1 - moving].layer)
        }

        XCTAssertGreaterThan(layers(.over).moving, layers(.over).still)
        XCTAssertLessThan(layers(.under, mountain: true).moving, layers(.under, mountain: true).still)
        XCTAssertEqual(layers(.flip).moving, -0.3, accuracy: 0.0001)
        XCTAssertEqual(layers(.keep).moving, 0.3, accuracy: 0.0001)
        XCTAssertGreaterThan(layers(.settle).moving, layers(.settle).still)

        var workshop = PaperCraneWorkshop(facets: [facet(square)])
        let flap = workshop.component(at: SIMD2(0.8, 0.5), line: line.0, line.1)
        workshop.perform([.init(facets: flap, samples: workshop.fold(flap, line.0, line.1, mountain: true), layering: .custom([flap[0]: 7]), tucked: true, crease: line)])
        XCTAssertEqual(workshop.facets[flap[0]].layer, 7)
        XCTAssertTrue(workshop.folds[0].pieces[flap[0]].tucked)
        XCTAssertTrue(workshop.folds[0].hint.mountain)
    }

    func testCreasesThatOpenFlatStayFaintAndSeamsStayHidden() {
        var workshop = PaperCraneWorkshop(facets: [facet(square)])
        workshop.cut([0], SIMD3(0.5, 0, 0), SIMD3(0.5, 1, 0))
        workshop.cut([0, 1], SIMD3(0, 0.5, 0), SIMD3(1, 0.5, 0), seam: true)
        let styled = PaperCraneWorkshop.styled(workshop.facets, seams: workshop.seams)

        XCTAssertEqual(styled.count, 4)
        XCTAssertEqual(workshop.seams.count, 2)
        for facet in styled {
            XCTAssertEqual(facet.edges.filter { $0 == .edge }.count, 2)
            XCTAssertEqual(facet.edges.filter { $0 == .crease }.count, 1)
            XCTAssertEqual(facet.edges.filter { $0 == .hidden }.count, 1)
        }

        workshop.regroup("left", [0])
        XCTAssertEqual(workshop.facets[0].group, "left")
    }

    func testCameraTurnsAndBlendsViews() {
        assertPoint(PaperCraneCamera.flat.apply(SIMD3(0.3, -0.2, 0.1)), SIMD3(0.3, -0.2, 0.1))
        assertPoint(PaperCraneCamera(yaw: .pi / 2, pitch: 0).apply(SIMD3(1, 0, 0)), SIMD3(0, 0, -1))
        assertPoint(PaperCraneCamera(yaw: 0, pitch: .pi / 2).apply(SIMD3(0, 1, 0)), SIMD3(0, 0, 1))
        XCTAssertEqual(PaperCraneCamera.flat.mix(PaperCraneCamera(yaw: 1, pitch: -0.5), 0.5), PaperCraneCamera(yaw: 0.5, pitch: -0.25))
    }

    func testPieceWindowsDelayMotion() {
        let piece = PaperCranePiece(facet: facet(square), body: 0, window: 0.5...1, endLayer: 0, tucked: false)

        XCTAssertEqual(piece.local(0.4), 0)
        XCTAssertEqual(piece.local(0.75), 0.5, accuracy: 0.0001)
        XCTAssertEqual(piece.local(1), 1)
        XCTAssertNil([1, 2][safe: 2])
        XCTAssertEqual([1, 2][safe: 1], 2)
    }

    func testSettlingOpensAFoldedSheetSymmetricallyAndKeepsItJoined() {
        let sheet = facet([SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)])
        var workshop = PaperCraneWorkshop(facets: [sheet])
        let hinge = (SIMD3<Double>(0, -1, 0), SIMD3<Double>(0, 1, 0))
        let flap = workshop.component(at: SIMD2(0.5, 0), line: hinge.0, hinge.1)
        workshop.perform([.init(facets: flap, samples: workshop.fold(flap, hinge.0, hinge.1), layering: .over)])
        let top = flap[0]
        let bottom = 1 - top
        let open = PaperCraneWorkshop.Driver(
            facets: [top],
            pose: { PaperCranePose.turn(around: .zero, axis: SIMD3(0, 1, 0), angle: 0.6 * $0) },
            group: "page",
            crease: hinge,
            arrow: true,
        )
        workshop.settle(
            drivers: [open],
            mirror: (SIMD2(0, -1), SIMD2(0, 1)),
            front: SIMD2(0.5, 0),
            camera: PaperCraneCamera(yaw: 0.3, pitch: 0),
            iterations: 30,
        )

        let fold = workshop.folds[1]
        let topEdge = fold.points(top, at: 1).min { $0.x < $1.x } ?? .zero
        let bottomEdge = fold.points(bottom, at: 1).min { $0.x < $1.x } ?? .zero
        XCTAssertGreaterThan(topEdge.z, 0.3)
        XCTAssertEqual(bottomEdge.z, -topEdge.z, accuracy: 0.01)
        XCTAssertEqual(bottomEdge.x, topEdge.x, accuracy: 0.01)
        XCTAssertEqual(fold.pieces[top].track.count, PaperCraneWorkshop.sampleCount + 1)
        XCTAssertEqual(fold.end[top].group, "page")
        XCTAssertEqual(fold.endCamera, PaperCraneCamera(yaw: 0.3, pitch: 0))
        XCTAssertEqual(fold.hint.creases.count, 1)
        for (paper, point) in zip(fold.pieces[top].facet.paper, fold.points(top, at: 0.5)) where abs(paper.x) < 0.000_1 {
            let partner = fold.pieces[bottom].facet.paper.firstIndex { simd_distance($0, paper) < 0.000_1 }
            XCTAssertNotNil(partner)
            if let partner {
                XCTAssertLessThan(simd_distance(fold.points(bottom, at: 0.5)[partner], point), 0.000_001)
            }
        }
    }

    func testTrackedPiecesFollowTheirRecordedCorners() {
        let piece = PaperCranePiece(
            facet: facet(square),
            body: nil,
            window: 0...1,
            endLayer: 0,
            tucked: false,
            track: [square.map { SIMD3($0.x, $0.y, 0) }, square.map { SIMD3($0.x, $0.y, 1) }],
        )
        let fold = PaperCraneFold(
            pieces: [piece],
            bodies: [],
            end: [],
            startCamera: .flat,
            endCamera: .flat,
            hint: PaperCraneHint(creases: [], arrows: [], mountain: false, turnOver: false),
            seams: [],
        )

        XCTAssertEqual(fold.points(0, at: 0.5).map(\.z), [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(fold.points(0, at: 1).map(\.z), [1, 1, 1, 1])
    }
}
