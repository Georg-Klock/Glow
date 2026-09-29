import Foundation
import Testing
@testable import Glow

/// Which week This Week shows once today or the week start has moved under it.
///
/// One sentence, two clauses: the current week follows, any other week stays.
/// The fixed cases below name the two ways the current week used to be left
/// behind — a new week beginning, and the week start changing in Settings —
/// and the sweep holds both clauses over zones that move their clocks at
/// midnight, every pair of week starts, and days either side of a year's end.
@Suite("Week follow")
struct WeekFollowTests {
    private static func calendar(_ zone: String = "UTC", firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func day(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.startOfDay(for: calendar.date(from: components) ?? .distantPast)
    }

    private let monday = Self.calendar(firstWeekday: WeekPreferences.monday)
    private let sunday = Self.calendar(firstWeekday: WeekPreferences.sunday)

    // MARK: - A new week begins

    /// The failure this replaces, stated against the type that used to be the
    /// whole of the refresh: clamping into the new reach keeps last week,
    /// because last week is inside it.
    @Test("The reach's clamp alone keeps the week just ended")
    func theClampAloneStaysBehind() {
        let lastWeek = Self.day(monday, 2026, 9, 21)
        let reach = WeekReach.from(
            recordStart: nil, today: Self.day(monday, 2026, 9, 28), calendar: monday
        )
        #expect(reach.clamped(lastWeek) == lastWeek)
    }

    @Test("On the current week at a week boundary, the screen follows")
    func theCurrentWeekFollowsMidnight() {
        let shown = Self.day(monday, 2026, 9, 21)
        let followed = WeekFollow.weekStart(
            shown: shown, previousCurrent: shown,
            today: Self.day(monday, 2026, 9, 28), calendar: monday
        )
        #expect(followed == Self.day(monday, 2026, 9, 28))
    }

    @Test("A browsed week stays where it is at a week boundary")
    func aBrowsedWeekStaysAtMidnight() {
        let shown = Self.day(monday, 2026, 9, 7)
        let followed = WeekFollow.weekStart(
            shown: shown, previousCurrent: Self.day(monday, 2026, 9, 21),
            today: Self.day(monday, 2026, 9, 28), calendar: monday
        )
        #expect(followed == shown)
    }

    @Test("Midnight inside a week changes nothing")
    func midnightInsideAWeek() {
        let shown = Self.day(monday, 2026, 9, 28)
        let followed = WeekFollow.weekStart(
            shown: shown, previousCurrent: shown,
            today: Self.day(monday, 2026, 9, 30), calendar: monday
        )
        #expect(followed == shown)
    }

    @Test("Across a year's end the current week follows into January")
    func theYearTurns() {
        // Monday-first: Dec 28 2026 – Jan 3 2027, then Jan 4.
        let shown = Self.day(monday, 2026, 12, 28)
        #expect(WeekFollow.weekStart(
            shown: shown, previousCurrent: shown,
            today: Self.day(monday, 2027, 1, 4), calendar: monday
        ) == Self.day(monday, 2027, 1, 4))
        // Sunday-first: Dec 27 2026 – Jan 2 2027, then Jan 3.
        let shownSunday = Self.day(sunday, 2026, 12, 27)
        #expect(WeekFollow.weekStart(
            shown: shownSunday, previousCurrent: shownSunday,
            today: Self.day(sunday, 2027, 1, 3), calendar: sunday
        ) == Self.day(sunday, 2027, 1, 3))
    }

    // MARK: - The week start changes

    /// Tuesday 29 September 2026. Sunday-first, this week began on the 27th;
    /// in a Monday-first calendar the 27th closes *last* week, which is what
    /// the grid used to draw under the title "This Week".
    @Test("Sunday to Monday on the current week lands on the new current week")
    func sundayToMonday() {
        let today = Self.day(monday, 2026, 9, 29)
        let shown = Self.day(sunday, 2026, 9, 27)
        #expect(WeekCalendar.startOfWeek(containing: shown, calendar: monday)
            == Self.day(monday, 2026, 9, 21))

        let followed = WeekFollow.weekStart(
            shown: shown, previousCurrent: shown, today: today, calendar: monday
        )
        #expect(followed == Self.day(monday, 2026, 9, 28))
        #expect(WeekCalendar.week(containing: followed, calendar: monday).contains(today))
    }

    /// Monday-first, this week began on the 28th; Sunday-first it begins on the
    /// 27th, so the old start stopped equalling the current week's and the
    /// current-week controls went with it.
    @Test("Monday to Sunday on the current week lands on the new current week")
    func mondayToSunday() {
        let today = Self.day(monday, 2026, 9, 29)
        let shown = Self.day(monday, 2026, 9, 28)
        let followed = WeekFollow.weekStart(
            shown: shown, previousCurrent: shown, today: today, calendar: sunday
        )
        #expect(followed == WeekCalendar.startOfWeek(containing: today, calendar: sunday))
        #expect(followed == Self.day(sunday, 2026, 9, 27))
    }

    /// A browsed Sunday-first week, 13–19 September, regrouped Monday-first:
    /// 14–20 holds six of its seven days, and is the week shown.
    @Test("A browsed week lands on the new week holding most of its days")
    func aBrowsedWeekIsRegrouped() {
        let followed = WeekFollow.weekStart(
            shown: Self.day(sunday, 2026, 9, 13),
            previousCurrent: Self.day(sunday, 2026, 9, 27),
            today: Self.day(monday, 2026, 9, 29), calendar: monday
        )
        #expect(followed == Self.day(monday, 2026, 9, 14))
    }

    // MARK: - The sweep

    static let zones = [
        "UTC", "America/Los_Angeles", "Europe/Berlin", "Australia/Sydney",
        "America/Havana", "America/Santiago",
    ]

    /// Days to stand on: both of Berlin's and Havana's clock changes, a year's
    /// last and first days, and ordinary days between.
    static let days = [
        (2025, 3, 9), (2025, 3, 30), (2025, 10, 26), (2025, 11, 2),
        (2025, 12, 31), (2026, 1, 1), (2026, 3, 8), (2026, 3, 29),
        (2026, 9, 29), (2026, 10, 25), (2026, 12, 31), (2027, 1, 3),
    ]

    /// Every pair of week starts, in every zone, on every day above, the
    /// current week and three browsed ones: the current week lands on the week
    /// holding today, a browsed one on a normalized week start sharing at least
    /// four of its days — and exactly on itself when the week start did not
    /// change, which is the midnight case.
    @Test("Both clauses hold everywhere", arguments: WeekFollowTests.zones)
    func sweep(zone: String) {
        var failure: String?
        var checked = 0
        for old in 1...7 {
            for new in 1...7 {
                let before = Self.calendar(zone, firstWeekday: old)
                let after = Self.calendar(zone, firstWeekday: new)
                for (year, month, dayOfMonth) in Self.days {
                    let today = Self.day(after, year, month, dayOfMonth)
                    let previousCurrent = WeekCalendar.startOfWeek(containing: today, calendar: before)

                    let followed = WeekFollow.weekStart(
                        shown: previousCurrent, previousCurrent: previousCurrent,
                        today: today, calendar: after
                    )
                    if followed != WeekCalendar.startOfWeek(containing: today, calendar: after)
                        || !WeekCalendar.week(containing: followed, calendar: after).contains(today) {
                        failure = failure ?? "\(zone) \(old)->\(new) \(year)-\(month)-\(dayOfMonth): current week did not follow"
                    }
                    checked += 1

                    for back in 1...3 {
                        guard let moved = before.date(byAdding: .day, value: -7 * back, to: previousCurrent)
                        else { continue }
                        let shown = WeekCalendar.startOfWeek(containing: moved, calendar: before)
                        let kept = WeekFollow.weekStart(
                            shown: shown, previousCurrent: previousCurrent,
                            today: today, calendar: after
                        )
                        let oldDays = Set(WeekCalendar.week(containing: shown, calendar: before).days)
                        let newDays = Set(WeekCalendar.week(containing: kept, calendar: after).days)
                        if kept != WeekCalendar.startOfWeek(containing: kept, calendar: after)
                            || oldDays.intersection(newDays).count < 4
                            || (old == new && kept != shown) {
                            failure = failure ?? "\(zone) \(old)->\(new) \(year)-\(month)-\(dayOfMonth) back \(back): browsed week moved"
                        }
                        checked += 1
                    }
                }
            }
        }
        #expect(failure == nil, "\(failure ?? "")")
        #expect(checked == 7 * 7 * Self.days.count * 4)
    }
}
