import Foundation
import Testing
@testable import Glow

/// The three steps type takes (#335, `docs/week-marks.md` §8.5).
///
/// The table the spec draws, as tests — including the two rows that are new,
/// because before #335 type had two states and the middle one had nowhere to
/// attach.
@Suite("Type tiers")
struct TypeTierTests {
    private let calendar = TestCalendar.monday
    /// The week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    private func habit(_ frequency: Frequency, done: [Int] = []) -> HabitSnapshot {
        .fixture(frequency: frequency, completedDays: Set(done.map { day($0) }))
    }

    // MARK: - The weekday letter

    @Test("Today emits while anything is open, and steps down when nothing is")
    func todayStepsDown() {
        // **The new middle row.** Today's letter used to emit whatever the week
        // was doing, which made the emitting tier say *this is today* rather
        // than *this wants you*. Reserving emission for what is actionable
        // (#334) means today has to give it up once every habit is handled.
        #expect(TypeTier.weekday(isToday: true, anyHabitOpen: true) == .emitting)
        #expect(TypeTier.weekday(isToday: true, anyHabitOpen: false) == .lit)
    }

    @Test("Any other day rests, whatever the week is doing")
    func otherDaysRest() {
        #expect(TypeTier.weekday(isToday: false, anyHabitOpen: true) == .resting)
        #expect(TypeTier.weekday(isToday: false, anyHabitOpen: false) == .resting)
    }

    // MARK: - The habit label

    @Test("A label emits when open, is lit when handled, and rests otherwise")
    func labelTakesThreeSteps() {
        #expect(TypeTier.label(isOpenToday: true, isHandledToday: false) == .emitting)
        #expect(TypeTier.label(isOpenToday: false, isHandledToday: true) == .lit)
        #expect(TypeTier.label(isOpenToday: false, isHandledToday: false) == .resting)
        // Open wins if both are somehow true: what is still asked outranks what
        // is already done, which is the whole ordering of the three tiers.
        #expect(TypeTier.label(isOpenToday: true, isHandledToday: true) == .emitting)
    }

    // MARK: - Deriving the two states

    @Test("Open is asked of WeekGrid, for both cadences")
    func openFollowsTheGrid() {
        let today = day(2)
        // A daily habit with today unlogged, and the same habit logged.
        #expect(TypeTier.isOpen(habit(.daily), in: week, today: today, restDay: nil, calendar: calendar))
        #expect(!TypeTier.isOpen(
            habit(.daily, done: [2]), in: week, today: today, restDay: nil, calendar: calendar
        ))
        // A weekly habit still owing a rep, and one that has met its goal.
        #expect(TypeTier.isOpen(
            habit(.timesPerWeek(3)), in: week, today: today, restDay: nil, calendar: calendar
        ))
        #expect(!TypeTier.isOpen(
            habit(.timesPerWeek(2), done: [0, 1]), in: week, today: today,
            restDay: nil, calendar: calendar
        ))
    }

    @Test("Handled means logged today, not goal met")
    func handledIsAboutToday() {
        // A 2x habit finished on Monday and Tuesday, read on Friday: nothing was
        // asked of it today and nothing was done, so it rests rather than
        // sitting lit all week. This is the distinction the middle step turns
        // on, and the easy version of it — "is the goal met" — gets it wrong.
        let met = habit(.timesPerWeek(2), done: [0, 1])
        #expect(!TypeTier.isHandled(met, today: day(4), restDay: nil, calendar: calendar))
        #expect(TypeTier.isHandled(met, today: day(1), restDay: nil, calendar: calendar))
    }

    @Test("The rest day hands out no tier at all")
    func restDayIsNeverHandled() {
        // #72: the rest day draws nothing and asks nothing, so a completion
        // stored on one does not light its label either.
        let rest = TestPreferences.weekday(ofColumn: 3, in: week)
        #expect(!TypeTier.isHandled(
            habit(.daily, done: [3]), today: day(3), restDay: rest, calendar: calendar
        ))
    }

    @Test("A spacer is neither open nor handled")
    func spacersAreInert() {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completionCounts: [:], isSpacer: true
        )
        #expect(!TypeTier.isOpen(spacer, in: week, today: day(2), restDay: nil, calendar: calendar))
        #expect(!TypeTier.isHandled(spacer, today: day(2), restDay: nil, calendar: calendar))
    }

    @Test("The week is open while any one habit is")
    func anyOpenIsAnyHabit() {
        let today = day(2)
        let done = habit(.daily, done: [2])
        let open = habit(.daily)
        #expect(!TypeTier.anyOpen(
            in: [done, done], week: week, today: today, restDay: nil, calendar: calendar
        ))
        #expect(TypeTier.anyOpen(
            in: [done, open], week: week, today: today, restDay: nil, calendar: calendar
        ))
        // An empty week asks nothing, so today's letter is lit rather than
        // emitting — the same answer a fully handled week gives.
        #expect(!TypeTier.anyOpen(
            in: [], week: week, today: today, restDay: nil, calendar: calendar
        ))
    }
}
