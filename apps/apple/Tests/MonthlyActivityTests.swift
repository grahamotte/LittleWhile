import XCTest
@testable import App

final class MonthlyActivityTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEmptyMonthIncludesEveryDayAndSundayFirstAlignment() {
        let now = date(2026, 9, 29)
        let activity = MonthlyActivity(runs: [], month: now, at: now, calendar: calendar)

        XCTAssertEqual(activity.month, date(2026, 9, 1, hour: 0))
        XCTAssertEqual(activity.days.map(\.number), Array(1...30))
        XCTAssertEqual(Set(activity.days.map(\.id)).count, 30)
        XCTAssertTrue(activity.days.allSatisfy { $0.focusSeconds == 0 && $0.dotDiameter == 3 })
        XCTAssertEqual(activity.leadingBlankCount, 2)
        XCTAssertEqual(activity.weekdaySymbols, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    func testMondayFirstCalendarReordersWeekdaysAndGrid() {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let now = date(2026, 9, 29)
        let activity = MonthlyActivity(runs: [], month: now, at: now, calendar: mondayCalendar)

        XCTAssertEqual(activity.leadingBlankCount, 1)
        XCTAssertEqual(activity.weekdaySymbols, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }

    func testLeapYearAndMonthLengths() {
        let now = date(2026, 9, 29)
        for (year, month, count) in [(2024, 2, 29), (2025, 2, 28), (2026, 1, 31)] {
            let activity = MonthlyActivity(runs: [], month: date(year, month, 15), at: now, calendar: calendar)
            XCTAssertEqual(activity.days.count, count)
            XCTAssertEqual(activity.days.last?.number, count)
        }
    }

    func testAggregatesPartialAndCompletedFocusWithoutRestOrReadyRuns() {
        let now = date(2026, 9, 29)
        let started = date(2026, 9, 10)
        let runs = [
            FocusRun(createdAt: started, startedAt: started, progressSeconds: 1_800, goalSeconds: 1_500, restSeconds: 300),
            FocusRun(createdAt: started, startedAt: started, progressSeconds: 120),
            FocusRun(createdAt: started),
            FocusRun(createdAt: date(2026, 8, 10), progressSeconds: 1_500),
            FocusRun(createdAt: date(2026, 10, 1), progressSeconds: 1_500),
        ]
        let activity = MonthlyActivity(runs: runs, month: now, at: now, calendar: calendar)

        XCTAssertEqual(activity.days[9].focusSeconds, 1_620)
        XCTAssertEqual(activity.days.reduce(0) { $0 + $1.focusSeconds }, 1_620)
    }

    func testUsesLocalStartDayInsteadOfCreationDayAndFallsBackForLegacyRuns() {
        let now = date(2026, 9, 29)
        let started = date(2026, 9, 1, hour: 23)
        let runs = [
            FocusRun(createdAt: date(2026, 8, 30), startedAt: started, progressSeconds: 900),
            FocusRun(createdAt: date(2026, 9, 2), progressSeconds: 300),
            FocusRun(createdAt: now, startedAt: now.addingTimeInterval(60), progressSeconds: 100),
        ]
        let activity = MonthlyActivity(runs: runs, month: now, at: now, calendar: calendar)

        XCTAssertEqual(activity.days[0].focusSeconds, 900)
        XCTAssertEqual(activity.days[1].focusSeconds, 300)
        XCTAssertEqual(activity.days[28].focusSeconds, 0)
    }

    func testRunningTimeUpdatesAndCapsAtFocusGoalDuringRest() {
        let started = date(2026, 9, 29)
        let run = FocusRun(createdAt: started, startedAt: started, progressSeconds: 60, goalSeconds: 300, restSeconds: 300, resumedAt: started)
        let earlier = MonthlyActivity(runs: [run], month: started, at: started.addingTimeInterval(60), calendar: calendar)
        let later = MonthlyActivity(runs: [run], month: started, at: started.addingTimeInterval(400), calendar: calendar)

        XCTAssertEqual(earlier.days[28].focusSeconds, 120)
        XCTAssertEqual(later.days[28].focusSeconds, 300)
    }

    func testDeletingRunRemovesItsActivity() {
        let now = date(2026, 9, 29)
        let run = FocusRun(createdAt: now, progressSeconds: 300)
        let before = MonthlyActivity(runs: [run], month: now, at: now, calendar: calendar)
        let after = MonthlyActivity(runs: [], month: now, at: now, calendar: calendar)

        XCTAssertEqual(before.days[28].focusSeconds, 300)
        XCTAssertEqual(after.days[28].focusSeconds, 0)
    }

    func testInvalidProgressAndNegativeGoalsDoNotAddActivity() {
        let now = date(2026, 9, 29)
        let runs = [
            FocusRun(createdAt: now, progressSeconds: -.infinity),
            FocusRun(createdAt: now, progressSeconds: .nan),
            FocusRun(createdAt: now, progressSeconds: -10),
            FocusRun(createdAt: now, progressSeconds: 100, goalSeconds: -100, restSeconds: 300),
        ]
        let activity = MonthlyActivity(runs: runs, month: now, at: now, calendar: calendar)

        XCTAssertEqual(activity.days[28].focusSeconds, 0)
    }

    func testDotSizeUsesConsistentBoundedScaleAcrossMonths() {
        let now = date(2026, 9, 29)
        let day = MonthlyActivity.Day.self

        XCTAssertEqual(day.init(date: now, number: 1, focusSeconds: 1).dotDiameter, 6)
        XCTAssertEqual(day.init(date: now, number: 1, focusSeconds: 1_500).dotDiameter, 10)
        XCTAssertEqual(day.init(date: now, number: 1, focusSeconds: 6_000).dotDiameter, 20)
        XCTAssertEqual(day.init(date: now, number: 1, focusSeconds: 100_000).dotDiameter, 28)
    }

    func testMonthNavigationCrossesYearBoundaryAndStopsAtCurrentMonth() {
        let now = date(2026, 1, 15)
        let current = MonthlyActivity(runs: [], month: now, at: now, calendar: calendar)
        let previousMonth = current.month(byAdding: -1, at: now)
        let previous = MonthlyActivity(runs: [], month: previousMonth, at: now, calendar: calendar)

        XCTAssertFalse(current.canGoForward(at: now))
        XCTAssertEqual(current.month(byAdding: 1, at: now), current.month)
        XCTAssertEqual(previousMonth, date(2025, 12, 1, hour: 0))
        XCTAssertTrue(previous.canGoForward(at: now))
        XCTAssertEqual(previous.month(byAdding: 1, at: now), current.month)
        XCTAssertEqual(current.month(byAdding: -24, at: now), date(2024, 1, 1, hour: 0))
    }

    func testFutureSelectionClampsToCurrentMonthAndRolloverAllowsNavigation() {
        let now = date(2026, 9, 29)
        let activity = MonthlyActivity(runs: [], month: date(2026, 10, 1), at: now, calendar: calendar)

        XCTAssertEqual(activity.month, date(2026, 9, 1, hour: 0))
        XCTAssertFalse(activity.canGoForward(at: now))
        XCTAssertTrue(activity.canGoForward(at: date(2026, 10, 1)))
        XCTAssertEqual(activity.month(byAdding: 1, at: date(2026, 10, 1)), date(2026, 10, 1, hour: 0))
    }

    func testDayGenerationHandlesDaylightSavingTransitions() {
        let now = date(2026, 9, 29)
        let activity = MonthlyActivity(runs: [], month: date(2026, 3, 15), at: now, calendar: calendar)

        XCTAssertEqual(activity.days.count, 31)
        XCTAssertTrue(activity.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        XCTAssertEqual(activity.days[8].date.timeIntervalSince(activity.days[7].date), 23 * 3_600)
    }
}
