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

    @Test("Deleting a habit takes its completions with it and leaves a blank row")
    func deleteClearsTheHabitButKeepsThePosition() throws {
        let context = try makeContext()
        let store = makeStore(context)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)
        try store.toggleCompletion(for: habit, on: today)
        try store.toggleCompletion(for: habit, on: TestCalendar.date(2026, 8, 18))

        try store.delete(habit)

        // The habit is gone; the row it occupied is not. Collapsing the row
        // would pull every habit below it up a line and silently regroup a
        // layout the user arranged.
        let rows = try context.fetch(FetchDescriptor<Habit>())
        #expect(rows.count == 1)
        #expect(rows.first?.isSpacer == true)
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
        let slots = WeekGrid.slots(for: snapshot, in: week, today: today, editing: .todayOnly, calendar: calendar)
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
