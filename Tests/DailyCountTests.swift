import Foundation
import SwiftData
import Testing
@testable import Glow

/// A habit counted within a day rather than across a week.
///
/// The interesting assertions here are not "twelve is twelve" — they are the
/// three places the new kind meets the old one: that a per-day habit draws no
/// week, that the stored shape of an existing weekly habit did not move, and
/// that a repetition is its own row.
@Suite("Daily count")
struct DailyCountTests {
    private let calendar = TestCalendar.monday
    private let friday = TestCalendar.date(2026, 8, 21)

    // MARK: - The type

    @Test("A per-day count is clamped into 1...12", arguments: [
        (-4, 1), (0, 1), (1, 1), (8, 8), (12, 12), (13, 12), (400, 12),
    ])
    func clamps(input: Int, expected: Int) {
        #expect(Frequency(timesPerDay: input).dailyTarget == expected)
    }

    @Test("Unlike the weekly initializer, no per-day count collapses to another case")
    func noCollapse() {
        // 7x a week *is* daily, so `Frequency(timesPerWeek: 7)` is `.daily`.
        #expect(Frequency(timesPerWeek: 7) == .daily)
        // Once a day is its own cadence with its own drawing, so it stays put.
        for count in Frequency.selectableDailyCounts {
            #expect(Frequency(timesPerDay: count) == .timesPerDay(count))
        }
    }

    @Test("A per-day habit has no week, and says so rather than guessing one")
    func noWeek() {
        let perDay = Frequency(timesPerDay: 3)
        #expect(perDay.slotCount == nil)
        #expect(perDay.weeklyTarget == nil)
        #expect(perDay.isCountedPerDay)

        // And the weekly kinds still answer, unchanged.
        #expect(Frequency.daily.slotCount == 7)
        #expect(Frequency(timesPerWeek: 3).weeklyTarget == 3)
        #expect(!Frequency.daily.isCountedPerDay)
        #expect(Frequency.daily.dailyTarget == nil)
    }

    // MARK: - Where the kinds meet

