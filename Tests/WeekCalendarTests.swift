import Foundation
import Testing
@testable import Glow

@Suite("Week boundaries")
struct WeekCalendarTests {
    private let calendar = TestCalendar.monday

    @Test("A week starts on Monday and runs seven days")
    func weekShape() {
        let wednesday = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: wednesday, calendar: calendar)

        #expect(week.days.count == 7)
        #expect(week.start == TestCalendar.date(2026, 8, 17))
        #expect(week.days.last == TestCalendar.date(2026, 8, 23))
        #expect(calendar.component(.weekday, from: week.start) == 2)
    }

    @Test("Sunday belongs to the week that started the Monday before it")
    func sundayIsTheEndOfTheWeek() {
        // The bug this guards: with a Sunday-first calendar, Sunday would open
        // a new week and every column would shift by one.
        let sunday = TestCalendar.date(2026, 8, 23)
        let week = WeekCalendar.week(containing: sunday, calendar: calendar)

        #expect(week.start == TestCalendar.date(2026, 8, 17))
        #expect(week.index(of: sunday) == 6)
    }

    @Test("Monday is its own week's first day")
    func mondayIsTheStart() {
        let monday = TestCalendar.date(2026, 8, 17)
        let week = WeekCalendar.week(containing: monday, calendar: calendar)

        #expect(week.start == monday)
        #expect(week.index(of: monday) == 0)
    }

    @Test("Any instant during a day normalizes to that day's midnight")
    func dayNormalization() {
        let midnight = TestCalendar.date(2026, 8, 19)
        let lateEvening = midnight.addingTimeInterval(23 * 3600 + 59 * 60)

        #expect(WeekCalendar.day(lateEvening, calendar: calendar) == midnight)
        #expect(WeekCalendar.day(midnight, calendar: calendar) == midnight)
    }

    @Test("Weeks are seven distinct midnights even across a DST transition")
    func daylightSavingWeek() {
        // Europe/Berlin springs forward on 2026-03-29, mid-week. Adding 86,400
        // seconds seven times would land these columns on 23:00 the day before.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        berlin.firstWeekday = 2

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 25
        let midWeek = berlin.date(from: components) ?? .distantPast

        let week = WeekCalendar.week(containing: midWeek, calendar: berlin)
        #expect(week.days.count == 7)
        #expect(Set(week.days).count == 7)
        for day in week.days {
            #expect(berlin.startOfDay(for: day) == day)
        }
    }

    @Test("Weekday initials are ordered Monday first")
    func weekdayInitialsOrder() {
        let initials = WeekCalendar.weekdayInitials(calendar: calendar)
        #expect(initials.count == 7)
        #expect(initials.first == "M")
        #expect(initials.last == "S")
    }

    @Test("Header dates are the week's own days, in order")
    func dayNumbersMatchTheWeek() {
        let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
        #expect(WeekCalendar.dayNumbers(in: week, calendar: calendar)
            == ["17", "18", "19", "20", "21", "22", "23"])
    }

    @Test("Header dates roll over a month boundary rather than running past it")
    func dayNumbersAcrossMonthEnd() {
        // The week of Monday 2026-08-31 runs into September, so the column
        // labels have to restart at 1 rather than read 32.
        let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 31), calendar: calendar)
        #expect(WeekCalendar.dayNumbers(in: week, calendar: calendar)
            == ["31", "1", "2", "3", "4", "5", "6"])
    }

    // MARK: - Which week is on screen (#117)

    private func title(_ weekOf: Date, today: Date) -> String {
        WeekCalendar.monthTitle(
            for: WeekCalendar.week(containing: weekOf, calendar: calendar),
            today: today,
            calendar: calendar
        )
    }

    @Test("The current week is named for today, straddle or no straddle")
    func theCurrentWeekIsNamedForToday() {
        let wednesday = TestCalendar.date(2026, 9, 2)
        // The week of Monday 31 August, seen on Wednesday 2 September. The
        // title reads September, which is what it read before there was a
        // pager at all — the rule was chosen so this did not move.
        #expect(title(wednesday, today: wednesday) == "September")
    }

    @Test("An earlier week is named for the day it starts on")
    func anEarlierWeekIsNamedForItsStart() {
        let today = TestCalendar.date(2026, 9, 2)
        #expect(title(TestCalendar.date(2026, 8, 31), today: TestCalendar.date(2026, 8, 31)) == "August")
        // Paged back one, the same week is the one being looked at and it
        // begins in August.
        #expect(title(TestCalendar.date(2026, 8, 24), today: today) == "August")
    }

    @Test("The year appears only when it is not this one")
    func theYearArrivesWhenItHasTo() {
        let january = TestCalendar.date(2026, 1, 14)
        #expect(title(january, today: january) == "January")
        // Twelve weeks back from mid-January is late October of the year
        // before, and "October" alone would not say which.
        #expect(title(TestCalendar.date(2025, 10, 22), today: january) == "October 2025")
    }
}
