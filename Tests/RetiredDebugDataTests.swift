import Foundation
import SwiftData
import Testing
@testable import Glow

/// The launch purge that replaced Demo history and Debug: Override Today
/// (#628). Those tools are gone from the app, and so is the only code that
/// could take out what they wrote — so what an install already holds has to go
/// at launch, and nothing a person logged may go with it.
@Suite("Retired debug data")
@MainActor
struct RetiredDebugDataTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "retired-debug-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    /// The keys are the ones the removed tools wrote. Spelled out, because the
    /// code that defined them is gone and a typo here would purge nothing.
    @Test("The keys are the ones the removed tools wrote")
    func keysMatchWhatWasWritten() {
        #expect(RetiredDebugData.debugTodayKey == "debugTodayOverride")
        #expect(RetiredDebugData.demoLegacyIDsKey == "demoHistoryCompletionIDs")
    }

    @Test("Invented rows go, and a completion the person logged on the same day stays")
    func inventedRowsGoRealRowsStay() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        let session = UUID()
        for offset in [-3, -2, -1] {
            context.insert(Completion(day: day(offset), habit: habit, demoSessionID: session, calendar: calendar))
        }
        try context.save()
        // A real tap on a day the demo also filled.
        #expect(try store.addCompletion(for: habit, on: day(-2)) == 2)

        #expect(try RetiredDebugData.purge(context: context, defaults: makeDefaults()) == 3)

        let left = try context.fetch(FetchDescriptor<Completion>())
        #expect(left.count == 1)
        #expect(left.first?.demoSessionID == nil)
        #expect(left.first?.dayID == DayID(day(-2), calendar: calendar))
    }

    @Test("Rows a pre-provenance demo recorded in the defaults go, and so does the key")
    func legacyRecordIsPurged() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let defaults = makeDefaults()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Read", icon: "📖", frequency: .daily)

        // Unstamped rows whose ids the old demo wrote into the App Group.
        let named = [day(-4), day(-3)].map { Completion(day: $0, habit: habit, calendar: calendar) }
        for completion in named { context.insert(completion) }
        try context.save()
        defaults.set(named.map(\.id.uuidString) + [UUID().uuidString], forKey: RetiredDebugData.demoLegacyIDsKey)
        #expect(try store.addCompletion(for: habit, on: day(-1)) == 1)

        #expect(try RetiredDebugData.purge(context: context, defaults: defaults) == 2)

        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)
        #expect(defaults.stringArray(forKey: RetiredDebugData.demoLegacyIDsKey) == nil)
    }

    @Test("The override key is removed")
    func overrideKeyIsRemoved() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let defaults = makeDefaults()
        defaults.set(today, forKey: RetiredDebugData.debugTodayKey)

        #expect(try RetiredDebugData.purge(context: context, defaults: defaults) == 0)

        #expect(defaults.object(forKey: RetiredDebugData.debugTodayKey) == nil)
    }

    @Test("A second launch purges nothing and changes nothing")
    func purgeIsIdempotent() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let defaults = makeDefaults()
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Stretch", icon: "figure.cooldown", frequency: .daily)
        context.insert(Completion(day: day(-1), habit: habit, demoSessionID: UUID(), calendar: calendar))
        try context.save()
        #expect(try store.addCompletion(for: habit, on: today) == 1)

        #expect(try RetiredDebugData.purge(context: context, defaults: defaults) == 1)
        #expect(try RetiredDebugData.purge(context: context, defaults: defaults) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)
        #expect(!context.hasChanges)
    }
}
