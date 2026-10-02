import Foundation

struct MonthlyActivity {
    struct Day: Identifiable {
        let date: Date
        let number: Int
        let focusSeconds: TimeInterval

        var id: Date { date }

        var dotDiameter: Double {
            guard focusSeconds > 0 else { return 3 }
            return min(28, max(6, 10 * sqrt(focusSeconds / 1_500)))
        }
    }

    let month: Date
    let days: [Day]
    let leadingBlankCount: Int
    let weekdaySymbols: [String]
    private let calendar: Calendar

    init(runs: [FocusRun], month: Date, at date: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let currentMonth = calendar.dateInterval(of: .month, for: date)!.start
        let interval = calendar.dateInterval(of: .month, for: min(month, currentMonth))!
        self.month = interval.start
        leadingBlankCount = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.shortWeekdaySymbols
        weekdaySymbols = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }

        var totals: [Date: TimeInterval] = [:]
        for run in runs {
            let startedAt = run.startedAt ?? run.createdAt
            guard startedAt <= date, interval.contains(startedAt) else { continue }
            totals[calendar.startOfDay(for: startedAt), default: 0] += run.focusElapsed(at: date)
        }

        days = calendar.range(of: .day, in: .month, for: interval.start)!.map { number in
            let day = calendar.date(byAdding: .day, value: number - 1, to: interval.start)!
            return Day(date: day, number: number, focusSeconds: totals[day, default: 0])
        }
    }

    func month(byAdding offset: Int, at date: Date) -> Date {
        let nextMonth = calendar.date(byAdding: .month, value: offset, to: month)!
        let currentMonth = calendar.dateInterval(of: .month, for: date)!.start
        return min(nextMonth, currentMonth)
    }

    func canGoForward(at date: Date) -> Bool {
        month < calendar.dateInterval(of: .month, for: date)!.start
    }
}
