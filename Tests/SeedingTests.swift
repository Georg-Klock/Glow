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

    @Test("Every seeded week row is open today")
    func seededHabitsAreOpenToday() throws {
        // The weekly cadences only. A per-day habit has no week row at all —
        // it is one ring on Today — so asking `WeekGrid` about it would assert
        // against the backstop that draws nothing rather than against a habit.
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let rows = try context.fetch(FetchDescriptor<Habit>(predicate: Habit.countedPerWeek))
        for habit in rows where !habit.isSpacer {
            let slots = WeekGrid.slots(
                for: habit.snapshot(calendar: calendar), in: week, today: today,
                editing: .todayOnly, restDay: nil, calendar: calendar
            )
            #expect(slots.filter { $0.state == .open }.count == 1, "\(habit.name)")
        }
    }

    @Test("Every seeded ring has its whole day still to do")
    func seededRingsAreOpenToday() throws {
        // Today's half of the same claim: a fresh install's rings are empty,
        // with every repetition open, because nothing has been logged yet.
        let context = try makeContext()
        try seeder(context, makeDefaults()).seedIfNeeded(now: today)

        let rings = try context.fetch(FetchDescriptor<Habit>(predicate: Habit.countedPerDay))
        #expect(rings.count == DefaultHabits.perDay.count)
        for habit in rings {
            #expect(!habit.isSpacer, "\(habit.name) is a blank row on Today")
            let target = try #require(habit.frequency.dailyTarget)
            let arcs = DayRing.arcs(target: target, done: 0)
            let open = arcs.filter(\.isOpen).count
            #expect(arcs.count == target, "\(habit.name)")
            #expect(open == target, "\(habit.name)")
        }
    }

    @Test("A perfect habit really is perfect, and an uneven one is not")
    func formsProduceTheirRates() throws {
        // The point of the seed is that a full streak is visible and a missed
        // day is visible. If every habit came out the same these would be eight
        // rows of identical noise.
        let perfect = SeededHistory.completions(
            for: .daily, form: .perfect, seed: 1, today: today,
            restDay: nil, calendar: calendar
        )
        let uneven = SeededHistory.completions(
            for: .daily, form: .uneven, seed: 1, today: today,
            restDay: nil, calendar: calendar
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
            for: .timesPerWeek(2), form: .perfect, seed: 5, today: today,
            restDay: nil, calendar: calendar
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

    @Test("A seed that could not save leaves nothing, and the next launch tries again")
    func aFailedSeedIsRetried() throws {
        // The partial-seed failure, which used to be permanent: the flag went
        // in before the inserts, so an interruption anywhere in them left four
        // habits of eleven and nothing that would ever repair them.
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        let defaults = makeDefaults()

        // An empty store, made first: a read-only container cannot open a file
        // that is not there yet, which is a fresh install's other problem.
        let empty = try TestStore.writable(at: url)
        try empty.save()

        let blocked = try TestStore.readOnly(at: url)
        #expect(throws: (any Error).self) {
            try seeder(blocked, defaults).seedIfNeeded(now: today)
        }
        #expect(!defaults.bool(forKey: HabitSeeder.seededKey))

        let after = try TestStore.writable(at: url)
        #expect(try after.fetchCount(FetchDescriptor<Habit>()) == 0)
        #expect(try seeder(after, defaults).seedIfNeeded(now: today) == DefaultHabits.all.count)
        #expect(try after.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }

    @Test("A flag that never landed does not seed the list twice")
    func aLostFlagConvergesRatherThanDuplicating() throws {
        // The one step that cannot be part of the transaction is the flag,
        // because it lives in another store. So it converges: a launch that
        // finds habits it has no record of putting there records that, rather
        // than adding eleven more rows to a list somebody is already using.
        let context = try makeContext()
        let forgetful = try #require(ForgetfulDefaults(suiteName: "seeding-lost-flag-\(UUID().uuidString)"))
        #expect(try seeder(context, forgetful).seedIfNeeded(now: today) == DefaultHabits.all.count)
        #expect(!forgetful.bool(forKey: HabitSeeder.seededKey))

        // Relaunch, with a defaults that keeps what it is given this time.
        let defaults = makeDefaults()
        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
        #expect(defaults.bool(forKey: HabitSeeder.seededKey))
        #expect(try seeder(context, defaults).seedIfNeeded(now: today) == 0)
    }

    @Test("A list goes in as it was written, blank rows in their places")
    func addAllKeepsTheListItGaveIt() throws {
        // `addAll` is where a seed set becomes rows, so it is what a change to
        // the seed data has to keep working. It appends after whatever is
        // already there, in order, and a template that says blank row arrives
        // as a blank row rather than as a habit with no name.
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar)
        try store.addHabit(name: "Mine", icon: "star", frequency: .daily, now: today)

        let templates: [DefaultHabits.Template] = [
            DefaultHabits.Template(name: " Read ", icon: "book", frequency: .daily),
            DefaultHabits.Template(isSpacer: true, name: "", icon: "", frequency: .daily),
            DefaultHabits.Template(name: "Walk", icon: "figure.run", frequency: .timesPerWeek(2))
        ]
        #expect(try store.addAll(templates, now: today) == 3)

        let rows = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        #expect(rows.map(\.name) == ["Mine", "Read", "", "Walk"])
        #expect(rows.map(\.isSpacer) == [false, false, true, false])
        #expect(rows.map(\.sortOrder) == [0, 1, 2, 3])
        #expect(rows[3].frequency == .timesPerWeek(2))
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

    @Test("The defaults show every row shape the app draws")
    func defaultsCoverBothCadences() {
        let cadences = Set(DefaultHabits.all.map(\.frequency))
        #expect(cadences.contains(.daily))
        #expect(cadences.contains { if case .timesPerWeek = $0 { true } else { false } })
        #expect(cadences.contains { if case .timesPerDay = $0 { true } else { false } })
    }

    @Test("A seven-a-week default is written as daily")
    func sevenIsWrittenAsDaily() {
        // `Frequency.init(timesPerWeek:)` folds seven into `.daily` at runtime.
        // A literal `.timesPerWeek(7)` in the seed would therefore describe a
        // row the store can never hold, and read as a different cadence from
        // the one it seeds.
        let folded = DefaultHabits.all.filter { $0.frequency == .timesPerWeek(Frequency.daysInWeek) }
        #expect(folded.isEmpty)
    }

    @Test("No two defaults are named the same")
    func defaultNamesAreDistinct() {
        // Two rows nobody can tell apart is what the previous set shipped, with
        // "Touch Grass" twice on the same grid.
        let names = DefaultHabits.all.filter { !$0.isSpacer }.map(\.name)
        #expect(Set(names).count == names.count)
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
        #expect(WeekGrid.slots(
            for: spacer, in: week, today: today, editing: .todayOnly,
            restDay: nil, calendar: calendar
        ).isEmpty)
    }

    @Test("A blank row draws nothing on a spanning cadence either")
    func spacerHasNoSpans() {
        let spacer = HabitSnapshot.fixture(frequency: .timesPerWeek(3), isSpacer: true)
        let spans = WeekSpans.spans(
            for: spacer, in: week, today: today, target: 3,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(spans.isEmpty)
    }

    @Test("The weekly rows fit a large widget")
    func defaultsFitTheWidget() {
        // Eight habits and two blank rows is ten, inside the eleven a large
        // widget holds — see WidgetMetricsTests. Not a number the set was
        // built to hit: three clusters need two dividers, and ten is what that
        // comes to. What is asserted is that it fits.
        #expect(DefaultHabits.weekly.count == 10)
        #expect(DefaultHabits.weekly.count <= WidgetMetrics.largeRowCapacity)
        #expect(DefaultHabits.weekly.count(where: \.isSpacer) == 2)
        #expect(DefaultHabits.weekly.count(where: { !$0.isSpacer }) == 8)
    }

    @Test("Blank rows are the grid's, and only the grid's")
    func spacersAreWeeklyOnly() {
        // `countedPerWeek` is `timesPerDay == 0`, which a blank row satisfies
        // and a per-day habit never does — so a spacer among the per-day five
        // would be a row Today could not draw and the grid could not see.
        let spacersOnToday = DefaultHabits.perDay.count(where: \.isSpacer)
        #expect(DefaultHabits.perDay.count == 5)
        #expect(spacersOnToday == 0)
        #expect(DefaultHabits.weekly.count + DefaultHabits.perDay.count == DefaultHabits.all.count)
    }

    @Test("The blank rows fall between clusters, never at either end")
    func spacersDivideRatherThanPad() {
        // A blank row at the top or the bottom of the grid is padding; between
        // two habits it is a divider. Three clusters, so the dividers are
        // interior and never adjacent.
        let isSpacer = DefaultHabits.weekly.map(\.isSpacer)
        let adjacent = zip(isSpacer, isSpacer.dropFirst()).filter { $0 && $1 }.count
        #expect(isSpacer.first == false)
        #expect(isSpacer.last == false)
        #expect(adjacent == 0)
        #expect(isSpacer.filter { $0 }.count == 2)
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

/// #193: the opt-in way back to the shipped defaults, for a store the seeding
/// guard will never touch again.
@Suite("Reset to defaults")
@MainActor
struct ResetToDefaultsTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "reset-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A store somebody has actually used: their own habits, their own days.
    private func handTypedStore() throws -> (ModelContext, HabitStore) {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let mine = try store.addHabit(name: "Mine", icon: "star", frequency: .daily, now: today)
        try store.addSpacer(now: today)
        let counted = try store.addHabit(
            name: "Water", icon: "drop", frequency: .timesPerDay(3), now: today
        )
        _ = try store.toggleCompletion(for: mine, on: today)
        _ = try store.toggleCompletion(for: mine, on: TestCalendar.date(2026, 8, 18))
        _ = try store.addCompletion(for: counted, on: today)
        return (context, store)
    }

    @Test("A reset leaves exactly the shipped defaults, in their order")
    func resetInstallsTheDefaults() throws {
        let (context, store) = try handTypedStore()

        #expect(try store.resetToDefaults(now: today) == DefaultHabits.all.count)

        let rows = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        #expect(rows.map(\.name) == DefaultHabits.all.map { $0.isSpacer ? "" : $0.name })
        #expect(rows.map(\.isSpacer) == DefaultHabits.all.map(\.isSpacer))
        #expect(
            rows.map(\.frequency)
                == DefaultHabits.all.map { $0.isSpacer ? Frequency.daily : $0.frequency }
        )
        // Numbered from zero, exactly as a first launch numbers them. Appending
        // after rows that are on their way out would leave the same list at
        // sortOrder 3…17 — invisible on screen, and a difference between
        // "reset" and "fresh install" that nothing would ever reconcile.
        #expect(rows.map(\.sortOrder) == Array(0..<DefaultHabits.all.count))
    }

    @Test("Nothing that was logged survives a reset")
    func resetTakesEveryCompletion() throws {
        let (context, store) = try handTypedStore()
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 3)

        try store.resetToDefaults(now: today)

        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("A completion with no habit on it goes too")
    func resetTakesOrphanedCompletions() throws {
        // What the `.cascade` rule cannot reach. A store in this state is not
        // one this app writes, but "nothing survives" is the whole promise
        // here, and a promise with an exception in it is a different promise.
        let (context, store) = try handTypedStore()
        context.insert(Completion(day: today, habit: nil, calendar: calendar))
        try context.save()

        try store.resetToDefaults(now: today)

        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("The demo reads as out afterwards, however it was recorded")
    func resetLeavesNoDemoBehind() throws {
        let defaults = makeDefaults()
        let context = try makeContext()
        try HabitSeeder(context: context, defaults: defaults, calendar: calendar)
            .seedIfNeeded(now: today)
        let demo = DemoHistory(
            context: context, defaults: defaults, calendar: calendar, restDay: nil
        )
        try demo.seed(now: today)
        #expect(demo.isSeeded)

        try HabitStore(context: context, calendar: calendar, restDay: nil)
            .resetToDefaults(now: today)

        // Provenance is on the row now (#140), so this holds because the rows
        // are gone — not because anything was told to forget them.
        #expect(!demo.isSeeded)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
    }

    @Test("The pre-provenance record is dropped rather than left naming nothing")
    func discardingTheLegacyRecordEmptiesTheKey() throws {
        let defaults = makeDefaults()
        let context = try makeContext()
        defaults.set([UUID().uuidString], forKey: DemoHistory.legacyIDsKey)
        let demo = DemoHistory(
            context: context, defaults: defaults, calendar: calendar, restDay: nil
        )

        demo.discardLegacyRecord()

        #expect(defaults.stringArray(forKey: DemoHistory.legacyIDsKey) == nil)
    }

    @Test("A reset does not re-arm first-run seeding")
    func resetLeavesTheSeededFlagAlone() throws {
        // `seededKey` means "this install has at some point ended up seeded",
        // and a store holding exactly the defaults is that state. Clearing it
        // would arm a seeder that then refuses the store anyway — and on the
        // one path where it would not refuse, it would be adding a second copy
        // of the list this call just installed.
        let defaults = makeDefaults()
        let context = try makeContext()
        let seeder = HabitSeeder(context: context, defaults: defaults, calendar: calendar)
        try seeder.seedIfNeeded(now: today)
        #expect(defaults.bool(forKey: HabitSeeder.seededKey))

        try HabitStore(context: context, calendar: calendar, restDay: nil)
            .resetToDefaults(now: today)

        #expect(defaults.bool(forKey: HabitSeeder.seededKey))
        #expect(try seeder.seedIfNeeded(now: today) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }

    @Test("Resetting twice is resetting once")
    func resetIsIdempotent() throws {
        let (context, store) = try handTypedStore()

        try store.resetToDefaults(now: today)
        try store.resetToDefaults(now: today)

        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
        let rows = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        #expect(rows.map(\.sortOrder) == Array(0..<DefaultHabits.all.count))
    }

    @Test("An empty store resets to the defaults just as well")
    func resetSeedsAnEmptyStore() throws {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)

        #expect(try store.resetToDefaults(now: today) == DefaultHabits.all.count)
        #expect(try context.fetchCount(FetchDescriptor<Habit>()) == DefaultHabits.all.count)
    }
}

/// The gate in front of the reset. It stands in front of the one action that
/// deletes everything at once, so it is a pure rule with assertions on it
/// rather than an expression inside a `.disabled(…)`.
@Suite("Reset confirmation")
struct ResetConfirmationTests {
    @Test("Nothing short of the whole word opens the gate")
    func onlyTheWholeWordConfirms() {
        #expect(!ResetConfirmation.isConfirmed(""))
        #expect(!ResetConfirmation.isConfirmed(" "))
        #expect(!ResetConfirmation.isConfirmed("RESE"))
        #expect(!ResetConfirmation.isConfirmed("RESETT"))
        #expect(!ResetConfirmation.isConfirmed("RE SET"))
        #expect(!ResetConfirmation.isConfirmed("please RESET"))
        #expect(!ResetConfirmation.isConfirmed("delete"))
    }

    @Test("Case and surrounding whitespace are not the point")
    func caseAndPaddingAreForgiven() {
        // Typing `reset` is as deliberate an act as typing `RESET`, and a
        // confirm button that stays dead over a shift key says nothing about
        // why. A trailing space from an autocomplete is not a change of mind.
        #expect(ResetConfirmation.isConfirmed("RESET"))
        #expect(ResetConfirmation.isConfirmed("reset"))
        #expect(ResetConfirmation.isConfirmed("Reset"))
        #expect(ResetConfirmation.isConfirmed(" RESET "))
        #expect(ResetConfirmation.isConfirmed("RESET\n"))
    }

    @Test("The word is declared once")
    func theWordIsShared() {
        // The placeholder, the footer and the check all read this, so a change
        // of word cannot leave the field asking for one thing and the gate
        // waiting for another.
        #expect(ResetConfirmation.word == "RESET")
        #expect(ResetConfirmation.isConfirmed(ResetConfirmation.word))
    }
}
