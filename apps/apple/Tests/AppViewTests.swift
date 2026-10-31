import XCTest
@testable import LittleWhileCore

@MainActor
final class AppViewTests: XCTestCase {
    func testCreatesAppViewWithoutRequestingSystemNotifications() async {
        let suite = "AppViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RunStore(defaults: defaults)
        _ = AppView(store: store)
        XCTAssertEqual(store.currentRun.goalSeconds, 1500)
        XCTAssertEqual(store.currentRun.restSeconds, 300)
    }
}
