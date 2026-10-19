import XCTest
@testable import App

@MainActor
final class TimerThemesTests: XCTestCase {
    func testRegistryContainsThemesWithStableIdentities() async {
        XCTAssertEqual(TimerThemes.all.map(\.id), ["boring", "mr-smiles", "he-loves-me", "paper-crane"])
        XCTAssertEqual(TimerThemes.resolve("boring").name, "Boring")
        XCTAssertEqual(TimerThemes.resolve("mr-smiles").name, "Mr Smiles")
        XCTAssertEqual(TimerThemes.resolve("mr-smiles").colorScheme, .dark)
        XCTAssertEqual(TimerThemes.resolve("he-loves-me").name, "He Loves Me")
        XCTAssertEqual(TimerThemes.resolve("he-loves-me").colorScheme, .light)
        XCTAssertEqual(TimerThemes.resolve("paper-crane").name, "Paper Crane")
        XCTAssertEqual(TimerThemes.resolve("paper-crane").colorScheme, .light)
    }

    func testUnavailableThemeUsesBoringWithoutChangingSavedIdentifier() async {
        let run = FocusRun(theme: "future-theme")
        XCTAssertEqual(TimerThemes.resolve(run.theme).id, "boring")
        XCTAssertEqual(run.theme, "future-theme")
    }
}
