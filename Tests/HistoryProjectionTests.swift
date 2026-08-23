import Foundation
import SwiftData
import Testing
@testable import Glow

/// #135: what a render actually has to read.
///
/// **Both arms of every comparison run in this one process, alternated, and the
/// report is a median.** Two separate `Tools/test.sh` runs are not comparable —
/// `seed` varied 34ms to 103ms between runs with unchanged code — so a
/// before/after taken from two runs measures the machine, not the change. See
/// `docs/decisions.md`.
@Suite("History projection")
@MainActor
struct HistoryProjectionTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 17)

    private func makeStore(habits habitCount: Int, days: Int) throws -> (ModelContext, [Habit]) {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var habits: [Habit] = []
        for index in 0..<habitCount {
            let habit = Habit(
                name: "Habit \(index)", icon: "📖", frequency: .timesPerWeek(3),
                createdAt: TestCalendar.date(2024, 1, 1), sortOrder: index
            )
            context.insert(habit)
            habits.append(habit)
            for offset in 0..<days {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today)
                else { continue }
                context.insert(Completion(day: day, habit: habit, calendar: calendar))
            }
        }
        try context.save()
        return (context, habits)
    }

    private func week(of day: Date) -> ClosedRange<DayID> {
        let week = WeekCalendar.week(containing: day, calendar: calendar)
        return DayID(week.days[0], calendar: calendar)...DayID(week.days[6], calendar: calendar)
    }

    private func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        Double((ContinuousClock.now - start).components.attoseconds) / 1e15
    }

    // MARK: - Correctness

    @Test("A bounded pass agrees with the whole history, inside its bounds")
    func boundedAgreesWithWhole() throws {
        let (_, habits) = try makeStore(habits: 3, days: 400)
        let bounds = week(of: today)
        let whole = Habit.snapshots(of: habits, calendar: calendar)
        let bounded = Habit.snapshots(of: habits, within: bounds, calendar: calendar)

        for (full, part) in zip(whole, bounded) {
            let expected = full.completionCounts.filter {
                bounds.contains(DayID($0.key, calendar: calendar))
            }
            #expect(part.completionCounts == expected)
            #expect(!expected.isEmpty)
            #expect(part.completionCounts.count < full.completionCounts.count)
        }
    }

    /// A range wide enough to hold everything gives back everything, so the
    /// bounded read is the same read with a smaller mouth.
    @Test("A pass wide enough to hold the history agrees with one fetch per habit")
    func aWidePassAgreesWithPerHabit() throws {
        let (_, habits) = try makeStore(habits: 4, days: 40)
        let wide = DayID(year: 2000, month: 1, day: 1)...DayID(year: 2099, month: 12, day: 31)
        let mapped = habits.map { $0.snapshot(calendar: calendar) }
        let shared = Habit.snapshots(of: habits, within: wide, calendar: calendar)
        #expect(mapped == shared)
    }

    /// The rows the day-identity backfill has not reached have no `dayKey` at
    /// all, so a predicate on the key alone would drop exactly the rows #130 is
    /// about. They come back whatever the range and are settled in memory.
    @Test("A row with no day key is counted inside the range and not outside it")
    func legacyRowsSurviveTheRange() throws {
        let (context, habits) = try makeStore(habits: 1, days: 0)
        let habit = try #require(habits.first)
        let inside = Completion(day: today, habit: habit, calendar: calendar)
        let outside = Completion(
            day: TestCalendar.date(2026, 1, 5), habit: habit, calendar: calendar
        )
        // Exactly what a store written before the column looks like.
        inside.dayKey = ""
        outside.dayKey = ""
        context.insert(inside)
        context.insert(outside)
        try context.save()

        let counts = Habit.dayCounts(of: habits, within: week(of: today), in: context)
        let days = try #require(counts[habit.id])
        #expect(days == [DayID(today, calendar: calendar): 1])
    }

    @Test("Habits outside the list are not returned")
    func otherHabitsAreDropped() throws {
        let (context, habits) = try makeStore(habits: 3, days: 10)
        let counts = Habit.dayCounts(of: [habits[0]], in: context)
        #expect(Set(counts.keys) == [habits[0].id])
    }

    @Test("A habit with no context falls back to the rows it carries")
    func fixturesStillProject() {
        let habit = Habit(
            name: "Read", icon: "📖", frequency: .daily,
            createdAt: today, sortOrder: 0
        )
        habit.completions = [Completion(day: today, habit: habit, calendar: calendar)]
        let snapshots = Habit.snapshots(of: [habit], calendar: calendar)
        #expect(snapshots.first?.completedDays == [today])
    }

    // MARK: - What the surfaces draw

    // The bounded read is only safe because nothing week-, month- or
    // year-shaped asks about a day outside what it draws. These assert that
    // against the real drawing rules rather than against a reading of them:
    // whole history in one side, the bounded read in the other, same output.

    @Test("A week's worth draws the same week as the whole history")
    func boundedWeekDrawsTheSame() throws {
        // Sunday rests, stated in each call below rather than pinned in the
        // process (#181). The week start still is pinned: `WeekCalendar` reads
        // that one, and that is not this change.
        let restDay = WeekPreferences.sunday
        try TestPreferences.withWeek(firstWeekday: 2) {
            let (_, habits) = try makeStore(habits: 3, days: 400)
            let shown = WeekCalendar.week(containing: today, calendar: calendar)
            let whole = habits.map { $0.snapshot(calendar: calendar) }
            let bounded = Habit.snapshots(
                of: habits, within: shown.dayIDs(in: calendar), calendar: calendar
            )

            for (full, part) in zip(whole, bounded) {
                #expect(
                    WeekGrid.slots(
                        for: part, in: shown, today: today, editing: .todayOnly,
                        restDay: restDay, calendar: calendar
                    ) == WeekGrid.slots(
                        for: full, in: shown, today: today, editing: .todayOnly,
                        restDay: restDay, calendar: calendar
                    )
                )
                #expect(
                    WeekSpans.spans(
                        for: part, in: shown, today: today, target: 3,
                        editing: .todayOnly, restDay: restDay, calendar: calendar
                    ) == WeekSpans.spans(
                        for: full, in: shown, today: today, target: 3,
                        editing: .todayOnly, restDay: restDay, calendar: calendar
                    )
                )
                #expect(
                    WeekDots.columns(
                        for: part, in: shown, restDay: restDay, calendar: calendar
                    ) == WeekDots.columns(
                        for: full, in: shown, restDay: restDay, calendar: calendar
                    )
                )
                #expect(
                    GoalMet.justMet(habit: part, in: shown)
                        == GoalMet.justMet(habit: full, in: shown)
                )
            }
        }
    }

    @Test("A month's worth draws the same month as the whole history")
    func boundedMonthDrawsTheSame() throws {
        let restDay = WeekPreferences.sunday
        try TestPreferences.withWeek(firstWeekday: 2) {
            let (_, habits) = try makeStore(habits: 2, days: 400)
            let days = try #require(MonthGrid.dayRange(containing: today, calendar: calendar))
            let whole = habits.map { $0.snapshot(calendar: calendar) }
            let bounded = Habit.snapshots(of: habits, within: days, calendar: calendar)

            for (full, part) in zip(whole, bounded) {
                #expect(
                    MonthGrid.cells(
                        for: part, today: today, restDay: restDay, calendar: calendar
                    ) == MonthGrid.cells(
                        for: full, today: today, restDay: restDay, calendar: calendar
                    )
                )
            }
        }
    }

    @Test("A year's worth fills the same year as the whole history")
    func boundedYearFillsTheSame() throws {
        let restDay = WeekPreferences.sunday
        try TestPreferences.withWeek(firstWeekday: 2) {
            let (_, habits) = try makeStore(habits: 2, days: 500)
            let weeks = (0..<52).map { index -> Week in
                let start = calendar.date(
                    byAdding: .day, value: -7 * index, to: today
                ) ?? today
                return WeekCalendar.week(containing: start, calendar: calendar)
            }
            let first = try #require(weeks.last).days[0]
            let last = try #require(weeks.first).days[6]
            let whole = habits.map { $0.snapshot(calendar: calendar) }
            let bounded = Habit.snapshots(
                of: habits,
                within: DayID.range(from: first, through: last, calendar: calendar),
                calendar: calendar
            )

            for week in weeks {
                #expect(
                    YearHistory.fills(
                        in: week, habits: bounded, today: today,
                        restDay: restDay, calendar: calendar
                    ) == YearHistory.fills(
                        in: week, habits: whole, today: today,
                        restDay: restDay, calendar: calendar
                    )
                )
            }
        }
    }

    /// The month grid draws whole weeks, so its range has to run past both ends
    /// of the month. A range that stopped at the month's own edges would be
    /// short by up to twelve days and the marks in them would go missing.
    @Test("A month's range covers the weeks the month grid draws")
    func monthRangeCoversWholeWeeks() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            // 1 September 2026 is a Tuesday and 30 September a Wednesday, so
            // both ends of this month spill into a neighbouring one.
            let september = TestCalendar.date(2026, 9, 15)
            let days = try #require(MonthGrid.dayRange(containing: september, calendar: calendar))
            #expect(days.lowerBound == DayID(year: 2026, month: 8, day: 31))
            #expect(days.upperBound == DayID(year: 2026, month: 10, day: 4))
        }
    }

    // MARK: - The measurement

    /// Twelve habits with two years each: 8,760 completions, which is a heavier
    /// history than the app can currently produce and the point at which the
    /// difference is about the fetch rather than about the noise.
    @Test("A week costs a week, not a history")
    func aWeekCostsAWeek() throws {
        let (context, habits) = try makeStore(habits: 12, days: 730)
        let bounds = week(of: today)

        var perHabit: [Double] = []
        var onePass: [Double] = []
        var bounded: [Double] = []
        // Alternated, and the first round dropped: opening the store is paid
        // once and whichever arm ran first would wear it.
        for round in 0..<9 {
            var start = ContinuousClock.now
            let a = habits.map { $0.snapshot(calendar: calendar) }
            let aTime = milliseconds(since: start)

            // The middle arm is the shape that looks like the obvious fix —
            // one query instead of n — and it is the one this suite exists to
            // rule out. Called at the counts, not through `snapshots`, because
            // `snapshots` now declines to take it.
            start = ContinuousClock.now
            let b = Habit.dayCounts(of: habits, in: context)
            let bTime = milliseconds(since: start)

            start = ContinuousClock.now
            let c = Habit.snapshots(of: habits, within: bounds, calendar: calendar)
            let cTime = milliseconds(since: start)

            #expect(a.count == b.count && b.count == c.count)
            if round > 0 {
                perHabit.append(aTime)
                onePass.append(bTime)
                bounded.append(cTime)
            }
        }

        let whole = median(perHabit)
        let shared = median(onePass)
        let sevenDays = median(bounded)
        print(
            "L135 medians over 8 rounds, 12 habits x 730 days: "
                + "per-habit whole history \(whole)ms, one pass whole history \(shared)ms, "
                + "one pass bounded to a week \(sevenDays)ms"
        )
        // The claim this suite exists to hold: a surface that draws seven days
        // stops paying for every day there has ever been. Stated as a factor
        // rather than as a millisecond count, because the machine varies and
        // the shape of the win does not.
        #expect(sevenDays * 10 < whole)
    }
}
