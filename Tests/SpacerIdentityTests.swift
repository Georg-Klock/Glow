import Foundation
import SwiftData
import Testing
@testable import Glow

/// #129 and #143: a blank row is a *position*, and it kept being treated as an
/// identity and as a general-purpose deleted-habit slot.
///
/// One suite because they are one change. Both issues land on the same two
/// functions — `addHabit`'s reuse of a blank row and `delete`'s conversion into
/// one — and fixing either alone leaves the other's reproduction working.
@Suite("Spacer identity")
@MainActor
struct SpacerIdentityTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeStore(_ context: ModelContext) -> HabitStore {
        HabitStore(context: context, calendar: calendar)
    }

    private func rows(_ context: ModelContext) throws -> [Habit] {
        try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )
    }

    // MARK: - Identity

    @Test("A deleted habit's id does not survive as a blank row")
    func deleteRetiresTheIdentity() throws {
        // The id is what a widget configuration and a widget intent both
        // resolve by, so a row that kept it hands the next habit the last
        // one's widget.
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        let before = habit.id

        try store.delete(habit)

        let row = try #require(try rows(context).first)
        #expect(row.isSpacer)
        #expect(row.id != before)
    }

    @Test("The habit that fills a blank row is a new habit")
    func reuseTakesANewIdentity() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let first = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        // Read *before* the delete. A SwiftData object is live, not a snapshot:
        // `first`, the blank row and `second` are all the same instance here,
        // so asking `first.id` afterwards asks the new habit for its own id and
        // the assertion compares a value to itself.
        let firstID = first.id
        try store.delete(first)
        let spacerID = try #require(try rows(context).first).id

        let second = try store.addHabit(name: "Walk", icon: "🚶", frequency: .timesPerWeek(2))

        #expect(second.id != firstID)
        #expect(second.id != spacerID)
        #expect(try rows(context).count == 1, "the position was reused, not appended to")
    }

    @Test("No completion outlives the habit it belonged to")
    func historyDoesNotTransfer() throws {
        // The ghost-history half of #129: a stale widget tap lands after the
        // delete, and the row is later refilled.
        let context = try makeContext()
        let store = makeStore(context)
        let first = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        try store.toggleCompletion(for: first, on: today)
        try store.delete(first)

        let second = try store.addHabit(name: "Walk", icon: "🚶", frequency: .timesPerWeek(2))
        #expect((second.completions ?? []).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)
    }

    // MARK: - Stale writes

    @Test("A blank row refuses every kind of write")
    func spacerRefusesWrites() throws {
        // A widget snapshot outlives the thing it draws, so the tap arrives
        // for a habit that is now a blank row. The store is the one path both
        // processes share.
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        try store.delete(habit)
        let spacer = try #require(try rows(context).first)

        #expect(try store.toggleCompletion(for: spacer, on: today) == .refused)
        #expect(try store.addCompletion(for: spacer, on: today) == 0)
        #expect(try store.clearDay(for: spacer, on: today) == 0)
        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)
    }

    // The three tests that stood here were about the per-day kind: that a ring
    // refused a day toggle, that adding one did not consume This Week's blank
    // row, and that deleting one left none behind. All three are on
    // `feature/daily-habits-2.0` with the kind they described (#209). What is
    // left below is the rule they were guarding, which was never theirs.

    @Test("A weekly habit still leaves and still takes a blank row")
    func weeklyBehaviourIsUnchanged() throws {
        // The rule this whole change is protecting, so it is asserted rather
        // than assumed: a position stays put through delete and refill.
        let context = try makeContext()
        let store = makeStore(context)
        let a = try store.addHabit(name: "A", icon: "a", frequency: .timesPerWeek(3))
        let b = try store.addHabit(name: "B", icon: "b", frequency: .daily)
        let orderOfA = a.sortOrder

        try store.delete(a)
        #expect(try rows(context).count == 2)

        let c = try store.addHabit(name: "C", icon: "c", frequency: .timesPerWeek(2))
        #expect(c.sortOrder == orderOfA, "C took A's position")
        #expect(try rows(context).count == 2)
        #expect(b.sortOrder > c.sortOrder, "B did not move")
    }

    @Test("A blank row is still deleted outright")
    func deletingASpacerRemovesIt() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let spacer = try store.addSpacer()
        try store.delete(spacer)
        #expect(try rows(context).isEmpty)
    }
}
