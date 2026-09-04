import Foundation
import SwiftData
import Testing
@testable import Glow

@Suite("Persistence")
@MainActor
struct PersistenceTests {
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

    @Test("A habit round-trips through the store")
    func habitRoundTrip() throws {
        let context = try makeContext()
        let store = makeStore(context)

        try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(4))

        let fetched = try context.fetch(FetchDescriptor<Habit>())
        #expect(fetched.count == 1)
        let habit = try #require(fetched.first)
        #expect(habit.name == "Read")
        #expect(habit.icon == "📖")
        #expect(habit.frequency == .timesPerWeek(4))
    }

    @Test("Toggling twice leaves no completion behind")
    func toggleIsReversible() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        #expect(try store.toggleCompletion(for: habit, on: today) == .completed)
        #expect(try context.fetch(FetchDescriptor<Completion>()).count == 1)

        #expect(try store.toggleCompletion(for: habit, on: today) == .uncompleted)
        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)
        #expect(habit.completedDays(in: calendar).isEmpty)
    }

    /// **The assumption #318 removed a hot line on, held to explicitly.**
    ///
    /// `setCompletion` used to keep `habit.completions` in step by hand —
    /// `?.append` on an insert, `?.removeAll` on a delete. That is a to-many
    /// relationship, and reading it faults every completion the habit has ever
    /// had, which is why a tap cost the whole record. The lines went on the
    /// grounds that SwiftData maintains the inverse from `Completion.habit`
    /// alone, which the initializer sets and `context.delete` clears.
    ///
    /// That is a claim about the framework rather than about this app, so it
    /// is asserted rather than trusted: if a future SwiftData stops
    /// maintaining the inverse in memory, this fails here rather than showing
    /// up as a stale array somewhere that reads one.
    @Test("The inverse relationship is maintained without being told")
    func theInverseIsMaintainedWithoutBeingTold() throws {
        let context = try makeContext()
        let habit = Habit(
            name: "Walk", icon: "🚶", frequency: .daily, createdAt: today, sortOrder: 0
        )
        context.insert(habit)
        try context.save()
        // Read before the write, so what follows is the in-memory array being
        // kept up to date rather than a first read of the store.
        #expect(habit.completions?.isEmpty == true)

        let completion = Completion(day: today, habit: habit, calendar: calendar)
        context.insert(completion)
        try context.save()
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.id == completion.id)

        context.delete(completion)
        try context.save()
        #expect(habit.completions?.isEmpty == true)
    }

    /// And the same thing through the write path the tap actually takes.
    @Test("A toggle leaves the habit's own array agreeing with the store")
    func togglingKeepsTheArrayAgreeingWithTheStore() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)
        #expect(habit.completions?.isEmpty == true)

        #expect(try store.toggleCompletion(for: habit, on: today) == .completed)
        #expect(habit.completions?.count == 1)
        #expect(habit.completions?.first?.dayID == DayID(today, calendar: calendar))

        #expect(try store.toggleCompletion(for: habit, on: today) == .uncompleted)
        #expect(habit.completions?.isEmpty == true)
    }

    @Test("Two taps on the same day never store two completions")
    func noDuplicateCompletionsPerDay() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        // Different instants within the same day must collapse to one record.
        try store.toggleCompletion(for: habit, on: today.addingTimeInterval(60))
        try store.toggleCompletion(for: habit, on: today.addingTimeInterval(3600 * 20))

        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)

        try store.toggleCompletion(for: habit, on: today.addingTimeInterval(3600 * 9))
        let stored = try context.fetch(FetchDescriptor<Completion>())
        #expect(stored.count == 1)
        #expect(stored.first?.day == today)
    }

    @Test("Completions are stored at midnight, not at the moment of tapping")
    func completionsAreNormalized() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        try store.toggleCompletion(for: habit, on: today.addingTimeInterval(3600 * 22 + 1800))

        let completion = try #require(context.fetch(FetchDescriptor<Completion>()).first)
        #expect(completion.day == today)
    }

    @Test("Deleting a habit takes its completions and its row with it")
    func deleteClearsTheHabitButKeepsThePosition() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)
        try store.toggleCompletion(for: habit, on: today)
        try store.toggleCompletion(for: habit, on: TestCalendar.date(2026, 8, 18))

        try store.delete(habit)

        // The habit is gone and so is its row (#257). It used to leave a blank
        // row behind, which read as a delete that had not worked.
        let rows = try context.fetch(FetchDescriptor<Habit>())
        #expect(rows.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)
    }

    @Test("The store refuses a day that has not happened yet")
    func futureDaysAreRefused() throws {
        let context = try makeContext()
        // Real time rather than a fixture week: the guard is about *ahead of
        // now*, and a fixture that drifts into the past would stop testing it.
        let tomorrow = Date().addingTimeInterval(24 * 60 * 60)

        try TestPreferences.withWeek(restDay: nil) {
            let store = HabitStore(context: context)
            let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

            // A completion logged ahead is a claim about something that has not
            // happened. Refused on the path every surface shares, so a week
            // rendered while the demo was in cannot write one after it went
            // out. The calls are hoisted out of the macro: `#expect` around a
            // `try` inside a rethrowing closure does not compile.
            let refused = try store.toggleCompletion(for: habit, on: tomorrow)
            #expect(refused == .refused)
            let none = try context.fetch(FetchDescriptor<Completion>())
            #expect(none.isEmpty)

            // Demo history is the exception, and it says so at the call site.
            let logged = try store.toggleCompletion(
                for: habit, on: tomorrow, allowingFuture: true
            )
            #expect(logged == .completed)
            let one = try context.fetch(FetchDescriptor<Completion>())
            #expect(one.count == 1)

            // And an invented future can be taken back the same way.
            let undone = try store.toggleCompletion(
                for: habit, on: tomorrow, allowingFuture: true
            )
            #expect(undone == .uncompleted)

            // Today is not the future, however late in the day it is.
            let now = try store.toggleCompletion(for: habit, on: Date())
            #expect(now == .completed)
        }
    }

    @Test("Correcting a day in an earlier week is not a new kind of write")
    func earlierWeeksAreTheSameWrite() throws {
        let context = try makeContext()
        // Three weeks back, which is a week the pager reaches and the current
        // week does not contain. The store's guard is *ahead of now*, and a
        // day three weeks ago is behind it exactly as Monday is — which is why
        // #117 added no rule here. The floor the pager stops at is a bound on
        // navigation, not on what a record may hold.
        let longAgo = Date().addingTimeInterval(-21 * 24 * 60 * 60)

        try TestPreferences.withWeek(restDay: nil) {
            let store = HabitStore(context: context)
            let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

            let logged = try store.toggleCompletion(for: habit, on: longAgo)
            #expect(logged == .completed)
            let one = try context.fetch(FetchDescriptor<Completion>())
            #expect(one.count == 1)
            #expect(one.first?.day == WeekCalendar.day(longAgo))

            let undone = try store.toggleCompletion(for: habit, on: longAgo)
            #expect(undone == .uncompleted)
        }
    }

    @Test("A blank row in an earlier week is still refused")
    func earlierWeeksDoNotReopenABlankRow() throws {
        let context = try makeContext()
        let longAgo = Date().addingTimeInterval(-21 * 24 * 60 * 60)

        try TestPreferences.withWeek(restDay: nil) {
            let store = HabitStore(context: context)
            let spacer = try store.addSpacer()
            let refused = try store.toggleCompletion(for: spacer, on: longAgo)
            #expect(refused == .refused)
            #expect(try context.fetch(FetchDescriptor<Completion>()).isEmpty)
        }
    }

    @Test("The record's start is the earlier of the first habit and the first completion")
    func earliestRecordedDayReadsBothTables() throws {
        let context = try makeContext()
        let store = makeStore(context)

        #expect(store.earliestRecordedDay() == nil)

        let habit = try store.addHabit(
            name: "Walk", icon: "🚶", frequency: .daily, now: today
        )
        #expect(store.earliestRecordedDay() == today)

        // A demo invents completions weeks before the habits that carry them,
        // so the completion table is not a detail the reach can skip.
        let invented = TestCalendar.date(2026, 6, 15)
        context.insert(Completion(day: invented, habit: habit))
        try context.save()
        #expect(store.earliestRecordedDay() == invented)
    }

    /// **A habit with no creation date on record does not start the record**
    /// (#186).
    ///
    /// `Habit.createdAt` defaults to `Habit.unknownCreation` — `.distantPast` —
    /// for every row written before the column existed, and it sorts before
    /// every real date, so the `min` this function takes used to answer with
    /// the year 1 for any store holding one. That was survivable only because
    /// the pager was capped at twelve weeks; with the cap gone it would be a
    /// scroll with no end, so the sentinel is refused where the tables are read
    /// rather than clamped where they are used.
    @Test("A habit with no creation date on record does not start the record")
    func unknownCreationDoesNotStartTheRecord() throws {
        let context = try makeContext()
        let store = makeStore(context)

        let legacy = Habit(
            name: "Walk", icon: "🚶", frequency: .daily,
            createdAt: Habit.unknownCreation, sortOrder: 0
        )
        context.insert(legacy)
        try context.save()
        #expect(!legacy.hasKnownCreation)

        // **Nil, not the year 1 and not today.** Nothing is known about when
        // this habit began, and that is the same answer a fresh install gives:
        // the pager stays on this week rather than opening weeks the record
        // cannot vouch for. See `HabitStore.earliestRecordedDay`.
        #expect(store.earliestRecordedDay() == nil)

        // Its completions are still the record — a day logged is a day that
        // happened, whatever the row that carries it knows about itself.
        let logged = TestCalendar.date(2026, 6, 15)
        context.insert(Completion(day: logged, habit: legacy, calendar: calendar))
        try context.save()
        #expect(store.earliestRecordedDay() == logged)
    }

    /// The sentinel row is exactly the row an ascending sort returns first, so
    /// a limit of one over an unfiltered fetch hands it back and hides every
    /// real creation date behind it. Two habits, one of each kind, and the
    /// answer has to be the real one (#186).
    @Test("A row with no creation date does not hide the rows that have one")
    func unknownCreationDoesNotMaskARealOne() throws {
        let context = try makeContext()
        let store = makeStore(context)

        context.insert(
            Habit(
                name: "Walk", icon: "🚶", frequency: .daily,
                createdAt: Habit.unknownCreation, sortOrder: 0
            )
        )
        let made = TestCalendar.date(2026, 7, 6)
        context.insert(
            Habit(name: "Read", icon: "📖", frequency: .daily, createdAt: made, sortOrder: 1)
        )
        try context.save()

        #expect(store.earliestRecordedDay() == made)
    }

    @Test("Permission to write ahead is not permission to write on the rest day")
    func theRestDayOutranksTheDemo() throws {
        let context = try makeContext()
        let tomorrow = Date().addingTimeInterval(24 * 60 * 60)
        let weekday = Calendar.current.component(.weekday, from: tomorrow)

        try TestPreferences.withWeek(restDay: weekday) {
            let store = HabitStore(context: context)
            let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)
            let outcome = try store.toggleCompletion(
                for: habit, on: tomorrow, allowingFuture: true
            )
            #expect(outcome == .refused)
            let stored = try context.fetch(FetchDescriptor<Completion>())
            #expect(stored.isEmpty)
        }
    }

    @Test("New habits are appended, not prepended")
    func sortOrderIncrements() throws {
        let context = try makeContext()
        let store = makeStore(context)

        let first = try store.addHabit(name: "One", icon: "1️⃣", frequency: .daily)
        let second = try store.addHabit(name: "Two", icon: "2️⃣", frequency: .daily)
        let third = try store.addHabit(name: "Three", icon: "3️⃣", frequency: .daily)

        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
        #expect(third.sortOrder == 2)
    }

    @Test("Reordering rewrites sort order across the whole list")
    func reorderRewritesOrder() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let a = try store.addHabit(name: "A", icon: "🅰️", frequency: .daily)
        let b = try store.addHabit(name: "B", icon: "🅱️", frequency: .daily)
        let c = try store.addHabit(name: "C", icon: "©️", frequency: .daily)

        try store.reorder([a, b, c], from: IndexSet(integer: 2), to: 0)

        #expect(c.sortOrder == 0)
        #expect(a.sortOrder == 1)
        #expect(b.sortOrder == 2)
    }

    /// #556: a `List` may report one drag as two moves, each relative to the
    /// order after the previous one, while the view's `@Query` array still
    /// holds the order from before the first. The runner's recording showed
    /// row 3 carried to the top and the list then re-rendering as 2, 1, 3, 4,
    /// 5 — "offset 1 to 0" applied to the stale array. The offsets belong to
    /// the stored order.
    @Test("Reordering applies the offsets to the stored order, not the array as handed in")
    func reorderAppliesOffsetsToTheStoredOrder() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habits = try ["A", "B", "C", "D", "E"].map {
            try store.addHabit(name: $0, icon: "🔤", frequency: .daily)
        }
        let (a, b, c, d, e) = (habits[0], habits[1], habits[2], habits[3], habits[4])

        // Row C carried upward past B: the first step the List reports.
        try store.reorder(habits, from: IndexSet(integer: 2), to: 1)
        #expect([a, c, b, d, e].map(\.sortOrder) == [0, 1, 2, 3, 4])

        // The second step, C past A, arrives with offsets relative to the
        // order after the first — and with the array the query has not yet
        // republished. Applied literally to that array it would move B.
        try store.reorder(habits, from: IndexSet(integer: 1), to: 0)
        #expect([c, a, b, d, e].map(\.sortOrder) == [0, 1, 2, 3, 4])

        // And a fresh array is unaffected: the sort is a no-op on it.
        try store.reorder([c, a, b, d, e], from: IndexSet(integer: 4), to: 0)
        #expect([e, c, a, b, d].map(\.sortOrder) == [0, 1, 2, 3, 4])
    }

    @Test("A stored habit produces the snapshot the grid draws from")
    func snapshotReflectsStoredState() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(3))
        try store.toggleCompletion(for: habit, on: today)

        let snapshot = habit.snapshot(calendar: calendar)
        #expect(snapshot.name == "Read")
        #expect(snapshot.frequency == .timesPerWeek(3))
        #expect(snapshot.completedDays == [today])

        // And the grid agrees that today is spent.
        let week = WeekCalendar.week(containing: today, calendar: calendar)
        let slots = WeekGrid.slots(
            for: snapshot, in: week, today: today, editing: .todayOnly,
            restDay: nil, calendar: calendar
        )
        #expect(slots.map(\.state) == [.filled, .inactive, .inactive])
    }

    @Test("Whitespace around a name is trimmed on the way in")
    func namesAreTrimmed() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "  Stretch \n", icon: "🧘", frequency: .daily)
        #expect(habit.name == "Stretch")
    }

    @Test("Habits and completions survive the store being closed and reopened")
    func survivesRelaunch() throws {
        // An in-memory container cannot answer this, and "restarting preserves
        // everything" is an acceptance criterion, so this one goes to disk.
        let storeURL = URL.temporaryDirectory.appending(path: "glow-relaunch-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let configuration = ModelConfiguration(url: storeURL)

        let habitID: UUID
        do {
            let container = try ModelContainer(for: Habit.self, Completion.self, configurations: configuration)
            let context = ModelContext(container)
            let store = HabitStore(context: context, calendar: calendar)
            let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .timesPerWeek(4))
            habitID = habit.id
            try store.toggleCompletion(for: habit, on: today)
            try store.toggleCompletion(for: habit, on: TestCalendar.date(2026, 8, 17))
        }

        // A second container over the same file is as close to a relaunch as a
        // unit test gets.
        let reopened = try ModelContainer(for: Habit.self, Completion.self, configurations: configuration)
        let context = ModelContext(reopened)
        let habits = try context.fetch(FetchDescriptor<Habit>())

        #expect(habits.count == 1)
        let habit = try #require(habits.first)
        #expect(habit.id == habitID)
        #expect(habit.name == "Read")
        #expect(habit.frequency == .timesPerWeek(4))
        #expect(habit.completedDays(in: calendar) == [today, TestCalendar.date(2026, 8, 17)])
    }
}
