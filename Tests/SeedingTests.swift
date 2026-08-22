import Foundation
import SwiftData
import Testing
@testable import Glow

@Suite("Default habits")
@MainActor
struct SeedingTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A throwaway defaults domain per test, so one test's "already seeded"
    /// flag cannot decide another's outcome, and so a run never touches the
    /// real one.
    private func makeDefaults() -> UserDefaults {
        let suite = "seeding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func seeder(_ context: ModelContext, _ defaults: UserDefaults) -> HabitSeeder {
        HabitSeeder(context: context, defaults: defaults, calendar: calendar)
    }

    @Test("A fresh install starts with the default habits and an empty grid")
    func seedsOnFirstLaunch() throws {
        // Habits only, in every configuration: a tracker that opens showing a
        // streak you did not earn is lying on the first screen. The invented
        // past is DemoHistory's, behind the Settings toggle, and has its own
        // suite.
        let context = try makeContext()
        let added = try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        #expect(added == DefaultHabits.all.count)
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(habits.map(\.name) == DefaultHabits.all.map(\.name))
        #expect(habits.map(\.frequency) == DefaultHabits.all.map(\.frequency))
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("Every seeded habit is open today")
    func seededHabitsAreOpenToday() throws {
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        let week = WeekCalendar.week(containing: today, calendar: calendar)
        for habit in try context.fetch(FetchDescriptor<Habit>()) where !habit.isSpacer {
            let slots = WeekGrid.slots(for: habit.snapshot(), in: week, today: today, editing: .todayOnly, calendar: calendar)
            #expect(slots.filter { $0.state == .open }.count == 1, "\(habit.name)")
        }
    }

    @Test("A perfect habit really is perfect, and an uneven one is not")
    func formsProduceTheirRates() throws {
        // The point of the seed is that a full streak is visible and a missed
        // day is visible. If every habit came out the same these would be eight
        // rows of identical noise.
        let perfect = SeededHistory.completions(
            for: .daily, form: .perfect, seed: 1, today: today, calendar: calendar
        )
        let uneven = SeededHistory.completions(
            for: .daily, form: .uneven, seed: 1, today: today, calendar: calendar
        )
        #expect(perfect.count > uneven.count)

        // Perfect means every day back to the start, with none skipped.
        let days = Set(perfect)
        var cursor = perfect.min() ?? today
        while cursor < today {
            #expect(days.contains(cursor), "perfect run has a hole at \(cursor)")
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }
    }

    @Test("An N-times-a-week habit is seeded by the week, not by the day")
    func frequencyHistoryRespectsTheGoal() throws {
        // Seeded per day, a 2x-a-week habit lands six completions in one week
        // and none in the next, and every row reads as broken.
        let days = SeededHistory.completions(
            for: .timesPerWeek(2), form: .perfect, seed: 5, today: today, calendar: calendar
        )
        let byWeek = Dictionary(grouping: days) {
            WeekCalendar.startOfWeek(containing: $0, calendar: calendar)
        }
        // The current week is partial, so only the whole ones are checked.
        let thisWeek = WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        for (start, completions) in byWeek where start != thisWeek {
            #expect(completions.count == 2, "week of \(start) has \(completions.count)")
        }
    }

    @Test("Seeding runs once, not on every launch")
    func seedsOnlyOnce() throws {
        let context = try makeContext()
        let defaults = makeDefaults()

        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == DefaultHabits.all.count)
        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }

    @Test("Deleting every habit does not bring them back")
    func doesNotReseedAfterDeletion() throws {
        // "Is the store empty" and "has this install been seeded" are different
        // questions, and answering the second with the first makes the app
        // impossible to empty.
        let context = try makeContext()
        let defaults = makeDefaults()
        try seeder(context, defaults).seedIfNeeded(now: today)

        let store = HabitStore(context: context, calendar: calendar)
        // Twice: the first pass turns every habit into a blank row, the second
        // removes the rows. Emptying the list is two steps now, which is the
        // point — a deleted habit leaves its position behind.
        for _ in 0..<2 {
            for habit in try context.fetch(FetchDescriptor<Habit>()) {
                try store.delete(habit)
            }
        }

        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 0)
    }

    @Test("An install that already has habits is left alone")
    func doesNotSeedOverExistingHabits() throws {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar)
        try store.addHabit(name: "Mine", icon: "star", frequency: .daily)

        #expect(try seeder(context, makeDefaults()).seedIfNeeded(now: today) == 0)
        let habits = try context.fetch(FetchDescriptor<Habit>())
        #expect(habits.map(\.name) == ["Mine"])
    }

    @Test("Every default habit uses a symbol the picker can draw")
    func defaultsUseRealSymbols() {
        // A seeded habit whose icon is not in the catalogue would render as
        // literal text, which is how a typo here would reach a first launch.
        for template in DefaultHabits.all where !template.isSpacer {
            #expect(HabitSymbol.isSymbol(template.icon), "\(template.icon) is not a known symbol")
        }
    }

    @Test("The defaults show both row shapes")
    func defaultsCoverBothCadences() {
        let cadences = Set(DefaultHabits.all.map(\.frequency))
        #expect(cadences.contains(.daily))
        #expect(cadences.contains { if case .timesPerWeek = $0 { true } else { false } })
    }
}

