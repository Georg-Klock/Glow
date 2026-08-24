import Foundation
import SwiftData
import Testing
@testable import Glow

/// #129 and #143 made a blank row a *position* rather than an identity or a
/// general-purpose deleted-habit slot. **#257 removed the position** (2026-08-24):
/// a delete collapses its row, and `addHabit` appends rather than filling one.
///
/// What survives from #129 is the half that was never about layout — a deleted
/// habit's `id` and history must stop resolving to anything, because widget
/// configurations and widget intents resolve by `id` and a widget snapshot can
/// outlive what it draws. Deleting the row outright is a stronger form of that
/// guarantee than retiring the `id` of a row that stays.
///
/// The blank rows that express grouping are unaffected: `addSpacer` still makes
/// them, they are still refused every day-shaped write, and deleting one still
/// removes it. They are simply the only blank rows now.
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

    @Test("A deleted habit's id does not survive at all")
    func deleteRetiresTheIdentity() throws {
        // The id is what a widget configuration and a widget intent both
        // resolve by. It used to be retired on a row that stayed; since #257
        // the row goes with it, which is the same guarantee without the row.
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        let before = habit.id

        try store.delete(habit)

        #expect(try rows(context).isEmpty, "the row survived the delete")
        #expect(try !rows(context).contains { $0.id == before })
    }

    @Test("A habit added after a delete is a new habit in a new row")
    func addAfterDeleteIsANewRow() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let first = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        // Read *before* the delete. A SwiftData object is live, not a snapshot.
        let firstID = first.id
        try store.delete(first)
        #expect(try rows(context).isEmpty)

        let second = try store.addHabit(name: "Walk", icon: "🚶", frequency: .timesPerWeek(2))

        #expect(second.id != firstID)
        #expect(try rows(context).count == 1, "the row was appended, not reused")
        #expect(!second.isSpacer)
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
        // A deliberate blank row, which since #257 is the only kind there is.
        let spacer = try store.addSpacer()

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

    /// **The reversal itself** (#257). This test is the old
    /// `weeklyBehaviourIsUnchanged` turned around: it used to assert that a
    /// position stays put through delete and refill, which is exactly the
    /// behaviour that was reported as a delete that did not work.
    @Test("Deleting a habit collapses its row and everything below moves up")
    func deleteCollapsesTheRow() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let a = try store.addHabit(name: "A", icon: "a", frequency: .timesPerWeek(3))
        let b = try store.addHabit(name: "B", icon: "b", frequency: .daily)
        #expect(a.sortOrder < b.sortOrder)

        try store.delete(a)

        // One act, one row gone — not a blank row that has to be deleted again.
        #expect(try rows(context).map(\.name) == ["B"])

        // And the next habit lands after B rather than in the gap A left.
        let c = try store.addHabit(name: "C", icon: "c", frequency: .timesPerWeek(2))
        #expect(try rows(context).map(\.name) == ["B", "C"])
        #expect(c.sortOrder > b.sortOrder, "C landed in A's old position")
    }

    /// A deliberate blank row is not consumed by the next habit either — it is
    /// the grouping somebody put there, and taking it away is the same failure
    /// as leaving one behind, from the other side.
    @Test("A deliberate blank row survives adding a habit")
    func addingDoesNotEatASpacer() throws {
        let context = try makeContext()
        let store = makeStore(context)
        try store.addHabit(name: "A", icon: "a", frequency: .daily)
        try store.addSpacer()

        try store.addHabit(name: "B", icon: "b", frequency: .daily)

        let all = try rows(context)
        #expect(all.count == 3)
        #expect(all.map(\.isSpacer) == [false, true, false])
        #expect(all.map(\.name) == ["A", "", "B"])
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
