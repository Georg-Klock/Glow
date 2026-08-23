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

    // MARK: - Which week is on screen (#117, #190)

    // The fixtures below read in `TestCalendar.monday`'s own locale, en_GB, so
    // the day leads and the month follows. That ordering is the locale's and
    // not this code's — which is the point of formatting the range through the
    // calendar rather than composing it — and a suite pinned to en_US would
    // read "Aug 17 – 23" for the same week.
    //
    // `dash` is written out because the separator is not the ASCII one it looks
    // like: `Date.IntervalFormatStyle` joins with an en dash between two thin
    // spaces, and the first version of these fixtures failed with two strings
    // that printed identically. `WeekCalendar.rangeSeparator` is the same
    // characters, used where the range has to be composed rather than
    // formatted, and it is written here rather than referenced so that a change
    // to it fails a test instead of moving one.
    private let dash = "\u{2009}\u{2013}\u{2009}"

    private func title(_ weekOf: Date, today: Date) -> String {
        WeekCalendar.weekRangeTitle(
            for: WeekCalendar.week(containing: weekOf, calendar: calendar),
            today: today,
            calendar: calendar
        )
    }

    @Test("A week inside one month names the month once")
    func aWeekInOneMonthNamesItOnce() {
        let wednesday = TestCalendar.date(2026, 8, 19)
        #expect(title(wednesday, today: wednesday) == "17\(dash)23 Aug")
    }

    @Test("A week that straddles a month end names both months")
    func aStraddlingWeekNamesBoth() {
        // The week of Monday 31 August, seen on Wednesday 2 September. The
        // month title this replaced said "September" and nothing about the
        // three days of August in front of it.
        let wednesday = TestCalendar.date(2026, 9, 2)
        #expect(title(wednesday, today: wednesday) == "31 Aug\(dash)6 Sep")
    }

    @Test("The year appears only on the end that is not in this one")
    func theYearArrivesWhenItHasTo() {
        let january = TestCalendar.date(2026, 1, 14)
        // Twelve weeks back from mid-January is late October of the year
        // before. Both ends are in it, so the year is said once, at the end.
        #expect(title(TestCalendar.date(2025, 10, 22), today: january) == "20 Oct\(dash)26 Oct 2025")
        // A week across the year boundary, seen from the new year: the old
        // year has to be said and the new one is today's, so it is not.
        #expect(title(TestCalendar.date(2025, 12, 31), today: january) == "29 Dec 2025\(dash)4 Jan")
        // The same week seen from inside it, on New Year's Eve, says the other
        // half: 2025 is this year now, and 2026 is the one that needs naming.
        let newYearsEve = TestCalendar.date(2025, 12, 31)
        #expect(title(newYearsEve, today: newYearsEve) == "29 Dec\(dash)4 Jan 2026")
    }

    @Test("A week in this month and this year says no year at all")
    func noYearOnTheCurrentWeek() {
        let august = TestCalendar.date(2026, 8, 19)
        #expect(!title(august, today: august).contains("2026"))
    }

    // MARK: - How far back, as a number (#207)

    // What the title ladder switches on. The ladder itself — This Week, Last
    // Week, Two Weeks Ago, then the range — is UI text composed in
    // `WeeklyGridView` from this number, and it is checked by looking at the
    // screen at each step; the arithmetic under it is checked here.

    private func count(_ weekOf: Date, latest: Date) -> Int {
        WeekCalendar.weeksBack(
            from: WeekCalendar.startOfWeek(containing: weekOf, calendar: calendar),
            latest: WeekCalendar.startOfWeek(containing: latest, calendar: calendar),
            calendar: calendar
        )
    }

    @Test("The rungs of the title ladder are the first three counts")
    func theLadderCountsWeeks() {
        let today = TestCalendar.date(2026, 8, 19)
        #expect(count(today, latest: today) == 0)
        // Any day of the same week is the same week, so the whole of it is
        // "This Week" and not the last day of it "Last Week".
        #expect(count(TestCalendar.date(2026, 8, 23), latest: today) == 0)
        #expect(count(TestCalendar.date(2026, 8, 12), latest: today) == 1)
        #expect(count(TestCalendar.date(2026, 8, 5), latest: today) == 2)
        // The first rung the ladder hands to the date range.
        #expect(count(TestCalendar.date(2026, 7, 29), latest: today) == 3)
    }

    @Test("A week that is not behind the newest one counts as zero, not as a negative")
    func nothingCountsForward() {
        let today = TestCalendar.date(2026, 8, 19)
        // The reach never puts a later week on screen, so this is a guard on
        // the arithmetic rather than a state the pager reaches: "This Week" is
        // the right title for it either way, and "−1 weeks ago" is not a
        // string this app should be able to produce.
        #expect(count(TestCalendar.date(2026, 8, 26), latest: today) == 0)
    }

    @Test("The count is whole weeks, not days divided by seven at a year end")
    func theCountSurvivesAYearEndAsANumber() {
        // `dateComponents([.weekOfYear], ...)` reads −39 across this boundary,
        // which is why the read counts days. The phrase test below covers the
        // same span; this one pins the number the ladder switches on.
        let january = TestCalendar.date(2026, 1, 14)
        #expect(count(TestCalendar.date(2025, 12, 31), latest: january) == 2)
    }

    // MARK: - How far back (#190)

    private func weeksBack(_ weekOf: Date, latest: Date) -> String? {
        WeekCalendar.weeksBackTitle(
            for: WeekCalendar.startOfWeek(containing: weekOf, calendar: calendar),
            latest: WeekCalendar.startOfWeek(containing: latest, calendar: calendar),
            calendar: calendar
        )
    }

    @Test("The newest week says nothing about how far back it is")
    func theCurrentWeekHasNoSuffix() {
        let today = TestCalendar.date(2026, 8, 19)
        #expect(weeksBack(today, latest: today) == nil)
        // A day later in the same week is the same week.
        #expect(weeksBack(TestCalendar.date(2026, 8, 17), latest: today) == nil)
    }

    @Test("One week back is singular, two are not")
    func theSingularBoundary() {
        let today = TestCalendar.date(2026, 8, 19)
        #expect(weeksBack(TestCalendar.date(2026, 8, 12), latest: today) == "1 week ago")
        #expect(weeksBack(TestCalendar.date(2026, 8, 5), latest: today) == "2 weeks ago")
    }

    @Test("The count survives a year end and the cap at twelve")
    func theCountReachesTheFloor() {
        // `weekOfYear` restarts on 1 January, so a distance counted in week
        // numbers would read −39 here rather than 12. This one counts days.
        let january = TestCalendar.date(2026, 1, 14)
        let earliest = WeekReach.from(
            recordStart: TestCalendar.date(2020, 1, 1), today: january, calendar: calendar
        ).earliest
        #expect(weeksBack(earliest, latest: january) == "12 weeks ago")
    }

    @Test("A daylight-saving transition does not lose a day of the count")
    func daylightSavingDoesNotShiftTheCount() {
        // Europe/Berlin springs forward on 2026-03-29, which is inside this
        // span: counted in seconds it would be an hour short of five weeks.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        berlin.locale = Locale(identifier: "en_GB")
        berlin.firstWeekday = 2

        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return berlin.date(from: components) ?? .distantPast
        }
        #expect(
            WeekCalendar.weeksBackTitle(
                for: date(2026, 3, 9), latest: date(2026, 4, 13), calendar: berlin
            ) == "5 weeks ago"
        )
    }
}
