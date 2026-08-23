import Foundation
import SwiftData
import Testing
@testable import Glow

/// #204: the day the app is willing to believe it is.
///
/// These read and write the real `DebugToday` key, which under a test bundle
/// lives in a private per-process defaults suite rather than the App Group —
/// `GlowSettings.store` does that, and `TestIsolationTests` asserts it. Every
/// test here still clears on the way out: a value that outlives its test is the
/// bug #168 was, and this one decides what day a write is dated to.
@Suite("Debug: override today")
struct DebugTodayTests {
    private let calendar = TestCalendar.monday

    /// The real current week, in the suite's own calendar. The override is
    /// scoped to "this week" against the real clock, so a fixture week cannot
    /// stand in for it — these have to use the week the run is happening in.
    private var realWeek: Week {
        WeekCalendar.week(
            containing: WeekCalendar.realToday(calendar: calendar), calendar: calendar
        )
    }

    private var realToday: Date { WeekCalendar.realToday(calendar: calendar) }

    /// A day of this real week that is not the real today, so that every
    /// assertion below distinguishes the override from the fallback.
    private var otherDay: Date {
        realWeek.days.first { $0 != realToday } ?? realWeek.days[0]
    }

    // MARK: - Resolving

    @Test("With nothing set, today is the real day")
    func fallsBackToTheRealDay() {
        DebugToday.clearOnLaunch()
        #expect(DebugToday.override(calendar: calendar) == nil)
        #expect(WeekCalendar.today(calendar: calendar) == realToday)
        #expect(DebugToday.isActive(calendar: calendar) == false)
    }

    @Test("An override inside this week is what today means")
    func anOverrideInThisWeekResolves() {
        defer { DebugToday.clearOnLaunch() }
        DebugToday.set(otherDay, calendar: calendar)

        #expect(DebugToday.override(calendar: calendar) == otherDay)
        #expect(WeekCalendar.today(calendar: calendar) == otherDay)
        #expect(DebugToday.isActive(calendar: calendar))
        // The real day is still reachable, which is the half the banner says.
        #expect(WeekCalendar.realToday(calendar: calendar) == realToday)
    }

    @Test("Any instant of the chosen day is stored as that day's midnight")
    func theStoredValueIsAMidnight() {
        defer { DebugToday.clearOnLaunch() }
        // The value is compared against the week's midnights by equality, so a
        // stored instant of 09:14 would resolve to nothing at all — an
        // override that silently did nothing is the worst of the failures
        // available here.
        DebugToday.set(otherDay.addingTimeInterval(9 * 3600 + 14 * 60), calendar: calendar)

        #expect(DebugToday.override(calendar: calendar) == otherDay)
    }

    // MARK: - Expiring

    @Test("A day from another week resolves to nothing and clears itself")
    func aStaleOverrideExpires() {
        defer { DebugToday.clearOnLaunch() }
        // The other side of "the real day advances into the next week": the
        // clock cannot be moved in a test, so the stored day is moved instead.
        // What the check compares is the same comparison either way.
        DebugToday.set(realToday.addingTimeInterval(-14 * 24 * 3600), calendar: calendar)

        #expect(DebugToday.override(calendar: calendar) == nil)
        #expect(WeekCalendar.today(calendar: calendar) == realToday)
        // Cleared, not merely ignored. An override that reads as off while the
        // key is still there comes back the moment the weeks line up again.
        #expect(GlowSettings.store.object(forKey: DebugToday.key) == nil)
    }

    @Test("Turning it off leaves nothing behind")
    func clearingRemovesTheKey() {
        defer { DebugToday.clearOnLaunch() }
        DebugToday.set(otherDay, calendar: calendar)
        DebugToday.set(nil, calendar: calendar)

        #expect(GlowSettings.store.object(forKey: DebugToday.key) == nil)
        #expect(WeekCalendar.today(calendar: calendar) == realToday)
    }

    @Test("A launch clears an override the last session left on")
    func launchClearsIt() {
        defer { DebugToday.clearOnLaunch() }
        DebugToday.set(otherDay, calendar: calendar)
        #expect(DebugToday.isActive(calendar: calendar))

        // The call `GlowApp.init` makes, before the store is opened.
        DebugToday.clearOnLaunch()

        #expect(DebugToday.override(calendar: calendar) == nil)
        #expect(GlowSettings.store.object(forKey: DebugToday.key) == nil)
    }

    // MARK: - What the picker offers

    @Test("The days offered are the real week's, whatever the override says")
    func theChoicesAreTheRealWeek() {
        defer { DebugToday.clearOnLaunch() }
        DebugToday.set(otherDay, calendar: calendar)

        let choices = DebugToday.choices(calendar: calendar)
        #expect(choices == realWeek.days)
        #expect(choices.contains(realToday))
        // Offering the *overridden* week would let the picker walk out of the
        // week it was set within, one day at a time, and every step of that
        // walk would look legitimate to the staleness check.
        #expect(choices.count == 7)
    }

    @Test("A day names itself in the calendar it came from")
    func daysAreNamed() {
        // en_GB, from `TestCalendar.monday`, so the name is not the machine's.
        #expect(DebugToday.dayName(TestCalendar.date(2026, 8, 19), calendar: calendar) == "Wednesday")
        #expect(DebugToday.dayName(TestCalendar.date(2026, 8, 23), calendar: calendar) == "Sunday")
    }

    // MARK: - The write path

    /// The claim that makes this a simulation rather than a preview.
    ///
    /// `toggleCompletion` refuses a day ahead of today, and "today" is the one
    /// thing the override moves. Which direction this test proves depends on
    /// what day it runs on, and both directions are real: from any day but the
    /// week's first, the override is set *backwards* and a write that would
    /// otherwise be accepted is refused; on the week's first day it is set
    /// *forwards* and a write that would otherwise be refused is accepted.
    @Test("A tap is dated to the overridden day, and the future guard moves with it")
    @MainActor
    func theWriteFollowsTheOverride() throws {
        defer { DebugToday.clearOnLaunch() }
        let container = try ModelContainer(
            for: Habit.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = HabitStore(context: context, calendar: calendar, restDay: nil)
        let habit = try store.addHabit(name: "Walk", icon: "🚶", frequency: .daily)

        let isFirstDay = realToday == realWeek.days[0]
        let overridden = isFirstDay ? realWeek.days[6] : realWeek.days[0]
        let refused = calendar.date(byAdding: .day, value: 1, to: overridden) ?? overridden
        DebugToday.set(overridden, calendar: calendar)

        #expect(try store.toggleCompletion(for: habit, on: overridden) == .completed)
        #expect(try store.toggleCompletion(for: habit, on: refused) == .refused)

        // The row is dated to the simulated day, not to the real one — which
        // is exactly why this tool has a banner and a launch reset.
        let completions = try context.fetch(FetchDescriptor<Completion>())
        #expect(completions.count == 1)
        #expect(completions.first?.dayID == DayID(overridden, calendar: calendar))
        if !isFirstDay {
            // Without the override this write would have landed: `refused` is
            // the second day of the week, and today is later than that.
            #expect(refused <= realToday)
        }
    }
}
