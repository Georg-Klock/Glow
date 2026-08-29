import Foundation
import SwiftData
import Testing
@testable import Glow

@Suite("Week preferences", .serialized)
struct WeekPreferencesTests {
    /// One implementation, in `TestSupport`, shared by every suite that sets
    /// these — this used to be four near-copies. See `TestPreferences`.
    private func withPreferences(
        firstWeekday: Int? = nil,
        restDay: Int? = nil,
        _ body: () throws -> Void
    ) rethrows {
        try TestPreferences.withWeek(firstWeekday: firstWeekday, restDay: restDay, body)
    }

    @Test("Monday by default, not whatever the locale says")
    func defaultsToMonday() {
        // Locale would answer Sunday in the US, and this is not a formatting
        // choice: it decides which seven days a weekly goal is counted over.
        #expect(WeekPreferences.defaultFirstWeekday == WeekPreferences.monday)
    }

    @Test("The week start moves the columns", arguments: [1, 2, 3, 7])
    func weekStartMovesColumns(first: Int) {
        withPreferences(firstWeekday: first) {
            let calendar = WeekCalendar.calendar
            #expect(calendar.firstWeekday == first)

            let week = WeekCalendar.week(containing: Date(), calendar: calendar)
            #expect(week.days.count == 7)
            #expect(calendar.component(.weekday, from: week.start) == first)
        }
    }

    @Test("Weekday initials follow the week start")
    func initialsRotate() {
        withPreferences(firstWeekday: WeekPreferences.sunday) {
            let sundayFirst = WeekCalendar.weekdayInitials(calendar: WeekCalendar.calendar)
            WeekPreferences.firstWeekday = WeekPreferences.monday
            let mondayFirst = WeekCalendar.weekdayInitials(calendar: WeekCalendar.calendar)

            #expect(sundayFirst.count == 7)
            // The same seven letters, rotated by one — not a different list.
            #expect(Array(sundayFirst.dropFirst()) + [sundayFirst[0]] == mondayFirst)
        }
    }

    @Test("Out-of-range week starts clamp instead of producing a silent wrong week")
    func weekdayClamps() {
        #expect(WeekPreferences.clampWeekday(0) == 1)
        #expect(WeekPreferences.clampWeekday(9) == 7)
        #expect(WeekPreferences.clampWeekday(4) == 4)
    }

    @Test("No rest day by default")
    func noRestDayByDefault() {
        withPreferences(restDay: nil) {
            #expect(WeekPreferences.restDay == nil)
        }
    }

    @Test("Retiring the rest day clears one an older build stored")
    func retirementClearsAStoredDay() {
        // **The half of #390 that the Settings diff cannot do.** Taking the
        // toggle and the picker out stops anyone setting a rest day; it does
        // nothing about an install that already had one, which would go on
        // resting on that day with nothing anywhere to turn it off.
        // `GlowApp.init` calls this on every launch.
        withPreferences(restDay: WeekPreferences.sunday) {
            #expect(WeekPreferences.restDay == WeekPreferences.sunday)
            WeekPreferences.retireRestDay()
            #expect(WeekPreferences.restDay == nil)
            // Idempotent, which is why it needs no "has migrated" flag: the
            // second launch removes an absent key and that is all.
            WeekPreferences.retireRestDay()
            #expect(WeekPreferences.restDay == nil)
        }
    }

    @Test("A rest day is never open and never missed")
    func restDayIsNeitherOpenNorMissed() {
        let calendar = TestCalendar.monday
        // Wednesday of the week beginning Monday 2026-08-17.
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        let row = WeekGrid.slots(
            for: .fixture(), in: week, today: today, editing: .todayOnly,
            restDay: calendar.component(.weekday, from: week.days[0]), calendar: calendar
        )
        // Monday is the rest day and already gone: it would be a miss
        // otherwise, and a miss is exactly what a rest day is not. It is
        // not an upcoming socket either — see `restDayDrawsNothing`.
        #expect(row[0].state == .rest)
        #expect(row[0].mark == .rest)
        #expect(row[1].state == .missed)
    }

