import XCTest
@testable import LittleWhileCore

final class PlaneAtlasTests: XCTestCase {
    func testCapitalsOnDrawnLandAppearOncePerCountryWithValidCoordinates() {
        let capitals = PlaneAtlas.capitals

        XCTAssertEqual(capitals.count, 169)
        XCTAssertEqual(Set(capitals.map(\.country)).count, capitals.count)
        for city in capitals {
            XCTAssertFalse(city.name.isEmpty)
            XCTAssertLessThanOrEqual(abs(city.latitude), 90)
            XCTAssertLessThanOrEqual(abs(city.longitude), 180)
        }
        let paris = capitals.first { $0.country == "France" }
        XCTAssertEqual(paris?.name, "Paris")
        XCTAssertEqual(paris?.latitude ?? 0, 48.87, accuracy: 0.1)
        XCTAssertEqual(paris?.longitude ?? 0, 2.33, accuracy: 0.1)
        XCTAssertEqual(capitals.first { $0.country == "Kazakhstan" }?.name, "Astana")
        XCTAssertNil(capitals.first { $0.country == "Nauru" })
        XCTAssertNil(capitals.first { $0.country == "Maldives" })
        XCTAssertEqual(capitals.first { $0.country == "Nigeria" }?.name, "Abuja")
    }

    func testCityParsingRejectsMalformedLines() {
        XCTAssertEqual(
            PlaneAtlas.city("Lima|Peru|-12.05|-77.05"),
            PlaneCity(name: "Lima", country: "Peru", latitude: -12.05, longitude: -77.05),
        )
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|-12.05"))
        XCTAssertNil(PlaneAtlas.city("|Peru|-12.05|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|north|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|91|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|10|181"))
    }

    func testRingsAreDensifiedSoNoEdgeIsLongerThanTheMaximumStep() {
        let ring = PlaneAtlas.ring("0,0 200,0 200,100 bad 0,100")

        XCTAssertEqual(ring.first, PlaneVector(latitude: 0, longitude: 0))
        XCTAssertGreaterThan(ring.count, 4)
        for (index, point) in ring.enumerated() {
            let next = ring[(index + 1) % ring.count]
            XCTAssertLessThanOrEqual(point.angle(to: next), PlaneAtlas.maximumStep + 1e-9)
            XCTAssertEqual(point.length, 1, accuracy: 1e-9)
        }
        XCTAssertEqual(PlaneAtlas.ring("0,0 10,10").count, 2)
    }

    func testLandHasTheContinentsAndOnlyAntarcticIslandsArePolar() {
        let land = PlaneAtlas.land

        XCTAssertGreaterThan(land.count, 50)
        XCTAssertGreaterThan(land.map(\.count).reduce(0, +), 2_500)
        let polar = land.filter(PlaneAtlas.isPolar)
        XCTAssertFalse(polar.isEmpty)
        XCTAssertTrue(polar.allSatisfy { $0.allSatisfy { $0.latitude < -60 } })
        XCTAssertTrue(land.filter { $0.contains { $0.latitude > -55 } }.allSatisfy { !PlaneAtlas.isPolar($0) })
        XCTAssertFalse(PlaneAtlas.isPolar([]))
        XCTAssertTrue(PlaneAtlas.isPolar([PlaneVector(latitude: -80, longitude: 0), PlaneVector(latitude: -70, longitude: 90)]))
        XCTAssertFalse(PlaneAtlas.isPolar([PlaneVector(latitude: -54, longitude: -68), PlaneVector(latitude: -53, longitude: -70)]))
    }
}
