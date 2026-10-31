import XCTest
@testable import LittleWhileCore

@MainActor
final class TimerThemesTests: XCTestCase {
    func testRegistryContainsThemesWithStableIdentities() async {
        XCTAssertEqual(TimerThemes.all.map(\.id), ["boring", "mr-smiles", "he-loves-me", "paper-crane", "graveyard"])
        XCTAssertEqual(TimerThemes.resolve("boring").name, "Boring")
        XCTAssertEqual(TimerThemes.resolve("mr-smiles").name, "Mr Smiles")
        XCTAssertEqual(TimerThemes.resolve("mr-smiles").colorScheme, .dark)
        XCTAssertEqual(TimerThemes.resolve("he-loves-me").name, "He Loves Me")
        XCTAssertEqual(TimerThemes.resolve("he-loves-me").colorScheme, .light)
        XCTAssertEqual(TimerThemes.resolve("paper-crane").name, "千羽鶴")
        XCTAssertEqual(TimerThemes.resolve("paper-crane").colorScheme, .light)
        XCTAssertEqual(TimerThemes.resolve("graveyard").name, "Graveyard")
        XCTAssertEqual(TimerThemes.resolve("graveyard").colorScheme, .dark)
    }

    func testUnavailableThemeUsesBoringWithoutChangingSavedIdentifier() async {
        let run = FocusRun(theme: "future-theme")
        XCTAssertEqual(TimerThemes.resolve(run.theme).id, "boring")
        XCTAssertEqual(run.theme, "future-theme")
    }
}
