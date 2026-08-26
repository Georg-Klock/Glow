import Foundation
import SwiftData
import Testing
@testable import Glow

/// #282: a failed read must never wear the empty state's words.
///
/// The widget stores used to encode "the container did not open", "the fetch
/// failed" and "the store holds nothing" as one empty array, and the views
/// drew all three as "No habits yet" — a database failure rendered as the
/// deletion of every habit. `StoreRead` keeps the three answers apart; these
/// tests hold the mapping at the boundary that produces it.
///
/// The failure is injected through the stores' `container:` parameter, because
/// that is the seam: the simulator cannot be made to fail a container open on
/// demand, and a mock of the store would be the mirror-copy testing this
/// repository forbids. A `nil` container is exactly what
/// `GlowStore.makeReadOnlyContainer()` hands these functions when the real
/// open fails.
@MainActor
@Suite("Failure is not empty")
struct StoreReadStateTests {
    // MARK: - The type

    @Test("The collection factory keeps the three answers apart")
    func factoryMapsThreeWays() {
        #expect(StoreRead<[Int]>(read: nil) == .unavailable)
        #expect(StoreRead<[Int]>(read: []) == .empty)
        #expect(StoreRead(read: [7]) == .loaded([7]))
    }

    @Test("Value and unavailability read back")
    func accessors() {
        #expect(StoreRead.loaded([3]).value == [3])
        #expect(StoreRead<[Int]>.empty.value == nil)
        #expect(StoreRead<[Int]>.unavailable.value == nil)
        #expect(StoreRead<[Int]>.unavailable.isUnavailable)
        #expect(!StoreRead<[Int]>.empty.isUnavailable)
    }

    // MARK: - Fixtures

    private func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: GlowStore.schema,
            configurations: ModelConfiguration(schema: GlowStore.schema, url: url)
        )
    }

    @discardableResult
    private func seed(
        _ container: ModelContainer, name: String, day: Date? = nil
    ) throws -> Habit {
        let context = ModelContext(container)
        let habit = Habit(
            name: name, icon: "figure.run", frequency: .daily,
            createdAt: TestCalendar.date(2026, 8, 1), sortOrder: 0
        )
        context.insert(habit)
        if let day {
            let completion = Completion(day: day, habit: habit, calendar: TestCalendar.monday)
            context.insert(completion)
            habit.completions?.append(completion)
        }
        try context.save()
        return habit
    }

    // MARK: - The week widget's boundary

    @Test("A missing container is unavailable, not an empty week")
    func weekRowsWithoutContainer() {
        TestPreferences.withWeek(firstWeekday: 2) {
            let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 19))
            #expect(WeekWidgetStore.rows(chosen: nil, in: week, container: nil) == .unavailable)
        }
    }

    @Test("A store with nothing in it is empty, and one with rows is loaded")
    func weekRowsDistinguishEmptyFromLoaded() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let url = TestStore.url()
            defer { TestStore.discard(url) }
            let container = try container(at: url)
            let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 19))

            #expect(WeekWidgetStore.rows(chosen: nil, in: week, container: container) == .empty)

            let habit = try seed(container, name: "Gym", day: TestCalendar.date(2026, 8, 18))
            let read = WeekWidgetStore.rows(chosen: nil, in: week, container: container)
            let rows = try #require(read.value)
            #expect(rows.map(\.id) == [habit.id])
            // The read carries the history too — a loaded row with a silently
            // empty week would be the same bug one layer down.
            #expect(rows[0].completionCounts.values.reduce(0, +) == 1)
        }
    }

    @Test("The picker's read throws rather than offering an empty list")
    func rowNamesThrowWithoutContainer() {
        #expect(throws: GlowStore.Unreadable.self) {
            _ = try WeekWidgetStore.rowNames(container: nil)
        }
        #expect(throws: GlowStore.Unreadable.self) {
            _ = try MonthStore.weeklyNames(container: nil)
        }
    }

    // MARK: - The month widget's boundary

    @Test("The month keeps unavailable, empty and loaded apart")
    func monthReadsThreeWays() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let date = TestCalendar.date(2026, 8, 19)
            #expect(
                MonthStore.month(of: nil, containing: date, container: nil) == .unavailable
            )

            let url = TestStore.url()
            defer { TestStore.discard(url) }
            let container = try container(at: url)
            #expect(MonthStore.month(of: nil, containing: date, container: container) == .empty)

            let habit = try seed(container, name: "Gym", day: date)
            let loaded = MonthStore.month(of: nil, containing: date, container: container)
            #expect(loaded.value?.id == habit.id)

            // A chosen habit that no longer exists is genuinely nothing to
            // show — the widget's own empty words — not a failure.
            let gone = MonthStore.month(of: UUID(), containing: date, container: container)
            #expect(gone == .empty)
        }
    }

    // MARK: - The throwing snapshot path

    @Test("Fetched snapshots agree with the non-throwing ones on a real store")
    func fetchedSnapshotsMatch() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        let container = try container(at: url)
        let habit = try seed(container, name: "Gym", day: TestCalendar.date(2026, 8, 18))

        let context = ModelContext(container)
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let fetched = try Habit.fetchedSnapshots(of: habits, calendar: TestCalendar.monday)
        let plain = habits.map { $0.snapshot(calendar: TestCalendar.monday) }
        #expect(fetched == plain)
        #expect(fetched.first?.id == habit.id)
    }

    @Test("Fixtures snapshot without a store, and without failing")
    func fetchedSnapshotsOnFixtures() throws {
        let habit = Habit(
            name: "Gym", icon: "figure.run", frequency: .daily,
            createdAt: TestCalendar.date(2026, 8, 1), sortOrder: 0
        )
        let snapshots = try Habit.fetchedSnapshots(of: [habit], calendar: TestCalendar.monday)
        #expect(snapshots.count == 1)
        #expect(snapshots[0].completionCounts.isEmpty)
    }
}
