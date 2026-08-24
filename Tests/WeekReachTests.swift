import Foundation
import Testing
@testable import Glow

/// How far back the week view may be paged.
///
/// The rule is one sentence — as far back as the record reaches — and every
/// test here is one clause of it. It used to have a second clause, *capped at
/// twelve weeks*, and #186 removed it; the tests that asserted the cap are the
/// tests that now assert its absence, at a depth no cap would survive.
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

    /// The clause that was the cap, asserted as its absence (#186).
    ///
    /// Twelve, thirteen and a quarter of a year were the interesting values
    /// while there was a cap at twelve; a decade is the value that could not
    /// pass any cap this app has ever had.
    @Test("A record of years reaches back years", arguments: [12, 13, 52, 104, 260, 522])
    func longRecordReachesItsOwnStart(back: Int) {
        let start = calendar.date(byAdding: .day, value: -7 * back, to: today)!
        let reach = reach(recordStart: start)

        #expect(weeksBack(reach) == back)
        #expect(reach.earliest == calendar.date(byAdding: .day, value: -7 * back, to: thisWeek))
        #expect(reach.contains(reach.earliest))
    }

    /// **The sentinel is not this type's to refuse** (#186).
    ///
    /// `Habit.createdAt` defaults to `.distantPast` for every row written
    /// before the column existed. The cap used to make that harmless here, by
    /// making everything harmless here; with the cap gone this function does
    /// exactly what it is told, and a reach back to the year 1 is what being
    /// told the record starts there *means*. The guard is one layer down, in
    /// `HabitStore.earliestRecordedDay`, which never hands one over — see
    /// `PersistenceTests.unknownCreationDoesNotStartTheRecord`.
    @Test("A record start of `.distantPast` reaches the year 1, so the store never sends one")
    func theSentinelIsNotThisTypesToRefuse() {
        let reach = reach(recordStart: .distantPast)

        #expect(reach.earliest < calendar.date(from: DateComponents(year: 2, month: 1, day: 1))!)
        #expect(weeksBack(reach) > 100_000)
        // And it is still a week start, so the pager's comparisons still
        // compare like with like — an unbounded reach is not a malformed one.
        let floor = WeekCalendar.startOfWeek(containing: reach.earliest, calendar: calendar)
        #expect(floor == reach.earliest)
    }

    @Test("The demo's ten weeks are all reachable")
    func theDemoIsReachableEndToEnd() {
        // `SeededHistory.weeks` of invented past, and the pager has to reach
        // the whole of it or the demo shows a week the app cannot open. This
        // used to be a comparison against the cap, which had to clear ten;
        // nothing encodes that constraint any more, so it is asserted the only
        // way left — by reaching the demo's own first week.
        let seeded = calendar.date(byAdding: .day, value: -7 * SeededHistory.weeks, to: today)!
        let reach = reach(recordStart: seeded)

        #expect(weeksBack(reach) == SeededHistory.weeks)
        let first = calendar.date(byAdding: .day, value: -7 * SeededHistory.weeks, to: thisWeek)!
        #expect(reach.contains(first))
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
        // Five years of record, week by week: the loop that used to run to the
        // cap runs to the record instead.
        let years = 5 * 52
        let reach = reach(recordStart: calendar.date(byAdding: .day, value: -7 * years, to: today)!)

        for back in 0...years {
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
    /// How deep the chevron sweep below enumerates, in weeks.
    ///
    /// It was `WeekReach.maximumWeeksBack` — the cap, which the sweep had to
    /// cover and one week past. #186 removed the cap and this number stayed,
    /// because the sweep's value is its *density* over week boundaries and
    /// clock changes rather than its depth, and holding it fixed keeps the
    /// counts in the comment below comparable to the ones the fix was measured
    /// against. Depth is `theDeepPagerWalksToTheStart`'s job.
    static let sweptWeeks = 12

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
    ///
    /// **Its parameters are unchanged by #186 on purpose.** The second record
    /// length and the enumeration depth used to be `WeekReach.maximumWeeksBack`
    /// and are now `sweptWeeks`, the same twelve, so the counts above are still
    /// the counts this sweep takes and the 166 failures are still comparable to
    /// them. Twelve is now nothing but a sweep depth: the reach it is swept
    /// against is bounded by the record and not by it, and the depth the cap's
    /// removal actually opened up is swept by `theDeepPagerWalksToTheStart`.
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

                    // A record a few days old and one twelve weeks old: the
                    // floor is the current week in the first and a week well
                    // behind it in the second.
                    for daysOfRecord in [3, 7 * Self.sweptWeeks] {
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
                        for back in 0...(Self.sweptWeeks + 1) {
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

    // MARK: - The depth the cap used to hide (#186)

    /// Days to stand on, spread across two years, with both of Havana's
    /// midnight clock changes among them.
    static let deepDays = [
        (2025, 1, 15), (2025, 3, 9), (2025, 4, 20), (2025, 6, 1),
        (2025, 9, 7), (2025, 11, 2), (2026, 1, 1), (2026, 3, 8),
        (2026, 5, 17), (2026, 8, 19), (2026, 11, 1), (2026, 12, 31),
    ]

    /// **The pager reaches the start of the record, however far away it is**
    /// (#186).
    ///
    /// With a cap this was a walk of at most twelve steps and the sweep above
    /// covered all of it. Uncapped the walk is as long as the record, so it is
    /// walked: from the current week, step back for as long as the chevron is
    /// enabled, and require every step to land on a *different* week — #242's
    /// invariant, asserted over the whole descent rather than near the top of
    /// it. Then require the walk to have taken exactly one step per week of
    /// record, to have arrived at `reach.earliest`, and to stop there with the
    /// chevron dim.
    ///
    /// Six years of record — 313 weeks — over the same nine zones, three week
    /// starts and twelve days spread across two years: 11,268 steps a zone.
    @Test("A deep pager walks all the way to the start", arguments: WeekReachTests.zones)
    func theDeepPagerWalksToTheStart(zone: String) {
        let weeksOfRecord = 313
        var walks = 0
        var steps = 0
        var failure: String?

        for firstWeekday in [1, 2, 7] {
            let calendar = Self.calendar(zone, firstWeekday: firstWeekday)
            for (year, month, day) in Self.deepDays {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                guard let midnight = calendar.date(from: components) else { continue }
                // Midday, so "today" is an instant inside its day whatever the
                // clock did at midnight.
                guard let today = calendar.date(
                    byAdding: .hour, value: 12, to: calendar.startOfDay(for: midnight)
                ) else { continue }
                guard let recordStart = calendar.date(
                    byAdding: .day, value: -7 * weeksOfRecord, to: today
                ) else { continue }
                let reach = WeekReach.from(
                    recordStart: recordStart, today: today, calendar: calendar
                )

                var cursor = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
                var walked = 0
                // The pager's own `.disabled(weekStart <= reach.earliest)`, and
                // a bound so a step that stopped moving is a failure rather
                // than a hang.
                while cursor > reach.earliest, walked <= weeksOfRecord {
                    let stepped = reach.step(cursor, by: -1, calendar: calendar)
                    let now = WeekCalendar.startOfWeek(containing: stepped, calendar: calendar)
                    if now == WeekCalendar.startOfWeek(containing: cursor, calendar: calendar) {
                        failure = failure ?? """
                        \(zone) firstWeekday=\(firstWeekday): enabled chevron, same week
                          today     = \(Self.described(today, calendar))
                          earliest  = \(Self.described(reach.earliest, calendar))
                          weekStart = \(Self.described(cursor, calendar))
                          stepped   = \(Self.described(stepped, calendar))
                        """
                        break
                    }
                    cursor = stepped
                    walked += 1
                    steps += 1
                }
                walks += 1

                if failure == nil, walked != weeksOfRecord {
                    failure = """
                    \(zone) firstWeekday=\(firstWeekday): walked \(walked) weeks of \(weeksOfRecord)
                      today    = \(Self.described(today, calendar))
                      earliest = \(Self.described(reach.earliest, calendar))
                      stopped  = \(Self.described(cursor, calendar))
                    """
                }
                if failure == nil, cursor != reach.earliest {
                    failure = """
                    \(zone) firstWeekday=\(firstWeekday): the walk did not arrive at the floor
                      earliest = \(Self.described(reach.earliest, calendar))
                      stopped  = \(Self.described(cursor, calendar))
                    """
                }
                // At the floor the chevron is dim, and stepping is a no-op.
                if failure == nil, reach.step(cursor, by: -1, calendar: calendar) != cursor {
                    failure = "\(zone) firstWeekday=\(firstWeekday): the floor moved when pushed"
                }
            }
        }

        #expect(failure == nil, "\(failure ?? "")")
        #expect(walks == 36)
        #expect(steps == 36 * weeksOfRecord, "\(zone) took \(steps) steps")
    }
}