    @Test("A per-day habit draws no week row and no spans")
    func drawsNoWeek() {
        let week = WeekCalendar.week(containing: friday, calendar: calendar)
        let habit = HabitSnapshot.fixture(
            frequency: Frequency(timesPerDay: 3),
            completedDays: [friday]
        )

        #expect(WeekGrid.slots(
            for: habit, in: week, today: friday, editing: .todayOnly,
            restDay: nil, calendar: calendar
        ).isEmpty)
        #expect(
            WeekSpans.spans(
                for: habit, in: week, today: friday, target: 3,
                editing: .todayOnly, restDay: nil, calendar: calendar
            ).isEmpty
        )
    }

    @Test("Switching to per-day and back restores the weekly cadence it had")
    func roundTrip() {
        let habit = Habit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerWeek: 4),
            createdAt: friday, sortOrder: 0
        )

        habit.frequency = Frequency(timesPerDay: 8)
        #expect(habit.frequency == .timesPerDay(8))
        #expect(habit.isCountedPerDay)

        habit.frequency = .daily
        #expect(habit.frequency == .daily)
        #expect(!habit.isCountedPerDay)
        #expect(habit.timesPerDay == 0)
    }

    @Test("Zero means 'counted across a week', so every habit written before this reads back unchanged")
    func sentinelIsSafe() {
        // The stored default. A row that predates the column has this value and
        // must come back as the weekly habit it was.
        let habit = Habit(
            name: "Read", icon: "book", frequency: Frequency(timesPerWeek: 2),
            createdAt: friday, sortOrder: 0
        )
        #expect(habit.timesPerDay == 0)
        #expect(habit.frequency == .timesPerWeek(2))

        // And no per-day habit can ever store the sentinel, because the count
        // is clamped above zero before it reaches the column.
        habit.frequency = Frequency(timesPerDay: 0)
        #expect(habit.timesPerDay == 1)
        #expect(habit.isCountedPerDay)
    }

    // MARK: - Counting

    @MainActor
    @Test("A repetition is its own row, so a day can hold several")
    func repetitionsAreRows() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 3), now: friday
        )

        #expect(store.count(for: habit, on: friday) == 0)
        #expect(try store.addCompletion(for: habit, on: friday) == 1)
        #expect(try store.addCompletion(for: habit, on: friday) == 2)
        #expect(try store.addCompletion(for: habit, on: friday) == 3)

        // Three rows, one day. This is the shape that merges when two devices
        // sync; a single row carrying a 3 would not.
        #expect((habit.completions ?? []).count == 3)
        #expect(habit.completedDays(in: calendar) == [friday])
        #expect(habit.completionCounts(in: calendar) == [friday: 3])
        #expect(habit.snapshot(calendar: calendar).count(on: friday) == 3)

        #expect(try store.clearDay(for: habit, on: friday) == 3)
        #expect(store.count(for: habit, on: friday) == 0)
        #expect((habit.completions ?? []).isEmpty)
    }

    @MainActor
    @Test("The time of day a repetition is logged at does not split it off its day")
    func normalizesToTheDay() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Walk", icon: "figure.walk", frequency: Frequency(timesPerDay: 2), now: friday
        )

        let morning = friday.addingTimeInterval(9 * 3600)
        let evening = friday.addingTimeInterval(21 * 3600)
        try store.addCompletion(for: habit, on: morning)
        try store.addCompletion(for: habit, on: evening)

        #expect(habit.completionCounts(in: calendar) == [friday: 2])
    }

    @MainActor
    @Test("Clearing one day leaves the others alone")
    func clearIsPerDay() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 4), now: friday
        )
        let thursday = TestCalendar.date(2026, 8, 20)

        try store.addCompletion(for: habit, on: thursday)
        try store.addCompletion(for: habit, on: thursday)
        try store.addCompletion(for: habit, on: friday)

        #expect(try store.clearDay(for: habit, on: friday) == 1)
        #expect(habit.completionCounts(in: calendar) == [thursday: 2])
        #expect(try store.clearDay(for: habit, on: friday) == 0)
    }

    // MARK: - The tap

    @MainActor
    @Test("A tap adds one, and a tap on the full ring clears the day")
    func tapCycle() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 3), now: friday
        )

        #expect(try store.recordTap(for: habit, on: friday) == 1)
        #expect(try store.recordTap(for: habit, on: friday) == 2)
        #expect(try store.recordTap(for: habit, on: friday) == 3)
        // The ring is full; the next tap is the reset, and the reset is the
        // undo — the day's rows are genuinely gone, not marked over.
        #expect(try store.recordTap(for: habit, on: friday) == 0)
        #expect((habit.completions ?? []).isEmpty)
        // And the cycle begins again.
        #expect(try store.recordTap(for: habit, on: friday) == 1)
    }

    @MainActor
    @Test("A count stranded past its target resets like a full ring")
    func tapAfterTargetEdit() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 8), now: friday
        )
        for _ in 0..<5 { try store.addCompletion(for: habit, on: friday) }

        habit.frequency = Frequency(timesPerDay: 3)
        #expect(try store.recordTap(for: habit, on: friday) == 0)
        #expect(store.count(for: habit, on: friday) == 0)
    }

    @MainActor
    @Test("A weekly habit has no ring, so a stray tap changes nothing")
    func tapOnWeeklyIsInert() throws {
        let container = try ModelContainer(
            for: Habit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = HabitStore(context: container.mainContext, calendar: calendar)
        let habit = try store.addHabit(
            name: "Read", icon: "book", frequency: Frequency(timesPerWeek: 3), now: friday
        )
        try store.toggleCompletion(for: habit, on: friday)

        #expect(try store.recordTap(for: habit, on: friday) == 1)
        #expect((habit.completions ?? []).count == 1)
    }

    // MARK: - The snapshot

    @Test("A weekly habit's snapshot counts one per day, so nothing week-shaped can tell the difference")
    func weeklySnapshotIsUnchanged() {
        let monday = TestCalendar.date(2026, 8, 17)
        let snapshot = HabitSnapshot.fixture(completedDays: [monday, friday])

        #expect(snapshot.completedDays == [monday, friday])
        #expect(snapshot.completionCounts == [monday: 1, friday: 1])
        #expect(snapshot.count(on: monday) == 1)
        #expect(snapshot.count(on: TestCalendar.date(2026, 8, 19)) == 0)
    }
}
