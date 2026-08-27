import Foundation
import SwiftData
import Testing
@testable import Glow

/// #318: what a tap on the week grid costs, measured on the real write path
/// rather than assumed from reading it.
///
/// The tap-to-redraw pipeline is `WeeklyGridView.toggle` →
/// `HabitStore.toggleCompletion` → `commit()` (a synchronous `context.save()`;
/// the widget reload is already deferred) → SwiftUI re-deriving
/// `Habit.snapshots(of:within:)` for the whole grid on the next render. Every
/// *read* path is bounded to the days on screen (#135); the write path's day
/// lookup — `HabitStore.completions(of:on:)` — fetches every completion the
/// habit has and filters to the day in memory, and `toggleCompletion` runs it
/// twice per tap. This suite measures whether that difference shows at
/// realistic history sizes, and what the whole tap costs beside the render.
///
/// Same discipline as `HistoryProjectionTests`: every arm runs in this one
/// process, alternated, and the report is a median over eight rounds with the
/// first dropped — two separate runs measure the machine, not the change. The
/// store is on disk through `TestStore`, because a tap's save is a disk write
/// and an in-memory store would time everything but the part in question.
@Suite("Tap latency")
@MainActor
struct TapLatencyTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 17)

    private func seed(
        into context: ModelContext, habits habitCount: Int, days: Int
    ) throws -> [Habit] {
        var habits: [Habit] = []
        for index in 0..<habitCount {
            let habit = Habit(
                name: "Habit \(index)", icon: "📖", frequency: .daily,
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
        return habits
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

    /// One depth, measured: the two toggles a tap can be, the day lookup that
    /// runs inside each, and the whole-grid derivation the redraw runs after.
    private func measure(habits habitCount: Int, days: Int) throws -> String {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        let context = try TestStore.writable(at: url)
        let habits = try seed(into: context, habits: habitCount, days: days)
        let habit = try #require(habits.first)
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let bounds = week(of: today)

        var unmark: [Double] = []
        var mark: [Double] = []
        var dayFetch: [Double] = []
        var render: [Double] = []
        for round in 0..<9 {
            // `today` is seeded, so the first toggle of each round removes and
            // the second puts it back — every round starts from the same store.
            var start = ContinuousClock.now
            let removed = try store.toggleCompletion(for: habit, on: today)
            let unmarkTime = milliseconds(since: start)

            start = ContinuousClock.now
            let added = try store.toggleCompletion(for: habit, on: today)
            let markTime = milliseconds(since: start)

            // One pass of the same unbounded fetch `toggleCompletion` runs
            // twice — `count` calls `completions(of:on:)` and nothing else.
            start = ContinuousClock.now
            let count = store.count(for: habit, on: today)
            let fetchTime = milliseconds(since: start)

            // What the redraw derives: every row's week, plus the rest cut.
            start = ContinuousClock.now
            let snapshots = Habit.snapshots(of: habits, within: bounds, calendar: calendar)
            _ = RestCut.rows(snapshots, capacity: WidgetMetrics.largeRowCapacity)
            let renderTime = milliseconds(since: start)

            #expect(removed == .uncompleted && added == .completed)
            #expect(count == 1)
            #expect(snapshots.count == habitCount)
            if round > 0 {
                unmark.append(unmarkTime)
                mark.append(markTime)
                dayFetch.append(fetchTime)
                render.append(renderTime)
            }
        }

        return "L318 medians over 8 rounds, \(habitCount) habits x \(days) days, on disk: "
            + "toggle off \(median(unmark))ms, toggle on \(median(mark))ms, "
            + "day lookup \(median(dayFetch))ms, grid derivation \(median(render))ms"
    }

    /// The numbers behind #318, printed for the log at three history depths:
    /// the demo's ten weeks, two years, and the ten years #186 argued over.
    @Test("A tap's cost, against the redraw it triggers")
    func aTapAgainstItsRedraw() throws {
        let previous = WidgetRefresh.sink
        defer {
            WidgetRefresh.sink = previous
            WidgetRefresh.flush()
        }
        // The reload itself is not this measurement's: `commit()` defers it to
        // the next turn of the main actor, so a tap never waits on WidgetKit.
        WidgetRefresh.sink = { _ in }

        for days in [70, 730, 3650] {
            print(try measure(habits: 12, days: days))
        }
    }
}
