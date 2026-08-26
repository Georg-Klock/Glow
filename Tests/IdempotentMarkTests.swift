import Foundation
import SwiftData
import Testing
@testable import Glow

/// #272, #292: marking a habit from a widget sets a state; it does not flip one.
///
/// The complaint was "checking off several habits quickly un-does them", and it
/// had two causes that a toggle turns into the same bug:
///
/// * **A single tap performing the intent twice**, measured 13ms apart on an
///   iPhone 14 Pro. Under a toggle the second performance undoes the first.
/// * **A stale surface.** WidgetKit's pixels lag the store, so a tap lands on a
///   ring for a day the store already has as done. A toggle reads that as
///   "flip", and removes the completion the person was trying to make.
///
/// Every test here is the same shape: ask for a state twice, or ask for the
/// state already held, and assert the record survives.
@Suite("Idempotent marking")
@MainActor
struct IdempotentMarkTests {
    private let calendar = TestCalendar.monday
    private let monday = TestCalendar.date(2026, 8, 17)

    private func store() throws -> (HabitStore, Habit) {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: ModelContext(container), calendar: calendar)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .daily)
        return (store, habit)
    }

    /// How many completions the day holds, read through the model rather than
    /// through the store's own private lookup — so this counts what was
    /// actually written rather than trusting the thing under test.
    private func completions(_ habit: Habit) -> Int {
        let day = DayID(monday, calendar: calendar)
        return (habit.completions ?? []).filter { DayID($0.day, calendar: calendar) == day }.count
    }

    @Test("Asking for done twice logs once")
    func doneTwiceLogsOnce() throws {
        // The duplicated delivery. Under a toggle the second call undid the
        // first and the tap did nothing at all.
        let (store, habit) = try store()
        #expect(try store.setCompletion(for: habit, on: monday, done: true) == .completed)
        #expect(try store.setCompletion(for: habit, on: monday, done: true) == .unchanged)
        #expect(completions(habit) == 1)
    }

    @Test("A stale ring does not retract a completion")
    func staleRingDoesNotRetract() throws {
        // The case the trace actually caught: the store has the day done, the
        // widget is still drawing the open ring, and somebody taps it meaning
        // "complete this". The request is `done: true` because that is what the
        // ring was asking for — and the completion survives.
        let (store, habit) = try store()
        #expect(try store.setCompletion(for: habit, on: monday, done: true) == .completed)

        #expect(try store.setCompletion(for: habit, on: monday, done: true) == .unchanged)
        #expect(completions(habit) == 1, "a stale tap removed a completion")
    }

    @Test("Asking for undone twice removes once and then does nothing")
    func undoneIsIdempotentToo() throws {
        // Undo has to converge as well, or the same duplicate turns an undo
        // back into a completion.
        let (store, habit) = try store()
        _ = try store.setCompletion(for: habit, on: monday, done: true)
        #expect(try store.setCompletion(for: habit, on: monday, done: false) == .uncompleted)
        #expect(try store.setCompletion(for: habit, on: monday, done: false) == .unchanged)
        #expect(completions(habit) == 0)
    }

    @Test("Order does not matter, only the last request")
    func theLastRequestWins() throws {
        // What "converges" means: whatever sequence of deliveries arrives, the
        // record ends in the state the last one asked for.
        let (store, habit) = try store()
        for request in [true, true, false, true, true] {
            _ = try store.setCompletion(for: habit, on: monday, done: request)
        }
        #expect(completions(habit) == 1)

        for request in [false, false, true, false] {
            _ = try store.setCompletion(for: habit, on: monday, done: request)
        }
        #expect(completions(habit) == 0)
    }

    @Test("A toggle still flips, and never reports unchanged")
    func toggleStillToggles() throws {
        // The app's own surfaces keep the toggle: they redraw in-process from
        // the store they just wrote, so they are never the stale caller this
        // is about. `toggleCompletion` reads the day and asks for its opposite,
        // so there is always something to change.
        let (store, habit) = try store()
        #expect(try store.toggleCompletion(for: habit, on: monday) == .completed)
        #expect(try store.toggleCompletion(for: habit, on: monday) == .uncompleted)
        #expect(try store.toggleCompletion(for: habit, on: monday) == .completed)
        #expect(completions(habit) == 1)
    }

    @Test("A refusal still wins over the requested state")
    func refusalOutranksTheRequest() throws {
        // Idempotence must not quietly become permission. The rest day and the
        // future are the store's rules and they are checked before the day's
        // current state is even read — a widget rendered before the setting
        // changed can still be holding a button the store will not honour.
        let (store, habit) = try store()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: WeekCalendar.today(calendar: calendar))!
        #expect(try store.setCompletion(for: habit, on: tomorrow, done: true) == .refused)
        #expect(try store.setCompletion(for: habit, on: tomorrow, done: false) == .refused)
    }
}
