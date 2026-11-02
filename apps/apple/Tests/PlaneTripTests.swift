import XCTest
@testable import LittleWhileCore

final class PlaneTripTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 10_000)
    private let seed = UUID(uuidString: "6D2B79F5-0C1A-4E3B-9C8D-7A6F5E4D3C2B")!
    private let line = [
        PlaneCity(name: "Zero", country: "A", latitude: 0, longitude: 0),
        PlaneCity(name: "Ten", country: "B", latitude: 0, longitude: 10),
        PlaneCity(name: "Ninety", country: "C", latitude: 0, longitude: 90),
    ]

    private func seeds(_ count: Int) -> [UUID] {
        (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
    }

    func testAFlightAroundTheEquatorTakesTwoHoursAndTripsRoundToFiveMinutes() {
        let circumference = 2 * Double.pi * PlaneTrip.earthRadius

        XCTAssertEqual(PlaneTrip.seconds(kilometers: circumference), 7_200, accuracy: 1e-9)
        XCTAssertEqual(PlaneTrip.seconds(kilometers: circumference / 2), 3_600, accuracy: 1e-9)
        XCTAssertEqual(PlaneTrip.bucket(149), 0)
        XCTAssertEqual(PlaneTrip.bucket(151), 300)
        XCTAssertEqual(PlaneTrip.bucket(1_499), 1_500)
        XCTAssertEqual(PlaneTrip.bucket(-60), 0)
        XCTAssertEqual(PlaneTrip.bucket(.nan), 0)
    }

    func testLongTimersAreSplitIntoLegsNoLongerThanTwentyMinutes() {
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: 60), 1)
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: 1_200), 1)
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: 1_201), 2)
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: 3_600), 3)
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: 7_200), 6)
        XCTAssertEqual(PlaneTrip.legCount(goalSeconds: .nan), 1)
    }

    func testEachRunFliesBetweenCapitalsWhoseFlightMatchesTheFocusTime() {
        for minutes in [1, 5, 10, 15, 20] {
            let target = PlaneTrip.bucket(TimeInterval(minutes * 60))
            for seed in seeds(4) {
                let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: minutes * 60, cycle: 0))
                XCTAssertEqual(trip.legs.count, 1)
                let leg = trip.legs[0]
                XCTAssertNotEqual(leg.from, leg.to)
                XCTAssertGreaterThanOrEqual(leg.kilometers, PlaneTrip.shortestHop)
                XCTAssertEqual(PlaneTrip.bucket(PlaneTrip.seconds(kilometers: leg.kilometers)), target, "\(minutes) minutes")
                XCTAssertEqual(leg.kilometers, trip.cities[leg.from].point.angle(to: trip.cities[leg.to].point) * PlaneTrip.earthRadius, accuracy: 1e-6)
            }
        }
    }

    func testLongerTimersFlyLongerTrips() {
        let short = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 5 * 60, cycle: 0))
        let long = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 20 * 60, cycle: 0))
        let longest = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 120 * 60, cycle: 0))

        XCTAssertLessThan(short.kilometers * 2, long.kilometers)
        XCTAssertLessThan(long.kilometers * 4, longest.kilometers)
    }

    func testTripsAreRandomPerRunButStableForTheSameRun() {
        let trips = seeds(20).map { PlaneTrip(key: PlaneTrip.Key(seed: $0, goalSeconds: 25 * 60, cycle: 0)).legs }

        XCTAssertGreaterThan(Set(trips.map { "\($0[0].from)-\($0[0].to)" }).count, 15)
        XCTAssertEqual(
            PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 0)).legs,
            PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 0)).legs,
        )
    }

    func testMultiLegTripsChainCapitalsWithoutRevisitingAny() {
        for seed in seeds(4) {
            let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 120 * 60, cycle: 0))

            XCTAssertEqual(trip.legs.count, 6)
            for (leg, next) in zip(trip.legs, trip.legs.dropFirst()) {
                XCTAssertEqual(leg.to, next.from)
            }
            XCTAssertEqual(Set(trip.stops.map(\.name)).count, 7)
            XCTAssertEqual(PlaneTrip.seconds(kilometers: trip.kilometers), 120 * 60, accuracy: 450)

        }
    }

    func testLongTripsKeepFlyingTheSameWayMostlyThroughBigCities() {
        var layovers = 0
        var hubs = 0
        for seed in seeds(12) {
            let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 120 * 60, cycle: 0))
            let points = trip.cities.map(\.point)

            for (leg, next) in zip(trip.legs, trip.legs.dropFirst()) {
                layovers += 1
                hubs += trip.cities[leg.to].hub ? 1 : 0
                let arrival = PlaneTrip.heading(from: points[leg.from], to: points[leg.to], at: points[leg.to])
                let departure = PlaneTrip.heading(from: points[next.from], to: points[next.to], at: points[next.from])
                XCTAssertGreaterThanOrEqual(arrival.dot(departure), PlaneTrip.straightness - 1e-9)
            }
        }
        XCTAssertGreaterThan(Double(hubs) / Double(layovers), 0.85)
    }

    func testHeadingPointsAlongTheGreatCircleTowardTheDestination() {
        let start = PlaneVector(latitude: 0, longitude: 0)
        let end = PlaneVector(latitude: 0, longitude: 90)

        let departure = PlaneTrip.heading(from: start, to: end, at: start)
        XCTAssertEqual(departure.y, 1, accuracy: 1e-9)
        let arrival = PlaneTrip.heading(from: start, to: end, at: end)
        XCTAssertEqual(arrival.x, -1, accuracy: 1e-9)
        XCTAssertEqual(PlaneTrip.heading(from: start, to: start, at: start), PlaneVector(x: 0, y: 0, z: 0))
        XCTAssertEqual(PlaneTrip.straightness, 0.5.squareRoot(), accuracy: 1e-9)
    }

    func testRulesRelaxWhenNoBigCityLiesAhead() {
        let cities = [
            PlaneCity(name: "West", country: "A", latitude: 0, longitude: 0, kind: .stateCapital),
            PlaneCity(name: "Middle", country: "B", latitude: 0, longitude: 90, kind: .stateCapital),
            PlaneCity(name: "Back", country: "C", latitude: 0, longitude: -90, kind: .stateCapital),
        ]

        let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 120 * 60, cycle: 0), cities: cities)
        XCTAssertEqual(trip.legs.count, 2)
    }

    func testEachLoopCycleTakesOffWhereTheLastOneLanded() {
        let first = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 0))
        let second = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 1))
        let third = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 2))

        XCTAssertEqual(second.legs[0].from, first.legs.last?.to)
        XCTAssertEqual(third.legs[0].from, second.legs.last?.to)
        XCTAssertNotEqual(second.legs[0].to, first.legs.last?.to)
        XCTAssertEqual(PlaneTrip.bucket(PlaneTrip.seconds(kilometers: second.legs[0].kilometers)), PlaneTrip.bucket(750))
    }

    func testTheClosestTripIsUsedWhenNoneMatchAndHopsBelowTheMinimumAreSkipped() {
        let close = [
            PlaneCity(name: "Here", country: "A", latitude: 0, longitude: 0),
            PlaneCity(name: "Next door", country: "B", latitude: 0, longitude: 1),
            PlaneCity(name: "Far", country: "C", latitude: 0, longitude: 30),
        ]

        let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_200, cycle: 0), cities: close)
        XCTAssertEqual(trip.legs.count, 1)
        XCTAssertGreaterThan(trip.legs[0].kilometers, 3_000)
        XCTAssertTrue(PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 0), cities: Array(close.prefix(1))).legs.isEmpty)
        XCTAssertTrue(PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_500, cycle: 0), cities: Array(close.prefix(2))).legs.isEmpty)
    }

    func testThePlaneBoardsFliesAlongTheGreatCircleAndLands() throws {
        let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_000, cycle: 0), cities: Array(line.prefix(2)))
        let start = trip.cities[trip.legs[0].from].point
        let end = trip.cities[trip.legs[0].to].point

        let boarding = try XCTUnwrap(trip.flight(elapsed: 0))
        XCTAssertEqual(boarding.stage, .boarding)
        XCTAssertEqual(boarding.position, start)
        XCTAssertEqual(boarding.altitude, 0)
        XCTAssertEqual(boarding.remainingKilometers, trip.kilometers, accuracy: 1e-9)

        let cruising = try XCTUnwrap(trip.flight(elapsed: 500))
        XCTAssertEqual(cruising.stage, .flying)
        XCTAssertEqual(cruising.progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(cruising.position.longitude, 5, accuracy: 1e-9)
        XCTAssertEqual(cruising.altitude, 1)
        XCTAssertEqual(cruising.remainingKilometers, trip.kilometers / 2, accuracy: 1e-6)
        XCTAssertEqual(cruising.heading.dot(cruising.position), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(cruising.heading.dot(end), 0)
        XCTAssertEqual(cruising.heading.length, 1, accuracy: 1e-9)

        let climbing = try XCTUnwrap(trip.flight(elapsed: 30))
        XCTAssertGreaterThan(climbing.altitude, 0)
        XCTAssertLessThan(climbing.altitude, 1)

        let landed = try XCTUnwrap(trip.flight(elapsed: 5_000))
        XCTAssertEqual(landed.stage, .landed)
        XCTAssertEqual(landed.position.angle(to: end), 0, accuracy: 1e-9)
        XCTAssertEqual(landed.altitude, 0)
        XCTAssertEqual(landed.remainingKilometers, 0, accuracy: 1e-9)
        XCTAssertEqual(trip.flight(elapsed: .nan)?.stage, .boarding)
        XCTAssertEqual(PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 0, cycle: 0), cities: line).flight(elapsed: 0)?.stage, .landed)
        XCTAssertNil(PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 600, cycle: 0), cities: []).flight(elapsed: 0))
    }

    func testMultiLegFlightsSpendTimeOnEachLegInProportionToItsDistance() throws {
        let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 120 * 60, cycle: 0))
        let first = trip.legs[0].kilometers / trip.kilometers

        let early = try XCTUnwrap(trip.flight(elapsed: 7_200 * first * 0.5))
        XCTAssertEqual(early.leg, 0)
        XCTAssertEqual(early.legProgress, 0.5, accuracy: 1e-9)
        let later = try XCTUnwrap(trip.flight(elapsed: 7_200 * (first + 0.01)))
        XCTAssertEqual(later.leg, 1)
        XCTAssertLessThan(later.legProgress, 0.1)
        let layover = try XCTUnwrap(trip.flight(elapsed: 7_200 * first))
        XCTAssertEqual(layover.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(trip.flight(elapsed: 7_199)?.leg, 5)
        XCTAssertEqual(trip.stops.count, 7)
    }

    func testTheFlightOnlyShowsWhileTheTimerIsGoing() {
        XCTAssertFalse(PlaneTrip.showsFlight(status: .ready))
        XCTAssertTrue(PlaneTrip.showsFlight(status: .running))
        XCTAssertTrue(PlaneTrip.showsFlight(status: .paused))
        XCTAssertFalse(PlaneTrip.showsFlight(status: .complete))
    }

    func testCaptionsAndRoutesDescribeTheTrip() throws {
        let trip = PlaneTrip(key: PlaneTrip.Key(seed: seed, goalSeconds: 1_000, cycle: 0), cities: Array(line.prefix(2)))

        XCTAssertEqual(PlaneTrip.caption(flight: trip.flight(elapsed: 0), trip: trip), "now boarding")
        let cruising = try XCTUnwrap(trip.flight(elapsed: 500))
        XCTAssertEqual(PlaneTrip.caption(flight: cruising, trip: trip), "\(Int(cruising.remainingKilometers.rounded()).formatted(.number.grouping(.automatic))) km to go")
        let from = trip.cities[trip.legs[0].from].name
        let to = trip.cities[trip.legs[0].to].name
        XCTAssertEqual(Set([from, to]), ["Zero", "Ten"])
        XCTAssertEqual(PlaneTrip.caption(flight: trip.flight(elapsed: 1_000), trip: trip), "welcome to \(to)")
        XCTAssertEqual(PlaneTrip.route(flight: cruising, trip: trip), "\(from) → \(to)")
        XCTAssertEqual(PlaneTrip.caption(flight: nil, trip: trip), "")
        XCTAssertEqual(PlaneTrip.route(flight: nil, trip: trip), "")
    }

    func testElapsedFollowsTheSnapshot() {
        let ready = TimerSnapshot(run: FocusRun(createdAt: date, goalSeconds: 60), at: date)
        let running = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, resumedAt: date), at: date.addingTimeInterval(10))
        let paused = TimerSnapshot(run: FocusRun(createdAt: date, startedAt: date, progressSeconds: 20, goalSeconds: 60), at: date)
        let looping = TimerSnapshot(
            run: FocusRun(createdAt: date, startedAt: date, goalSeconds: 60, restSeconds: 60, resumedAt: date, loops: true),
            at: date.addingTimeInterval(119.5),
        )

        XCTAssertEqual(PlaneTrip.elapsed(snapshot: ready, at: date.addingTimeInterval(500)), 0)
        XCTAssertEqual(PlaneTrip.elapsed(snapshot: running, at: date.addingTimeInterval(10.25)), 10.25, accuracy: 0.0001)
        XCTAssertEqual(PlaneTrip.elapsed(snapshot: running, at: date.addingTimeInterval(5)), 10, accuracy: 0.0001)
        XCTAssertEqual(PlaneTrip.elapsed(snapshot: running, at: date.addingTimeInterval(500)), 60)
        XCTAssertEqual(PlaneTrip.elapsed(snapshot: paused, at: date.addingTimeInterval(500)), 20)
        XCTAssertEqual(PlaneTrip.elapsed(snapshot: looping, at: date.addingTimeInterval(120.5)), 0.5, accuracy: 0.0001)
    }
}
