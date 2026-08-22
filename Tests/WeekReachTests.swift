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
}