@Suite("Blank rows")
struct SpacerTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    @Test("A blank row draws nothing at all")
    func spacerHasNoSlots() {
        // Not "draws an empty state" — draws nothing. It is a position in the
        // order, and anything rendered in it would be a mark for a habit that
        // does not exist.
        let spacer = HabitSnapshot.fixture(isSpacer: true)
        #expect(WeekGrid.slots(for: spacer, in: week, today: today, editing: .todayOnly, calendar: calendar).isEmpty)
    }

    @Test("A blank row draws nothing on a spanning cadence either")
    func spacerHasNoSpans() {
        let spacer = HabitSnapshot.fixture(frequency: .timesPerWeek(3), isSpacer: true)
        let spans = WeekSpans.spans(
            for: spacer, in: week, today: today, target: 3, editing: .todayOnly, calendar: calendar
        )
        #expect(spans.isEmpty)
    }

    @Test("The defaults fill a large widget exactly")
    func defaultsFillTheWidget() {
        // Eight habits and three blank rows is eleven, which is what a large
        // widget holds — see WidgetMetricsTests. The blank rows are there to be
        // moved between habits, and they only work as a grouping device if
        // there is room for them.
        #expect(DefaultHabits.all.count == 11)
        #expect(DefaultHabits.all.count(where: \.isSpacer) == 3)
        #expect(DefaultHabits.all.count(where: { !$0.isSpacer }) == 8)
    }

    @Test("Blank rows come with no habit fields and no history")
    func spacersAreEmpty() {
        for template in DefaultHabits.all where template.isSpacer {
            #expect(template.name.isEmpty)
            #expect(template.icon.isEmpty)
        }
    }
}

@Suite("Deleting")
@MainActor
struct DeletionTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("Deleting a habit leaves a blank row where it was")
    func deleteLeavesASpacer() throws {
        // The grid is a layout the user arranged. Collapsing a row pulls
        // everything below it up a line, so removing one habit would silently
        // regroup every habit under it.
        let context = try makeContext()
        let store = HabitStore(context: context)
        let first = try store.addHabit(name: "One", icon: "book", frequency: .daily)
        let second = try store.addHabit(name: "Two", icon: "drop", frequency: .daily)

        try store.delete(first)

        let rows = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        #expect(rows.count == 2)
        #expect(rows[0].isSpacer)
        #expect(rows[0].name.isEmpty)
        #expect(rows[1].id == second.id)
    }

    @Test("The habit itself is gone, completions and all")
    func deleteRemovesEverythingButThePosition() throws {
        let context = try makeContext()
        let store = HabitStore(context: context)
        let habit = try store.addHabit(name: "One", icon: "book", frequency: .daily)
        _ = try store.toggleCompletion(for: habit, on: Date())
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)

        try store.delete(habit)

        // Removed explicitly rather than left to cascade — the row survives, so
        // there is nothing for a cascade to hang off.
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
        #expect(habit.completedDays.isEmpty)
    }

    @Test("Deleting a blank row removes it")
    func deleteSpacerRemovesTheRow() throws {
        // Otherwise a gap could never be closed, and the grid would only ever
        // grow more of them.
        let context = try makeContext()
        let store = HabitStore(context: context)
        let spacer = try store.addSpacer()

        try store.delete(spacer)

        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == 0)
    }
}

@Suite("Adding fills blank rows")
@MainActor
struct AddingTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func rows(_ context: ModelContext) throws -> [Habit] {
        try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    @Test("A new habit takes the first blank row rather than landing past it")
    func addFillsTheFirstBlank() throws {
        let context = try makeContext()
        let store = HabitStore(context: context)
        try store.addHabit(name: "One", icon: "book", frequency: .daily)
        try store.addSpacer()
        try store.addSpacer()

        try store.addHabit(name: "Two", icon: "drop", frequency: .timesPerWeek(3))

        // Three rows, not four: the count is stable and the clustering the rows
        // were expressing survives.
        let all = try rows(context)
        #expect(all.count == 3)
        #expect(all[1].name == "Two")
        #expect(all[1].isSpacer == false)
        #expect(all[1].frequency == .timesPerWeek(3))
        #expect(all[2].isSpacer)
    }

    @Test("With no blank rows it appends, as it always did")
    func addAppendsWhenFull() throws {
        let context = try makeContext()
        let store = HabitStore(context: context)
        try store.addHabit(name: "One", icon: "book", frequency: .daily)

        try store.addHabit(name: "Two", icon: "drop", frequency: .daily)

        let all = try rows(context)
        #expect(all.count == 2)
        #expect(all.map(\.name) == ["One", "Two"])
    }

    @Test("Delete then add reuses the same row")
    func deleteThenAddIsStable() throws {
        // The two halves of one idea: a row's existence is stable and only its
        // contents change. Deleting leaves the position, adding takes it back.
        let context = try makeContext()
        let store = HabitStore(context: context)
        let first = try store.addHabit(name: "One", icon: "book", frequency: .daily)
        try store.addHabit(name: "Two", icon: "drop", frequency: .daily)

        try store.delete(first)
        try store.addHabit(name: "Three", icon: "leaf", frequency: .daily)

        let all = try rows(context)
        #expect(all.count == 2)
        #expect(all.map(\.name) == ["Three", "Two"])
    }
}
