import Foundation
import SwiftData
import Testing
@testable import Glow

/// The writers stop reading the cached relationship array.
///
/// #145 made every *reader* of `Habit.completions` fetch instead, because the
/// array is the rows this context fetched once and a peer container — the
/// widget's tap intent — can delete one of them without telling anyone.
/// Reading a stored attribute on that element is `_InvalidFutureBackingData`,
/// a precondition inside SwiftData: the process dies rather than the test
/// failing. #318 took the by-hand mutation off the tap; the writers that
/// removed a demo, reset to the defaults and delete a habit kept it, and each
/// read the array on the way through. The demo's removal is gone with the demo
/// (#628); the launch purge that replaced it is held to the same standard.
///
/// Every test here is the same shape as `StaleCompletionTests`: seed through
/// the app's context, delete one row through a peer, then run the writer
/// through the app's context. Against the old code these do not fail, they
/// abort the host — measured: three `SwiftData/BackingData.swift` fatal
/// errors in one run, one per writer. A run that dies here rather than
/// reports is the old code.
///
/// **Deleting a habit is deliberately not among them.** Its own by-hand read
/// is gone with the others, and with the array left unread the path is
/// clean — but a test that reads the array first, the way this file's
/// fixture does, still dies: SwiftData's cascade walks the cached array on
/// `context.delete(habit)` and meets the dead element itself, below anything
/// this code can reach. That is recorded in `docs/decisions.md` rather than
/// left as a test the host cannot survive.
@Suite("Stale writers")
@MainActor
struct StaleWriterTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Isolated defaults, so the purge's key removals touch nothing shared.
    private func defaults() -> UserDefaults {
        let suite = "stale-writer-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Rows a demo invented, written the way it wrote them: stamped with a
    /// session id, on days before today.
    private func insertInvented(for habit: Habit, into context: ModelContext) throws {
        let session = UUID()
        for offset in 1...3 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            context.insert(Completion(day: day, habit: habit, demoSessionID: session, calendar: calendar))
        }
        try context.save()
    }

    /// The app's context with invented rows and one real one, and one invented
    /// row deleted behind its back through a peer context — the widget's tap,
    /// in one process.
    private func seededWithOnePeerDelete()
        throws -> (container: ModelContainer, app: ModelContext, habit: Habit)
    {
        let container = try container()
        let app = ModelContext(container)
        let store = HabitStore(context: app, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .daily)
        try insertInvented(for: habit, into: app)
        #expect(try store.addCompletion(for: habit, on: today) == 1)
        // The array is populated on this side, which is the precondition.
        #expect((habit.completions ?? []).isEmpty == false)

        let peer = ModelContext(container)
        let habitID = habit.id
        let theirs = try peer.fetch(FetchDescriptor<Completion>(
            predicate: #Predicate { $0.habit?.id == habitID && $0.demoSessionID != nil }
        ))
        let doomed = try #require(theirs.first)
        peer.delete(doomed)
        try peer.save()
        return (container, app, habit)
    }

    @Test("Purging invented rows after a peer deleted one of them")
    func purgeSurvivesAPeerDelete() throws {
        let (container, app, habit) = try seededWithOnePeerDelete()
        defer { withExtendedLifetime(container) {} }

        #expect(try RetiredDebugData.purge(context: app, defaults: defaults()) == 2)

        let habitID = habit.id
        let left = try app.fetch(FetchDescriptor<Completion>(
            predicate: #Predicate { $0.habit?.id == habitID }
        ))
        #expect(left.count == 1, "the completion the person logged survives")
        #expect(left.allSatisfy { $0.demoSessionID == nil })
    }

    @Test("Resetting to the defaults after a peer deleted a row")
    func resetSurvivesAPeerDelete() throws {
        let (container, app, _) = try seededWithOnePeerDelete()
        defer { withExtendedLifetime(container) {} }

        let store = HabitStore(context: app, calendar: calendar, restDay: nil)
        #expect(try store.resetToDefaults(now: today) == DefaultHabits.all.count)
        #expect(try app.fetchCount(FetchDescriptor<Completion>()) == 0)
        #expect(try app.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }

    /// And the inverse the writers now rely on holds for a delete through the
    /// store, read off the array afterwards — the same claim
    /// `PersistenceTests` makes for the tap, made for the other writers.
    @Test("The array agrees with the store after each writer, without being told")
    func theArrayFollowsTheStore() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let app = ModelContext(container)
        let store = HabitStore(context: app, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        #expect(try store.addCompletion(for: habit, on: today) == 1)
        #expect(habit.completions?.count == 1)
        #expect(try store.clearDay(for: habit, on: today) == 1)
        #expect(habit.completions?.isEmpty == true)

        try insertInvented(for: habit, into: app)
        let seeded = habit.completions?.count ?? 0
        #expect(seeded > 0)
        try RetiredDebugData.purge(context: app, defaults: defaults())
        #expect(habit.completions?.isEmpty == true)
    }
}
