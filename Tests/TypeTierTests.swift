import Foundation
import Testing
@testable import Glow

/// The two tiers type takes (#334; #603 reversing #335's third step,
/// `docs/week-marks.md` §8.5).
///
/// The table the spec draws, as tests. #335 added a half-strength third step
/// under these — every other weekday, and a label nothing was logged for today
/// — and #603 took it out again: type either asks or it is lit.
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

    @Test("Any other day is lit, whatever the week is doing")
    func otherDaysAreLit() {
        // #603: the header marks today by asking, not by dimming the other six.
        #expect(TypeTier.weekday(isToday: false, anyHabitOpen: true) == .lit)
        #expect(TypeTier.weekday(isToday: false, anyHabitOpen: false) == .lit)
    }

    // MARK: - The habit label

    @Test("A label emits when open and is lit otherwise")
    func labelTakesTwoTiers() {
        #expect(TypeTier.label(isOpenToday: true) == .emitting)
        // Whether or not anything was logged today: a name is not absent, so
        // it is never dimmed for having nothing asked of it (#603).
        #expect(TypeTier.label(isOpenToday: false) == .lit)
    }

    // MARK: - Deriving the state

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

    @Test("A spacer is never open")
    func spacersAreInert() {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completionCounts: [:], isSpacer: true
        )
        #expect(!TypeTier.isOpen(spacer, in: week, today: day(2), restDay: nil, calendar: calendar))
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