    @Test("A rest day that is today has nothing to tap")
    func restDayTodayIsNotOpen() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        let row = WeekGrid.slots(
            for: .fixture(), in: week, today: today, editing: .todayOnly,
            restDay: calendar.component(.weekday, from: today), calendar: calendar
        )
        #expect(row[2].state == .rest)
        #expect(row[2].mark == .rest)
        #expect(!row.contains { $0.state == .open })
        #expect(row.allSatisfy { !$0.isTappable })
    }

    @Test("A completion already stored on a rest day still counts, and is not drawn")
    func restDayCompletionsCount() {
        // Both halves of the rule in one test, because they are one rule and
        // asserting either alone lets the other rot: the record survives —
        // nothing is deleted and nothing stops counting — and the week grid
        // stops drawing it, because the grid says what is open and a rest day
        // has nothing open on it. This reverses one clause of #39; see
        // docs/decisions.md.
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let monday = week.days[0]

        let restDay = calendar.component(.weekday, from: monday)
        let habit = HabitSnapshot.fixture(completedDays: [monday])
        let row = WeekGrid.slots(
            for: habit, in: week, today: today, editing: .todayOnly,
            restDay: restDay, calendar: calendar
        )
        // Not drawn: rest wins over the completion.
        #expect(row[0].state == .rest)
        #expect(row[0].mark == .rest)
        // Still counts. Asserted through a frequency row over the same
        // week rather than by re-reading `completedDays`, so "counts but
        // is not drawn" is a claim about the grid rather than about the
        // fixture.
        let weekly = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [monday]
        )
        let spans = WeekGrid.slots(
            for: weekly, in: week, today: today, editing: .todayOnly,
            restDay: restDay, calendar: calendar
        )
        #expect(spans.count { $0.state == .filled } == 1)
        #expect(habit.completedDays.contains(monday))
    }

    @Test("A rest day draws nothing, whichever way it faces")
    func restDayDrawsNothing() {
        // Past, future and today. Before #72 these drew a \u{2715}, a socket and a
        // ring respectively; a socket says one is coming, and on a rest day
        // none is.
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        for index in [0, 2, 5] {
            let weekday = calendar.component(.weekday, from: week.days[index])
            let row = WeekGrid.slots(
                for: .fixture(), in: week, today: today, editing: .todayOnly,
                restDay: weekday, calendar: calendar
            )
            #expect(row[index].mark == .rest, "column \(index) should draw nothing")
            #expect(row.count { $0.mark == .rest } == 1)
        }
    }

    @Test("No rest day leaves every column drawing something")
    func noRestDayDrawsNoHole() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        let row = WeekGrid.slots(
            for: .fixture(), in: week, today: today, editing: .todayOnly,
            restDay: nil, calendar: calendar
        )
        #expect(!row.contains { $0.mark == .rest })
    }

    @Test("A rest-day today opens nothing on a frequency row")
    func restDayStopsFrequencyRow() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        // The goal is nowhere near met, and still nothing is open: the
        // pill that would be waits, unlit, for a day that allows it.
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
        let row = WeekGrid.slots(
            for: habit, in: week, today: today, editing: .todayOnly,
            restDay: calendar.component(.weekday, from: today), calendar: calendar
        )
        #expect(!row.contains { $0.state == .open })
        #expect(row.allSatisfy { !$0.isTappable })
    }

    @Test("A rest-day today withholds the undo too")
    func restDayWithholdsUndo() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        // Today already holds a completion — stored before the rest day
        // was set. It still draws filled, and it cannot be un-logged.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [today]
        )
        let row = WeekGrid.slots(
            for: habit, in: week, today: today, editing: .todayOnly,
            restDay: calendar.component(.weekday, from: today), calendar: calendar
        )
        #expect(row.contains { $0.state == .filled })
        #expect(row.allSatisfy { !$0.isTappable })
    }

    @Test("A rest-day today stops the spans as well")
    func restDayStopsSpans() {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)
        let week = WeekCalendar.week(containing: today, calendar: calendar)

        let restDay = calendar.component(.weekday, from: today)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
        let spans = WeekSpans.spans(
            for: habit, in: week, today: today, target: 3,
            editing: .todayOnly, restDay: restDay, calendar: calendar
        )
        // The geometry holds — still three spans dividing the week — but
        // nothing is open and nothing takes a tap.
        #expect(spans.count == 3)
        #expect(!spans.contains { $0.state == .open })
        #expect(spans.allSatisfy { !$0.isTappable })

        // The met goal's whole-week span loses its undo the same way.
        let met = HabitSnapshot.fixture(
            frequency: .timesPerWeek(1), completedDays: [today]
        )
        let metSpans = WeekSpans.spans(
            for: met, in: week, today: today, target: 1,
            editing: .todayOnly, restDay: restDay, calendar: calendar
        )
        #expect(metSpans.allSatisfy { !$0.isTappable })
    }

    @Test("The store refuses a rest-day write in both directions")
    @MainActor
    func restDayRefusesWrites() throws {
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)

        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        // The store takes its rest day the way it takes its calendar (#181),
        // so the refusal can be asserted without setting a process-wide
        // preference and hoping nothing else reads it.
        let store = HabitStore(
            context: context, calendar: calendar,
            restDay: calendar.component(.weekday, from: today)
        )
        let habit = try store.addHabit(name: "Run", icon: "🏃", frequency: .daily)

        // This is the write path `MarkHabitIntent` calls, so the widget
        // process is refused here too — a stale widget can still offer the
        // button, and the store rather than the surface is what says no.
        #expect(try store.toggleCompletion(for: habit, on: today) == .refused)
        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)

        // A completion already stored on the rest day cannot be un-logged
        // on it either: refused, and the record stays.
        let stored = Completion(day: today, habit: habit)
        context.insert(stored)
        habit.completions?.append(stored)
        try context.save()
        #expect(try store.toggleCompletion(for: habit, on: today) == .refused)
        #expect(try context.fetch(FetchDescriptor<Completion>()).count == 1)

        // The day beside it writes as ever.
        let thursday = TestCalendar.date(2026, 8, 20)
        #expect(try store.toggleCompletion(for: habit, on: thursday) == .completed)
    }

    @Test("The store reads the rest day itself when it is not told one")
    @MainActor
    func storeDefaultsToTheStoredRestDay() throws {
        // The other half of #181: the *store* is a boundary and may read the
        // preference, and it must — the refusal exists because a surface can
        // outlive the setting it was rendered under, so a rest day supplied by
        // that stale surface would make the guard agree with it. Every real
        // caller builds a store per write and so re-reads it here.
        let calendar = TestCalendar.monday
        let today = TestCalendar.date(2026, 8, 19)

        try withPreferences(restDay: calendar.component(.weekday, from: today)) {
            let container = try ModelContainer(
                for: Habit.self, Completion.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let store = HabitStore(context: context, calendar: calendar)
            let habit = try store.addHabit(name: "Run", icon: "🏃", frequency: .daily)
            #expect(try store.toggleCompletion(for: habit, on: today) == .refused)
        }
    }
}
