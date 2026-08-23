import Foundation
import SwiftData
import Testing
@testable import Glow

/// #134: some persisted changes never asked a widget to redraw at all.
@Suite("Widget refresh", .serialized)
@MainActor
struct WidgetRefreshTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Watches what was asked for instead of calling WidgetKit, and puts the
    /// real sink back afterwards.
    private final class Spy {
        var calls: [Set<String>] = []
        var count: Int { calls.count }
        var kinds: Set<String> { calls.reduce(into: []) { $0.formUnion($1) } }
    }

    /// `restDay` is the store's, stated here rather than pinned in the process
    /// (#181): `HabitStore` takes it at construction, like its calendar, so a
    /// test that wants a refusal builds a store that rests on that day.
    private func withSpy(
        restDay: Int? = nil,
        _ body: (Spy, HabitStore, ModelContext) throws -> Void
    ) throws {
        let spy = Spy()
        let previous = WidgetRefresh.sink
        defer { WidgetRefresh.sink = previous; WidgetRefresh.flush() }
        WidgetRefresh.flush()   // nothing pending from a previous test
        WidgetRefresh.sink = { [spy] kinds in spy.calls.append(kinds) }

        let context = try makeContext()
        try body(
            spy,
            HabitStore(context: context, calendar: calendar, restDay: restDay),
            context
        )
    }

    // MARK: - Every write asks

    @Test("Every kind of write invalidates")
    func everyWriteInvalidates() throws {
        // The list is the point: three of these — spacer, reorder, delete —
        // had no reload at any call site before this change.
        try withSpy { spy, store, _ in
            let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
            let water = try store.addHabit(name: "Water", icon: "💧", frequency: .timesPerDay(6))
            let spacer = try store.addSpacer()
            try store.update(habit, name: "Read more", icon: "📖", frequency: .timesPerWeek(4))
            try store.toggleCompletion(for: habit, on: today)
            try store.recordTap(for: water, on: today)
            try store.clearDay(for: water, on: today)
            try store.reorder([habit, water, spacer], from: IndexSet(integer: 0), to: 2)
            try store.delete(habit)
            try store.delete(spacer)

            WidgetRefresh.flush()
            #expect(spy.count >= 1, "no write asked for a redraw")
            #expect(spy.kinds == WidgetRefresh.allKinds)
        }
    }

    @Test("A reset asks for a redraw, once for the whole thing")
    func resetInvalidatesOnce() throws {
        // #193 empties the store and refills it, which is every row the widget
        // draws changing at once — and it is one commit, so it is one reload.
        // The issue's sketch called `reloadAllTimelines` at the call site; that
        // is the habit #134 removed, and going through `commit()` is what makes
        // this coalesce like every other write.
        try withSpy { spy, store, _ in
            try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
            WidgetRefresh.flush()
            let before = spy.count

            try store.resetToDefaults()

            WidgetRefresh.flush()
            #expect(spy.count == before + 1)
            #expect(spy.calls.last == WidgetRefresh.allKinds)
        }
    }

    @Test("A refused write does not pretend anything changed")
    func refusalDoesNotInvalidate() throws {
        // A rest-day refusal saves nothing, so there is nothing to redraw. The
        // intents ask separately in that case, for their own stale surface.
        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let monday = TestPreferences.weekday(ofColumn: 0, in: week)

        try withSpy(restDay: monday) { spy, store, _ in
            let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
            WidgetRefresh.flush()
            let before = spy.count

            // The call is hoisted out of the macro: `#expect` around a `try`
            // inside a rethrowing closure does not compile.
            let outcome = try store.toggleCompletion(for: habit, on: week.days[0])
            #expect(outcome == .refused)

            WidgetRefresh.flush()
            #expect(spy.count == before)
        }
    }

    // MARK: - Coalescing

    @Test("One gesture is one reload, however many rows it rewrites")
    func requestsCoalesce() throws {
        // A reorder rewrites `sortOrder` on every row; a delete-then-refill is
        // two writes. Neither should cost a reload per row.
        try withSpy { spy, _, _ in
            for _ in 0..<20 { WidgetRefresh.invalidate() }
            WidgetRefresh.flush()
            #expect(spy.count == 1)
            #expect(spy.calls.first == WidgetRefresh.allKinds)
        }
    }

    @Test("Coalescing unions the kinds rather than keeping the last")
    func kindsAreUnioned() throws {
        try withSpy { spy, _, _ in
            WidgetRefresh.invalidate(["GlowWidget"])
            WidgetRefresh.invalidate(["GlowMonthSmall"])
            WidgetRefresh.flush()
            #expect(spy.count == 1)
            #expect(spy.calls.first == ["GlowWidget", "GlowMonthSmall"])
        }
    }

    @Test("Nothing pending sends nothing")
    func emptyFlushIsSilent() throws {
        try withSpy { spy, _, _ in
            WidgetRefresh.flush()
            WidgetRefresh.flush()
            #expect(spy.count == 0)
        }
    }

    @Test("A reload that is due still arrives without anyone flushing it")
    func invalidateDeliversOnItsOwn() async throws {
        // `flush` exists for the tests above; the app never calls it, so the
        // scheduling has to work by itself.
        let spy = Spy()
        let previous = WidgetRefresh.sink
        defer { WidgetRefresh.sink = previous }
        WidgetRefresh.flush()
        WidgetRefresh.sink = { [spy] kinds in spy.calls.append(kinds) }

        WidgetRefresh.invalidate()
        #expect(spy.count == 0, "it should not have been sent synchronously")
        try await Task.sleep(for: .milliseconds(100))
        #expect(spy.count == 1)
    }

    // MARK: - The kinds are the real ones

    @Test("The kind strings are pinned")
    func kindsArePinned() {
        // Not a tautology, despite reading like one. A widget's kind is a
        // *persistent identifier*: WidgetKit stores it against every widget a
        // person has placed, so changing one orphans their widget rather than
        // renaming it. These are spelled out here so that doing it is a
        // deliberate act with a failing test in front of it.
        //
        // Drift between the enum and the widgets is handled structurally
        // instead — each `StaticConfiguration` reads its kind from `WidgetKind`,
        // so there is no second spelling to drift from.
        #expect(WidgetKind.week.rawValue == "GlowWidget")
        #expect(WidgetKind.todaySmall.rawValue == "GlowTodaySmall")
        #expect(WidgetKind.todayMedium.rawValue == "GlowTodayMedium")
        #expect(WidgetKind.month.rawValue == "GlowMonthSmall")
        #expect(WidgetKind.allCases.count == 4)
        #expect(WidgetRefresh.allKinds == WidgetKind.allNames)
    }
}
