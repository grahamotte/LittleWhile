import XCTest
@testable import App

final class PaperCraneLedgerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PaperCraneLedgerTests"
    private let first = UUID(uuidString: "6D2B79F5-0C1A-4E3B-9C8D-7A6F5E4D3C2B")!
    private let second = UUID(uuidString: "1B2B79F5-0C1A-4E3B-9C8D-7A6F5E4D3C2B")!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testStartsAtZeroAndShowsCranesStillBeingCredited() {
        let ledger = PaperCraneLedger(defaults: defaults)

        XCTAssertEqual(ledger.total, 0)
        XCTAssertEqual(ledger.count(run: first, cranes: 3), 3)
        XCTAssertEqual(ledger.credited(first), 0)
    }

    func testCreditsEachRunOnlyForCranesItHasNotAlreadyCounted() {
        var ledger = PaperCraneLedger(defaults: defaults)
        ledger.credit(run: first, cranes: 2)
        ledger.credit(run: first, cranes: 5)
        ledger.credit(run: first, cranes: 5)
        ledger.credit(run: first, cranes: 1)

        XCTAssertEqual(ledger.total, 5)
        XCTAssertEqual(ledger.count(run: first, cranes: 1), 5)
        XCTAssertEqual(ledger.count(run: first, cranes: 7), 7)

        ledger.credit(run: second, cranes: 3)
        XCTAssertEqual(ledger.total, 8)
        XCTAssertEqual(ledger.count(run: second, cranes: 0), 8)
    }

    func testLifetimeTotalSurvivesRelaunchAndNeverGoesDown() {
        var ledger = PaperCraneLedger(defaults: defaults)
        ledger.credit(run: first, cranes: 4)

        var reopened = PaperCraneLedger(defaults: defaults)
        XCTAssertEqual(reopened.total, 4)
        XCTAssertEqual(reopened.credited(first), 4)
        reopened.credit(run: first, cranes: 6)
        XCTAssertEqual(PaperCraneLedger(defaults: defaults).total, 6)
    }

    func testRemembersOnlyRecentRunsWithoutLosingTheTotal() {
        var ledger = PaperCraneLedger(defaults: defaults)
        for _ in 0..<(PaperCraneLedger.remembered + 4) {
            ledger.credit(run: UUID(), cranes: 1)
        }

        XCTAssertEqual(ledger.credits.count, PaperCraneLedger.remembered)
        XCTAssertEqual(ledger.total, PaperCraneLedger.remembered + 4)
    }

    func testIgnoresUnreadableStorage() {
        defaults.set(Data("nonsense".utf8), forKey: PaperCraneLedger.storageKey)

        XCTAssertEqual(PaperCraneLedger(defaults: defaults).total, 0)
    }
}
