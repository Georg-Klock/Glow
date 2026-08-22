import Foundation
import SwiftData
import Testing
@testable import Glow

/// #145: reading a habit's completions crashed when another context had
/// deleted one.
///
/// **Two in-process contexts are the same shape as two processes**, without the
/// App Group boundary — which is what makes a cross-process crash reproducible
/// in a unit test at all. The app's context and the widget intents' context are
/// two independent `ModelContext`s over one store; here they are two over one
/// container.
///
/// Before the fix these trip `_InvalidFutureBackingData`, a `precondition`
/// inside SwiftData. That is a **hard trap, not a thrown error** — the process
/// dies rather than the test failing, so a run against the old code aborts the
/// suite instead of reporting. Worth knowing before anyone reverts to check.
@Suite("Stale completions")
@MainActor
struct StaleCompletionTests {
    private let calendar = TestCalendar.monday
    private let monday = TestCalendar.date(2026, 8, 17)
    private let tuesday = TestCalendar.date(2026, 8, 18)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A habit with two logged days, plus a second context over the same store.
    private func twoContexts(
        _ body: (Habit, ModelContext, ModelContext) throws -> Void
    ) throws {
        let container = try makeContainer()
        let app = ModelContext(container)
        let store = HabitStore(context: app, calendar: calendar)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        try store.toggleCompletion(for: habit, on: monday)
        try store.toggleCompletion(for: habit, on: tuesday)

        let widget = ModelContext(container)
        try body(habit, app, widget)
    }

    /// Deletes one of this habit's completions through the other context, the
    /// way an un-complete tap from the widget's process does.
    private func deleteOneCompletion(of habit: Habit, in other: ModelContext) throws {
        let habitID = habit.id
        let descriptor = FetchDescriptor<Completion>(
            predicate: #Predicate { $0.habit?.id == habitID }
        )
        let found = try other.fetch(descriptor)
        let doomed = try #require(found.first)
        other.delete(doomed)
        try other.save()
    }

    @Test("A completion deleted elsewhere does not crash the counts")
    func countsSurviveAnOutsideDelete() throws {
        try twoContexts { habit, _, widget in
            try deleteOneCompletion(of: habit, in: widget)
            // The line that crashed: `.day` on a row that is no longer there.
            let counts = habit.completionCounts
            #expect(counts.values.reduce(0, +) == 1)
        }
    }

    @Test("Nor the days")
    func daysSurviveAnOutsideDelete() throws {
        try twoContexts { habit, _, widget in
            try deleteOneCompletion(of: habit, in: widget)
            #expect(habit.completedDays.count == 1)
        }
    }

    @Test("Nor a snapshot, which is what the grid actually calls")
    func snapshotSurvivesAnOutsideDelete() throws {
        // `WeeklyGridView.grid` maps `snapshot()` over every habit on every
        // recompute, which is where all three crash reports landed.
        try twoContexts { habit, _, widget in
            try deleteOneCompletion(of: habit, in: widget)
            let snapshot = habit.snapshot()
            #expect(snapshot.name == "Read")
            #expect(snapshot.completionCounts.values.reduce(0, +) == 1)
        }
    }

    @Test("Every completion deleted elsewhere leaves an empty habit, not a crash")
    func allDeletedIsEmpty() throws {
        try twoContexts { habit, _, widget in
            try deleteOneCompletion(of: habit, in: widget)
            try deleteOneCompletion(of: habit, in: widget)
            #expect(habit.completionCounts.isEmpty)
            #expect(habit.completedDays.isEmpty)
        }
    }

    @Test("A completion added elsewhere is seen, not missed")
    func additionsAreSeenToo() throws {
        // The same cache staleness in the other direction. It never crashed, so
        // it was never noticed — a fetch fixes both.
        try twoContexts { habit, _, widget in
            let habitID = habit.id
            let match = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == habitID })
            let theirs = try #require(try widget.fetch(match).first)
            let wednesday = TestCalendar.date(2026, 8, 19)
            widget.insert(Completion(day: wednesday, habit: theirs))
            try widget.save()

            #expect(habit.completedDays.count == 3)
            #expect(habit.completedDays.contains(wednesday))
        }
    }

    @Test("A habit with no context still reads its own array")
    func uninsertedHabitStillWorks() {
        // A model object built but never inserted has no context to ask, and
        // the array is the only truth there is. Fixtures rely on this.
        let habit = Habit(
            name: "Read", icon: "📖", frequency: .timesPerWeek(3),
            createdAt: monday, sortOrder: 0
        )
        habit.completions = [Completion(day: monday, habit: habit)]
        #expect(habit.completedDays == [monday])
    }
}
