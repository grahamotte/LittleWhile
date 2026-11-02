import XCTest
@testable import LittleWhileCore

final class PlaneAtlasTests: XCTestCase {
    func testCitiesIncludeCapitalsStateCapitalsAndFamousCitiesOnDrawnLand() {
        let cities = PlaneAtlas.cities
        let capitals = cities.filter { $0.kind == .capital }

        XCTAssertEqual(cities.count, 483)
        XCTAssertEqual(capitals.count, 169)
        XCTAssertEqual(Set(capitals.map(\.country)).count, capitals.count)
        XCTAssertEqual(cities.filter { $0.kind == .stateCapital }.count, 198)
        XCTAssertEqual(cities.filter { $0.kind == .city }.count, 116)
        XCTAssertEqual(cities.filter(\.hub).count, 100)
        for city in cities {
            XCTAssertFalse(city.name.isEmpty)
            XCTAssertFalse(city.name.contains("  "))
            XCTAssertLessThanOrEqual(abs(city.latitude), 90)
            XCTAssertLessThanOrEqual(abs(city.longitude), 180)
        }
        for (index, city) in cities.enumerated() {
            for other in cities[(index + 1)...] where city.kind != .capital || other.kind != .capital {
                XCTAssertGreaterThan(city.point.angle(to: other.point) * PlaneTrip.earthRadius, 30, "\(city.name) and \(other.name)")
            }
        }
        let paris = capitals.first { $0.country == "France" }
        XCTAssertEqual(paris?.name, "Paris")
        XCTAssertEqual(paris?.latitude ?? 0, 48.87, accuracy: 0.1)
        XCTAssertEqual(paris?.longitude ?? 0, 2.33, accuracy: 0.1)
        XCTAssertEqual(capitals.first { $0.country == "Kazakhstan" }?.name, "Astana")
        XCTAssertEqual(capitals.first { $0.country == "Nigeria" }?.name, "Abuja")
        XCTAssertNil(cities.first { $0.country == "Maldives" })
        XCTAssertNil(cities.first { $0.name == "Honolulu" })
        XCTAssertEqual(cities.first { $0.name == "Sacramento" }?.kind, .stateCapital)
        XCTAssertEqual(cities.first { $0.name == "Toronto" }?.kind, .stateCapital)
        XCTAssertEqual(cities.first { $0.name == "Chengdu" }?.kind, .stateCapital)
        XCTAssertEqual(cities.first { $0.name == "Sydney" }?.kind, .stateCapital)
        XCTAssertEqual(cities.first { $0.name == "New York" }?.kind, .city)
        XCTAssertEqual(cities.first { $0.name == "Hong Kong" }?.kind, .city)
        XCTAssertEqual(cities.first { $0.name == "Venice" }?.kind, .city)
        XCTAssertEqual(cities.first { $0.name == "Vancouver" }?.country, "Canada")
        XCTAssertEqual(cities.filter { $0.hub }.map(\.name).filter { ["London", "Dubai", "Singapore", "Los Angeles", "Shanghai"].contains($0) }.count, 5)
        XCTAssertFalse(cities.first { $0.name == "Venice" }?.hub ?? true)
        XCTAssertFalse(cities.first { $0.name == "Vatican City" }?.hub ?? true)
    }

    func testCityParsingRejectsMalformedLines() {
        XCTAssertEqual(
            PlaneAtlas.city("Lima|Peru|c|-12.05|-77.05"),
            PlaneCity(name: "Lima", country: "Peru", latitude: -12.05, longitude: -77.05),
        )
        XCTAssertEqual(PlaneAtlas.city("Osaka|Japan|m|34.75|135.46")?.kind, .city)
        XCTAssertEqual(PlaneAtlas.city("Austin|United States|s|30.27|-97.74")?.kind, .stateCapital)
        XCTAssertEqual(PlaneAtlas.city("Austin|United States|s|30.27|-97.74")?.hub, false)
        XCTAssertEqual(PlaneAtlas.city("Tokyo|Japan|C|35.69|139.75"), PlaneCity(name: "Tokyo", country: "Japan", latitude: 35.69, longitude: 139.75, kind: .capital, hub: true))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|-12.05|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|x|-12.05|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|cs|-12.05|-77.05"))
        XCTAssertNil(PlaneAtlas.city("|Peru|c|-12.05|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|c|north|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|c|91|-77.05"))
        XCTAssertNil(PlaneAtlas.city("Lima|Peru|c|10|181"))
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
