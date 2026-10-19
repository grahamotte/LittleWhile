import XCTest
@testable import App

final class PaperCraneFoldingTests: XCTestCase {
    private func assertPoint(_ point: SIMD3<Double>, _ expected: SIMD3<Double>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(point.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(point.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }

    private func facet(_ points: [SIMD3<Double>], layer: Double = 0) -> PaperCraneFacet {
        PaperCraneFacet(
            group: "sheet",
            points: points,
            strokes: Array(repeating: true, count: points.count),
            layer: layer,
            front: .white,
            back: .color,
        )
    }

    private let square = [SIMD3<Double>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)]

    func testGeometryMeasuresOrientsAndMovesPoints() {
        XCTAssertGreaterThan(PaperCraneGeometry.newell(square).z, 0)
        XCTAssertLessThan(PaperCraneGeometry.newell(square.reversed()).z, 0)
        XCTAssertEqual(PaperCraneGeometry.area(square), 1, accuracy: 0.0001)
        assertPoint(PaperCraneGeometry.rotate(SIMD3(1, 0, 0), origin: .zero, axis: SIMD3(0, 0, 1), angle: .pi / 2), SIMD3(0, 1, 0))
        assertPoint(PaperCraneGeometry.rotate(SIMD3(0, 1, 0), origin: SIMD3(0, 0.5, 0), axis: SIMD3(1, 0, 0), angle: .pi), SIMD3(0, 0, 0))
        assertPoint(PaperCraneGeometry.reflect(SIMD3(1, 0, 0.3), .zero, SIMD3(1, 1, 0)), SIMD3(0, 1, 0.3))
        XCTAssertGreaterThan(PaperCraneGeometry.side(SIMD3(0, 1, 0), .zero, SIMD3(1, 0, 0)), 0)
        XCTAssertLessThan(PaperCraneGeometry.side(SIMD3(0, -1, 0), .zero, SIMD3(1, 0, 0)), 0)
    }

    func testEaseStartsAndEndsAtRestAndClampsBadInput() {
        XCTAssertEqual(PaperCraneGeometry.ease(0), 0)
        XCTAssertEqual(PaperCraneGeometry.ease(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PaperCraneGeometry.ease(1), 1)
        XCTAssertEqual(PaperCraneGeometry.ease(-2), 0)
        XCTAssertEqual(PaperCraneGeometry.ease(3), 1)
        XCTAssertEqual(PaperCraneGeometry.ease(.nan), 0)
        XCTAssertLessThan(PaperCraneGeometry.ease(0.1), 0.1)
    }

    func testSplitCutsAlongTheLineAndOnlyStrokesCreases() {
        let pieces = PaperCraneGeometry.split(facet(square), SIMD3(0.25, -1, 0), SIMD3(0.25, 2, 0), crease: true)

        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces.map { PaperCraneGeometry.area($0.points) }.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(pieces.map { PaperCraneGeometry.area($0.points) }.min() ?? 0, 0.25, accuracy: 0.0001)
        for piece in pieces {
            XCTAssertEqual(piece.points.count, piece.strokes.count)
            XCTAssertTrue(piece.strokes.allSatisfy { $0 })
            XCTAssertEqual(piece.front, .white)
        }

        let seams = PaperCraneGeometry.split(facet(square), SIMD3(0.25, -1, 0), SIMD3(0.25, 2, 0), crease: false)
        XCTAssertEqual(seams.map { $0.strokes.filter { !$0 }.count }, [1, 1])
    }

    func testSplitThroughCornersAndOutsideTheSheet() {
        let diagonal = PaperCraneGeometry.split(facet(square), .zero, SIMD3(1, 1, 0), crease: false)
        XCTAssertEqual(diagonal.map(\.points.count), [3, 3])
        XCTAssertEqual(diagonal.map { $0.strokes.filter { !$0 }.count }, [1, 1])

        let outside = PaperCraneGeometry.split(facet(square), SIMD3(2, 0, 0), SIMD3(2, 1, 0), crease: true)
        XCTAssertEqual(outside, [facet(square)])
        XCTAssertEqual(PaperCraneGeometry.split(facet(square), SIMD3(1, 0, 0), SIMD3(1, 1, 0), crease: true), [facet(square)])
    }

    func testFacetReportsCentroidAndTheFaceTowardTheViewer() {
        XCTAssertEqual(facet(square).centroid, SIMD3(0.5, 0.5, 0))
        XCTAssertEqual(facet(square).visibleFace, .white)
        XCTAssertEqual(facet(square.reversed()).visibleFace, .color)
        XCTAssertEqual(facet([]).centroid, .zero)
    }

    func testCameraTurnsAndBlendsViews() {
        assertPoint(PaperCraneCamera.flat.apply(SIMD3(0.3, -0.2, 0.1)), SIMD3(0.3, -0.2, 0.1))
        assertPoint(PaperCraneCamera(yaw: .pi / 2, pitch: 0).apply(SIMD3(1, 0, 0)), SIMD3(0, 0, -1))
        assertPoint(PaperCraneCamera(yaw: 0, pitch: .pi / 2).apply(SIMD3(0, 1, 0)), SIMD3(0, 0, 1))
        XCTAssertEqual(PaperCraneCamera.flat.mix(PaperCraneCamera(yaw: 1, pitch: -0.5), 0.5), PaperCraneCamera(yaw: 0.5, pitch: -0.25))
    }

    func testRotatingPieceLiftsOffTheTableAndLandsFlipped() {
        let piece = PaperCranePiece(
            facet: facet(square),
            move: .rotate(origin: SIMD3(0, 1, 0), axis: SIMD3(1, 0, 0), angle: -.pi),
            window: 0...1,
            endLayer: 2,
            tucked: false,
        )

        XCTAssertEqual(piece.points(at: 0), square)
        XCTAssertGreaterThan(piece.points(at: 0.5)[0].z, 0.9)
        assertPoint(piece.points(at: 1)[0], SIMD3(0, 2, 0))
        XCTAssertEqual(piece.layer(at: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(piece.end.layer, 2)
        XCTAssertEqual(piece.end.visibleFace, .color)
    }

    func testPieceWindowsDelayMotion() {
        let piece = PaperCranePiece(
            facet: facet(square),
            move: .rotate(origin: .zero, axis: SIMD3(0, 1, 0), angle: .pi),
            window: 0.5...1,
            endLayer: 0,
            tucked: false,
        )

        XCTAssertEqual(piece.points(at: 0.4), square)
        XCTAssertEqual(piece.progress(0.75), 0.5, accuracy: 0.0001)
        XCTAssertEqual(piece.progress(1), 1)
    }

    func testMorphPassesThroughItsWaypoint() {
        let target = square.map { $0 * 2 }
        let via = square.map { $0 + SIMD3(0, 0, 0.5) }
        let piece = PaperCranePiece(facet: facet(square), move: .morph(via: via, to: target), window: 0...1, endLayer: 0, tucked: false)

        for (point, expected) in zip(piece.points(at: 0.5), via) {
            assertPoint(point, expected)
        }
        XCTAssertEqual(piece.end.points, target)
        XCTAssertEqual(piece.end.visibleFace, .white)
    }

    func testSwingSweepsAroundThePivotIntoTheMirrorImageWithoutFlippingTheFace() {
        let leg = [SIMD3<Double>(0, 0, 0), SIMD3(0.1, 1, 0), SIMD3(0, 1, 0)]
        let mirrored = leg.map { PaperCraneGeometry.reflect($0, .zero, SIMD3(1, 0, 0)) }
        let piece = PaperCranePiece(facet: facet(leg), move: .swing(pivot: .zero, angle: .pi, to: mirrored), window: 0...1, endLayer: 0, tucked: true)

        assertPoint(piece.points(at: 0.5)[2], SIMD3(-1, 0, 0))
        for (point, expected) in zip(piece.end.points, mirrored) {
            assertPoint(point, expected)
        }
        XCTAssertEqual(facet(leg).visibleFace, piece.end.visibleFace)
    }

    func testValleyFoldRisesTowardTheViewerAndStacksOnTop() {
        var workshop = PaperCraneWorkshop(facets: PaperCraneWorkshop.sheet())
        let northWest = SIMD3(-PaperCraneWorkshop.r, -PaperCraneWorkshop.r, 0)
        let southEast = SIMD3(PaperCraneWorkshop.r, PaperCraneWorkshop.r, 0)
        workshop.perform([.init(select: { $0.group == "a" }, kind: .fold(northWest, southEast, mountain: false, angle: .pi, layering: .top))])

        let fold = workshop.folds[0]
        let flap = fold.pieces[0]
        XCTAssertGreaterThan(flap.points(at: 0.5).map(\.z).max() ?? 0, 0.5)
        XCTAssertGreaterThan(flap.endLayer, fold.pieces[1].endLayer)
        XCTAssertEqual(workshop.facets[0].visibleFace, .color)
        XCTAssertEqual(workshop.facets[1].visibleFace, .white)
        XCTAssertTrue(workshop.facets[0].strokes[2])
        XCTAssertEqual(fold.hint.creases.count, 1)
        assertPoint(fold.hint.creases[0][0], northWest)
        assertPoint(fold.hint.creases[0][1], southEast)
        XCTAssertEqual(fold.hint.arrows.count, 1)
        XCTAssertLessThan(fold.hint.arrows[0].from.y, 0)
        XCTAssertGreaterThan(fold.hint.arrows[0].to.y, 0)
        XCTAssertFalse(fold.hint.mountain)
        XCTAssertFalse(fold.hint.turnOver)
    }

    func testMountainFoldTucksBehindAndTurningOverReversesTheStack() {
        var workshop = PaperCraneWorkshop(facets: PaperCraneWorkshop.sheet())
        let northWest = SIMD3(-PaperCraneWorkshop.r, -PaperCraneWorkshop.r, 0)
        let southEast = SIMD3(PaperCraneWorkshop.r, PaperCraneWorkshop.r, 0)
        workshop.perform([.init(select: { $0.group == "a" }, kind: .fold(northWest, southEast, mountain: true, angle: .pi, layering: .bottom))])

        XCTAssertLessThan(workshop.folds[0].pieces[0].points(at: 0.5).map(\.z).min() ?? 0, -0.5)
        XCTAssertLessThan(workshop.facets[0].layer, workshop.facets[1].layer)
        XCTAssertTrue(workshop.folds[0].hint.mountain)

        workshop.perform([.init(select: { _ in true }, kind: .turnOver)])
        XCTAssertGreaterThan(workshop.facets[0].layer, workshop.facets[1].layer)
        XCTAssertEqual(workshop.facets[1].visibleFace, .color)
        XCTAssertTrue(workshop.folds[1].hint.turnOver)
        XCTAssertTrue(workshop.folds[1].hint.arrows.isEmpty)
    }

    func testWorkshopCutsPaintsAndRegroupsSelectedPaper() {
        var workshop = PaperCraneWorkshop(facets: PaperCraneWorkshop.sheet())
        workshop.cut(.zero, SIMD3(0, 1, 0), crease: true) { $0.group == "a" }
        XCTAssertEqual(workshop.facets.count, 3)

        workshop.paint(.color) { $0.group == "b" }
        workshop.regroup("wing") { $0.group == "a" }
        XCTAssertEqual(workshop.facets.map(\.group), ["wing", "wing", "b"])
        XCTAssertEqual(workshop.facets[2].front, .color)
        XCTAssertEqual(workshop.facets[2].back, .color)
        XCTAssertEqual(workshop.facets[0].front, .white)
    }

    func testMorphAndSwingActionsKeepUnselectedPaperStill() {
        var workshop = PaperCraneWorkshop(facets: PaperCraneWorkshop.sheet())
        workshop.perform(
            [
                .init(select: { $0.group == "a" }, kind: .morph(to: { $0 * 0.5 }, via: { start, end in (start + end) / 2 }), regroup: "small"),
                .init(select: { $0.group == "b" }, kind: .swing(.zero, SIMD3(1, 0, 0), pivot: .zero, turn: 1), window: 0.2...0.8),
            ],
            camera: PaperCraneCamera(yaw: 0.2, pitch: 0),
        )

        let fold = workshop.folds[0]
        XCTAssertEqual(workshop.facets[0].group, "small")
        XCTAssertEqual(PaperCraneGeometry.area(workshop.facets[0].points), 0.25, accuracy: 0.0001)
        XCTAssertTrue(fold.pieces[1].tucked)
        XCTAssertEqual(fold.pieces[1].window, 0.2...0.8)
        XCTAssertEqual(fold.startCamera, .flat)
        XCTAssertEqual(fold.endCamera, PaperCraneCamera(yaw: 0.2, pitch: 0))
        XCTAssertEqual(fold.hint.creases.count, 1)
        XCTAssertEqual(fold.hint.arrows.count, 2)
        XCTAssertEqual(fold.start, PaperCraneWorkshop.sheet())
        guard case let .swing(_, angle, _) = fold.pieces[1].move else { return XCTFail("expected a swing") }
        XCTAssertGreaterThan(angle, 0)
        XCTAssertLessThanOrEqual(angle, 2 * .pi)
    }
}
