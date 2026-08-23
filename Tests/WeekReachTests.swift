import Foundation
import Testing
@testable import Glow

/// How far back the week view may be paged.
///
/// The rule is one sentence — as far as the record reaches, capped at twelve
/// weeks — and every test here is one clause of it.
@Suite("Week reach")
struct WeekReachTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var thisWeek: Date { TestCalendar.date(2026, 8, 17) }

    private func reach(recordStart: Date?) -> WeekReach {
        WeekReach.from(recordStart: recordStart, today: today, calendar: calendar)
    }

    /// How many weeks the reach spans, which is the rule stated as a number.
    /// Counted in days and divided: a `weekOfYear` difference across a year
    /// boundary is not the number of weeks between two dates.
    private func weeksBack(_ reach: WeekReach) -> Int {
        (calendar.dateComponents([.day], from: reach.earliest, to: reach.latest).day ?? 0) / 7
    }

    @Test("An empty store can be paged nowhere")
    func noRecordNoReach() {
        let reach = reach(recordStart: nil)

        #expect(reach.earliest == thisWeek)
        #expect(reach.latest == thisWeek)
        #expect(weeksBack(reach) == 0)
    }

    @Test("A record that starts this week can be paged nowhere either")
    func freshInstallHasNoReach() {
        // Every habit created today: there is no earlier week to correct.
        let reach = reach(recordStart: today)

        #expect(reach.earliest == thisWeek)
        #expect(weeksBack(reach) == 0)
    }

    @Test("The reach is the record's, week by week", arguments: 0...11)
    func reachFollowsTheRecord(back: Int) {
        let start = calendar.date(byAdding: .day, value: -7 * back, to: today)!
        let reach = reach(recordStart: start)

        #expect(weeksBack(reach) == back)
        #expect(reach.earliest == calendar.date(byAdding: .day, value: -7 * back, to: thisWeek))
    }

    @Test("A record longer than a quarter is capped at twelve weeks")
    func longRecordIsCapped() {
        let twoYearsAgo = calendar.date(byAdding: .day, value: -730, to: today)!
        let reach = reach(recordStart: twoYearsAgo)

        #expect(weeksBack(reach) == WeekReach.maximumWeeksBack)
        #expect(reach.earliest == calendar.date(byAdding: .day, value: -7 * 12, to: thisWeek))
    }

    @Test("`.distantPast` is a cap, not a scroll with no end")
    func distantPastIsHarmless() {
        // `Habit.createdAt` defaults to this for every row written before the
        // column existed, which is the reason the cap is there at all.
        let reach = reach(recordStart: .distantPast)

        #expect(weeksBack(reach) == WeekReach.maximumWeeksBack)
    }

    @Test("The demo's ten weeks are all reachable")
    func theDemoFitsInsideTheCap() {
        // `SeededHistory.weeks` of invented past, and the pager has to reach
        // the whole of it or the demo shows a week the app cannot open.
        #expect(SeededHistory.weeks <= WeekReach.maximumWeeksBack)

        let seeded = calendar.date(byAdding: .day, value: -7 * SeededHistory.weeks, to: today)!
        #expect(weeksBack(reach(recordStart: seeded)) == SeededHistory.weeks)
    }

    @Test("Forward stops at the current week")
    func forwardStopsAtThisWeek() {
        let reach = reach(recordStart: calendar.date(byAdding: .day, value: -30, to: today)!)

        #expect(reach.latest == thisWeek)
        #expect(reach.step(thisWeek, by: 1, calendar: calendar) == thisWeek)
        #expect(!reach.contains(calendar.date(byAdding: .day, value: 7, to: thisWeek)!))
    }

    @Test("A record starting in the future leaves the pager where it is")
    func recordAheadOfToday() {
        // A clock that went backwards, or a sync from a device whose did.
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        let reach = reach(recordStart: nextMonth)

        #expect(reach.earliest == thisWeek)
        #expect(reach.latest == thisWeek)
    }

    @Test("Stepping back lands on week starts and stops at the floor")
    func steppingBackStopsAtTheFloor() {
        let reach = reach(recordStart: calendar.date(byAdding: .day, value: -21, to: today)!)

        var cursor = thisWeek
        for expected in 1...3 {
            cursor = reach.step(cursor, by: -1, calendar: calendar)
            #expect(cursor == calendar.date(byAdding: .day, value: -7 * expected, to: thisWeek))
        }
        // The floor holds: another step changes nothing.
        #expect(reach.step(cursor, by: -1, calendar: calendar) == cursor)
        #expect(cursor == reach.earliest)
    }

    @Test("Clamping pulls a week that has stopped existing back into range")
    func clampingBothEnds() {
        let reach = reach(recordStart: calendar.date(byAdding: .day, value: -14, to: today)!)
        let tooFar = calendar.date(byAdding: .day, value: -70, to: thisWeek)!
        let ahead = calendar.date(byAdding: .day, value: 7, to: thisWeek)!

        #expect(reach.clamped(tooFar) == reach.earliest)
        #expect(reach.clamped(ahead) == reach.latest)
        #expect(reach.clamped(reach.earliest) == reach.earliest)
    }

    @Test("Every week inside the reach is a week the pager can name")
    func everyWeekInRangeIsReachable() {
        let reach = reach(recordStart: .distantPast)

        for back in 0...WeekReach.maximumWeeksBack {
            let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek)!
            #expect(reach.contains(start), "\(back) weeks back was out of reach")
            // And each one is a real week start, seven days wide.
            let week = WeekCalendar.week(containing: start, calendar: calendar)
            #expect(week.start == start)
            #expect(week.days.count == 7)
        }
    }

    // MARK: - The pager's one invariant (#242)

    /// Zones a week boundary can be surprising in, and the controls.
    ///
    /// The last three are the interesting ones: they move their clocks *at*
    /// midnight rather than at two or three in the morning, so one day of the
    /// year has no 00:00 and another has two. Northern and southern DST are
    /// both here because they run in opposite phase, and two zones with no DST
    /// at all are here to show the sweep is not passing for want of anything to
    /// find.
    static let zones = [
        "America/Los_Angeles",
        "Europe/Berlin",
        "Australia/Sydney",
        "Pacific/Auckland",
        "Asia/Tokyo",
        "UTC",
        "America/Havana",
        "America/Santiago",
        "America/Sao_Paulo",
    ]

    private static func calendar(_ zone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func described(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ (EEE)"
        return formatter.string(from: date)
    }

    /// **The chevron's enabled state and its action are the same value, so they
    /// have to agree** (#242).
    ///
    /// `WeeklyGridView` disables the back chevron when `weekStart <=
    /// reach.earliest` and, when it does not, moves by `reach.step(weekStart,
    /// by: -1)`. Those are two reads of one `WeekReach`, and a chevron that is
    /// enabled and does nothing is exactly the two of them disagreeing. Stated
    /// as a rule over the logic alone: **if the button is enabled, stepping
    /// back changes the week on screen.**
    ///
    /// On the *week*, not on the `Date`. `show(week:)` skips only when the new
    /// value equals the old one, so a step that moved `weekStart` by an hour
    /// would still assign — and nothing on screen would move, because the title
    /// and the grid are both drawn from the week, not from the instant. A step
    /// that changes the date but not the week is a dead button with extra
    /// steps.
    ///
    /// Swept rather than sampled: a year of days, three times of day, two
    /// record lengths, three week starts and every week the pager can sit on,
    /// per zone — 86,349 enabled chevrons each. Before the fix it failed 166
    /// times, all of them in `America/Havana` and `America/Santiago`, and not
    /// once in the other seven zones.
    @Test("An enabled back chevron always lands on a different week", arguments: WeekReachTests.zones)
    func theBackChevronAlwaysMoves(zone: String) {
        var checks = 0
        var failure: String?

        for firstWeekday in [1, 2, 7] {
            let calendar = Self.calendar(zone, firstWeekday: firstWeekday)
            var components = DateComponents()
            components.year = 2025
            components.month = 1
            components.day = 1
            guard let base = calendar.date(from: components) else { continue }

            for dayIndex in 0..<365 {
                guard let day = calendar.date(byAdding: .day, value: dayIndex, to: base) else { continue }
                for hour in [0, 13, 23] {
                    guard let today = calendar.date(
                        byAdding: .hour, value: hour, to: calendar.startOfDay(for: day)
                    ) else { continue }

                    // A record inside the cap and one well beyond it: the floor
                    // is the record in the first and the cap in the second.
                    for daysOfRecord in [3, 7 * WeekReach.maximumWeeksBack] {
                        guard let recordStart = calendar.date(
                            byAdding: .day, value: -daysOfRecord, to: today
                        ) else { continue }
                        let reach = WeekReach.from(
                            recordStart: recordStart, today: today, calendar: calendar
                        )

                        // Both floors are week starts, which is what makes the
                        // comparisons below comparisons between like things.
                        if failure == nil {
                            for floor in [reach.earliest, reach.latest]
                            where WeekCalendar.startOfWeek(containing: floor, calendar: calendar) != floor {
                                failure = """
                                \(zone) firstWeekday=\(firstWeekday): a reach floor is not a week start
                                  floor = \(Self.described(floor, calendar))
                                  week  = \(Self.described(WeekCalendar.startOfWeek(containing: floor, calendar: calendar), calendar))
                                """
                            }
                        }

                        // Every week the pager can be sitting on, one past each
                        // end, and what clamping makes of them.
                        var weekStarts = [reach.earliest, reach.latest]
                        for back in 0...(WeekReach.maximumWeeksBack + 1) {
                            guard let raw = calendar.date(
                                byAdding: .day, value: -7 * back, to: reach.latest
                            ) else { continue }
                            let start = WeekCalendar.startOfWeek(containing: raw, calendar: calendar)
                            weekStarts.append(start)
                            weekStarts.append(reach.clamped(start))
                        }

                        for weekStart in weekStarts {
                            // The pager's own `.disabled(weekStart <= earliest)`.
                            guard weekStart > reach.earliest else { continue }
                            checks += 1
                            guard failure == nil else { continue }

                            let stepped = reach.step(weekStart, by: -1, calendar: calendar)
                            let was = WeekCalendar.startOfWeek(containing: weekStart, calendar: calendar)
                            let now = WeekCalendar.startOfWeek(containing: stepped, calendar: calendar)
                            if now == was {
                                failure = """
                                \(zone) firstWeekday=\(firstWeekday): enabled chevron, same week
                                  today       = \(Self.described(today, calendar))
                                  recordStart = \(Self.described(recordStart, calendar))
                                  earliest    = \(Self.described(reach.earliest, calendar))
                                  latest      = \(Self.described(reach.latest, calendar))
                                  weekStart   = \(Self.described(weekStart, calendar))
                                  stepped     = \(Self.described(stepped, calendar))
                                  both name   = \(Self.described(now, calendar))
                                """
                            }
                        }
                    }
                }
            }
        }

        #expect(failure == nil, "\(failure ?? "")")
        // The sweep swept something: a zone that silently produced no enabled
        // chevron would pass this test without asking it anything.
        #expect(checks > 50_000, "\(zone) made only \(checks) checks")
    }

    /// The exact case the sweep found, kept as a case rather than a range.
    ///
    /// Havana starts DST at midnight, so 2025-03-09 has no 00:00 — the clock
    /// goes from 23:59:59 to 01:00. `startOfDay` for that Sunday is therefore
    /// 01:00, and subtracting six days from it used to carry the 01:00 along:
    /// the week's start came out an hour after the Monday it names, while the
    /// same Monday reached from any other day of the week came out at 00:00.
    /// The pager compared one against the other, found `weekStart >
    /// earliest`, drew an enabled chevron, and stepped from 01:00 to 00:00 —
    /// a different `Date`, the same week, nothing on screen.
    @Test("A week with no midnight names its start the same as every other day does")
    func havanaSpringForward() {
        let calendar = Self.calendar("America/Havana", firstWeekday: 2)
        var components = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = 9
        let sunday = calendar.startOfDay(for: calendar.date(from: components) ?? .distantPast)
        // The premise: this really is a day that begins at one in the morning.
        #expect(calendar.component(.hour, from: sunday) == 1)

        let today = calendar.date(byAdding: .hour, value: 12, to: sunday) ?? sunday
        let weekStart = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let fromThursday = WeekCalendar.startOfWeek(
            containing: calendar.date(byAdding: .day, value: -3, to: today) ?? today,
            calendar: calendar
        )
        #expect(weekStart == fromThursday)
        #expect(calendar.startOfDay(for: weekStart) == weekStart)

        let reach = WeekReach.from(
            recordStart: calendar.date(byAdding: .day, value: -3, to: today),
            today: today,
            calendar: calendar
        )
        // One week of record, so the pager is at its floor and says so.
        #expect(reach.earliest == weekStart)
        #expect(!(weekStart > reach.earliest))
        #expect(reach.step(weekStart, by: -1, calendar: calendar) == weekStart)
    }

    /// The other half of the same zone's year: Havana ends DST at 01:00 by
    /// putting the clock back to 00:00, so 2026-11-01 has two midnights.
    /// `startOfDay` answers with the first and day arithmetic used to land on
    /// the second, so the week the pager was on and the week it could reach
    /// were an hour apart and named the same Sunday.
    @Test("A week with two midnights names its start once")
    func havanaFallBack() {
        let calendar = Self.calendar("America/Havana", firstWeekday: 1)
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 4
        let wednesday = calendar.startOfDay(for: calendar.date(from: components) ?? .distantPast)
        let today = calendar.date(byAdding: .hour, value: 23, to: wednesday) ?? wednesday

        let weekStart = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        let reach = WeekReach.from(
            recordStart: calendar.date(byAdding: .day, value: -3, to: today),
            today: today,
            calendar: calendar
        )
        #expect(reach.latest == weekStart)
        #expect(reach.earliest == weekStart)
        #expect(!(weekStart > reach.earliest))
    }
}
