import Foundation
import Testing
@testable import Glow

@Suite("Slot states")
struct WeekGridTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    /// Every test in this suite runs on a week with **no rest day** unless it
    /// asks for one, said out loud rather than inherited. This suite asserts
    /// R1, R2, R5 and R7 —
    /// including the exhaustive pass over all 128 completion histories — and a
    /// rest day arriving from elsewhere would change slot states underneath it
    /// (#105).
    ///
    /// Since #181 that is a property of the call rather than a hope about what
    /// else is running: the rest day is an argument, so nothing outside this
    /// file can set one for these assertions.
    ///
    /// `.todayOnly` unless a test says otherwise, so every assertion written
    /// before #116 still asserts what it was written to assert: the widget's
    /// rule, which is also what the app's rule used to be.
    private func slots(
        _ habit: HabitSnapshot,
        editing: SlotEditing = .todayOnly,
        restDay: Int? = nil
    ) -> [Slot] {
        WeekGrid.slots(
            for: habit, in: week, today: today, editing: editing,
            restDay: restDay, calendar: calendar
        )
    }

    // MARK: - Daily

    @Test("A daily habit shows exactly seven circles")
    func dailyRowHasSevenSlots() {
        #expect(slots(.fixture()).count == 7)
    }

    @Test("Today is open, past days are missed, future days are inactive")
    func dailyStates() {
        let row = slots(.fixture())

        // A day gone by without a completion is a different fact from a day
        // that has not arrived, and the grid draws them differently. They were
        // the same state until the states were separated.
        #expect(row[0].state == .missed)    // Monday, gone
        #expect(row[1].state == .missed)    // Tuesday, gone
        #expect(row[2].state == .open)      // Wednesday, today
        #expect(row[3].state == .inactive)  // Thursday, not yet
        #expect(row[6].state == .inactive)
    }

    @Test("A completion today and a completion on Monday are the same state, different marks")
    func marksSeparateTodayFromHistory() {
        let habit = HabitSnapshot.fixture(completedDays: [
            TestCalendar.date(2026, 8, 17),
            today
        ])
        let row = slots(habit)

        #expect(row[0].state == .filled)
        #expect(row[2].state == .filled)
        // Only today's completion is lit. This is the whole hierarchy: an
        // achievement stops asking for attention the moment it is recorded.
        #expect(row[0].mark == .donePast)
        #expect(row[2].mark == .doneToday)
    }

    @Test("Every state maps to exactly one mark")
    func markCoverage() {
        let row = slots(.fixture())

        #expect(row[0].mark == .missed)
        #expect(row[2].mark == .openToday)
        #expect(row[3].mark == .upcoming)
    }

    @Test("A habit due a number of times a week can never miss")
    func frequencyRowsNeverMiss() {
        // An empty slot on Wednesday is not a failure when the week is still
        // winnable, so these rows have no past to have missed.
        for target in 2...6 {
            let row = slots(.fixture(frequency: .timesPerWeek(target)))
            #expect(!row.contains { $0.state == .missed }, "\(target)x per week produced a miss")
            #expect(!row.contains { $0.mark == .missed })
        }
    }

    @Test("A completed day is filled, including today")
    func dailyCompleted() {
        let habit = HabitSnapshot.fixture(completedDays: [
            TestCalendar.date(2026, 8, 17),
            today
        ])
        let row = slots(habit)

        #expect(row[0].state == .filled)
        #expect(row[2].state == .filled)
        // Filled today is still tappable, so a mistaken tap can be undone.
        #expect(row[2].isTappable)
    }

    @Test("Only today's slot is tappable")
    func dailyTappability() {
        let row = slots(.fixture())
        let tappable = row.filter(\.isTappable)

        #expect(tappable.count == 1)
        #expect(tappable.first?.index == 2)
        #expect(tappable.first?.actionDay == today)
    }

    // MARK: - Times per week

    @Test("An N-times-per-week habit shows exactly N pills", arguments: 2...6)
    func frequencyRowSlotCount(target: Int) {
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(target))
        #expect(slots(habit).count == target)
    }

    @Test("Pills fill left to right, and the next one is open")
    func frequencyFillOrder() {
        // Two completions this week, logged on Monday and Tuesday.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(4),
            completedDays: [TestCalendar.date(2026, 8, 17), TestCalendar.date(2026, 8, 18)]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled, .open, .inactive])
    }

    @Test("No slot is open once today is already logged")
    func frequencyDoneToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(4),
            completedDays: [TestCalendar.date(2026, 8, 17), today]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled, .inactive, .inactive])
        // The pill holding today's completion is the one that can undo it.
        #expect(row.filter(\.isTappable).map(\.index) == [1])
    }

    @Test("No slot is open once the weekly goal is met")
    func frequencyGoalMet() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 17), TestCalendar.date(2026, 8, 18)]
        )
        let row = slots(habit)

        #expect(row.map(\.state) == [.filled, .filled])
        #expect(row.allSatisfy { !$0.isTappable })
    }

    @Test("Completions in other weeks do not fill this week's pills")
    func frequencyIgnoresOtherWeeks() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [
                TestCalendar.date(2026, 8, 10),  // previous week
                TestCalendar.date(2026, 8, 24)   // next week
            ]
        )
        let row = slots(habit)

        // A fresh, empty row: the week rolls over with no carry-over.
        #expect(row.map(\.state) == [.open, .inactive, .inactive])
    }

    @Test("A habit edited down to fewer pills than it has completions clamps")
    func frequencyOverfilled() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [
                TestCalendar.date(2026, 8, 17),
                TestCalendar.date(2026, 8, 18),
                TestCalendar.date(2026, 8, 19)
            ]
        )
        let row = slots(habit)

        #expect(row.count == 2)
        #expect(row.allSatisfy { $0.state == .filled })
    }

    // MARK: - The invariant

    @Test("At most one slot per habit is ever open")
    func atMostOneOpenSlot() {
        let cadences: [Frequency] = [.daily, .timesPerWeek(2), .timesPerWeek(3),
                                     .timesPerWeek(4), .timesPerWeek(5), .timesPerWeek(6)]
        let weekDays = week.days

        for frequency in cadences {
            // Every subset of this week is a valid completion history.
            for mask in 0..<(1 << 7) {
                let completed = Set(weekDays.enumerated().compactMap { index, day in
                    mask & (1 << index) != 0 ? day : nil
                })
                let habit = HabitSnapshot.fixture(frequency: frequency, completedDays: completed)
                let open = slots(habit).filter { $0.state == .open }
                #expect(open.count <= 1, "\(frequency) with mask \(mask) produced \(open.count) open slots")
            }
        }
    }

    @Test("Every tappable slot acts on today and nothing else")
    func tapsOnlyEverTouchToday() {
        let cadences: [Frequency] = [.daily, .timesPerWeek(3), .timesPerWeek(6)]
        for frequency in cadences {
            for mask in 0..<(1 << 7) {
                let completed = Set(week.days.enumerated().compactMap { index, day in
                    mask & (1 << index) != 0 ? day : nil
                })
                let habit = HabitSnapshot.fixture(frequency: frequency, completedDays: completed)
                for slot in slots(habit) where slot.isTappable {
                    #expect(slot.actionDay == today)
                }
            }
        }
    }

    // MARK: - The one cadence-surface policy (#543)

    @Test("Every current-week history exposes today and nothing else")
    func tappabilityOverEveryHistory() {
        for mask in 0..<(1 << 7) {
            let completed = Set(week.days.enumerated().compactMap { index, day in
                mask & (1 << index) != 0 ? day : nil
            })
            let row = slots(.fixture(completedDays: completed), editing: .todayOnly)
            let actions = row.filter(\.isTappable)
            #expect(actions.count == 1, "mask \(mask) offered \(actions.count) days")
            #expect(actions.first?.actionDay == today)
            #expect(actions.first?.index == 2)
        }
    }

    @Test("A past completion stays visible but is browse-only")
    func pastCompletionIsInert() {
        let habit = HabitSnapshot.fixture(
            completedDays: [TestCalendar.date(2026, 8, 17), today]
        )
        let row = slots(habit, editing: .todayOnly)

        #expect(!row[0].isTappable)
        #expect(!row[0].isToday)
        #expect(row[0].mark == .donePast)
        #expect(row[2].isToday)
        #expect(row[2].isTappable)
        #expect(row[2].mark == .doneToday)
    }

    @Test("The legacy rest day remains inert")
    func restDayIsNeverEditable() {
        let monday = TestPreferences.weekday(ofColumn: 0, in: week, calendar: calendar)
        let row = slots(.fixture(), editing: .todayOnly, restDay: monday)
        #expect(row[0].state == .rest)
        #expect(!row[0].isTappable)
    }

    // MARK: - An earlier week (#117, browse-only since #543)

    /// The week beginning Monday 2026-08-03, two weeks before this one — the
    /// branch that has no today in it at all.
    private var pastWeek: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 3), calendar: calendar)
    }

    private func pastSlots(_ habit: HabitSnapshot, editing: SlotEditing) -> [Slot] {
        WeekGrid.slots(
            for: habit, in: pastWeek, today: today, editing: editing,
            restDay: nil, calendar: calendar
        )
    }

    @Test("Every history of an earlier week is visible and inert")
    func pastWeekOverEveryHistory() {
        for mask in 0..<(1 << 7) {
            let completed = Set(pastWeek.days.enumerated().compactMap { index, day in
                mask & (1 << index) != 0 ? day : nil
            })
            let habit = HabitSnapshot.fixture(completedDays: completed)

            let row = pastSlots(habit, editing: .todayOnly)
            #expect(row.count == 7, "mask \(mask) drew \(row.count) slots")
            #expect(!row.contains { $0.state == .open }, "mask \(mask) opened a past day")
            #expect(!row.contains { $0.isToday }, "mask \(mask) called a past day today")
            #expect(row.allSatisfy { !$0.isTappable }, "mask \(mask) exposed a correction")

            let states = row.map(\.state)
            #expect(states.allSatisfy { $0 == .filled || $0 == .missed }, "mask \(mask)")
            #expect(states.count { $0 == .filled } == completed.count, "mask \(mask)")
        }
    }

    @Test("A completion in an earlier week draws as a past completion, never as today's")
    func pastWeekCompletionsAreNotToday() {
        let habit = HabitSnapshot.fixture(completedDays: [pastWeek.days[1]])
        let row = pastSlots(habit, editing: .todayOnly)

        #expect(row[1].state == .filled)
        #expect(row[1].mark == .donePast)
        #expect(row[0].mark == .missed)
    }

    @Test("A day outside the displayed week leaves no slot open")
    func todayOutsideTheWeek() {
        let otherWeek = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 10), calendar: calendar)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
        let row = WeekGrid.slots(
            for: habit, in: otherWeek, today: today, editing: .todayOnly,
            restDay: nil, calendar: calendar
        )

        #expect(row.allSatisfy { $0.state != .open })
        #expect(row.allSatisfy { !$0.isTappable })
    }
}

/// #265: a habit draws no mark of failure for a week it did not live in.
///
/// The reported shape was a habit created today showing seven ✕ across last
/// week — the app asserting seven missed days on days when there was nothing
/// to miss. `SlotState.missed` means "this became unavoidable" (#82), and
/// nothing becomes unavoidable before it is asked for.
@Suite("Before a habit existed")
struct BeforeCreationTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
    }
    private func day(_ column: Int) -> Date { week.days[column] }

    private func slots(createdColumn: Int?, todayColumn: Int = 4) -> [Slot] {
        let habit = HabitSnapshot(
            id: UUID(), name: "New", icon: "star", frequency: .daily,
            completionCounts: [:], isSpacer: false,
            createdDay: createdColumn.map { day($0) }
        )
        return WeekGrid.slots(
            for: habit, in: week, today: day(todayColumn),
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
    }

    @Test("A day before the habit existed is unlit, not missed")
    func daysBeforeCreationAreInactive() {
        // Created Wednesday, today Friday. Monday and Tuesday are past days the
        // habit was not alive for; Wednesday and Thursday are past days it was.
        let row = slots(createdColumn: 2)
        #expect(row[0].state == .inactive, "Monday: \(row[0].state)")
        #expect(row[1].state == .inactive, "Tuesday: \(row[1].state)")
        #expect(row[2].state == .missed, "Wednesday: \(row[2].state)")
        #expect(row[3].state == .missed, "Thursday: \(row[3].state)")
        #expect(row[4].state == .open, "today: \(row[4].state)")
    }

    /// The mark, not just the state — an unlit dot is what #265 asked for.
    @Test("Those days draw the same unlit dot a day still to come draws")
    func theyDrawAnUnlitDot() {
        let row = slots(createdColumn: 2)
        #expect(row[0].mark == .upcoming)
        #expect(row[1].mark == .upcoming)
        #expect(row[5].mark == .upcoming, "a day still to come draws the same")
        #expect(row[2].mark == .missed)
    }

    /// A whole week before the habit: nothing on the row claims anything.
    @Test("A week entirely before the habit has no misses in it")
    func awholeWeekBeforeIsClean() {
        // Created after this week ends, today later still.
        let later = TestCalendar.date(2026, 8, 31)
        let habit = HabitSnapshot(
            id: UUID(), name: "New", icon: "star", frequency: .daily,
            completionCounts: [:], isSpacer: false, createdDay: later
        )
        let row = WeekGrid.slots(
            for: habit, in: week, today: later,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(row.allSatisfy { $0.state == .inactive })
        #expect(row.allSatisfy { $0.mark == .upcoming })
    }

    /// An unknown creation date means *unknown*, so nothing changes for it —
    /// the pre-#265 behaviour, kept for every row written before the column
    /// existed (#186).
    @Test("A habit with no known creation still misses as it always did")
    func unknownCreationIsUnchanged() {
        let row = slots(createdColumn: nil)
        #expect(row[0].state == .missed)
        #expect(row[3].state == .missed)
    }

    /// A completion still wins, wherever it came from — an import, or a store
    /// older than the column.
    @Test("A completion before the creation date is still drawn")
    func completionsOutrankTheCreationDate() {
        let habit = HabitSnapshot(
            id: UUID(), name: "New", icon: "star", frequency: .daily,
            completionCounts: [day(0): 1], isSpacer: false, createdDay: day(2)
        )
        let row = WeekGrid.slots(
            for: habit, in: week, today: day(4),
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(row[0].state == .filled)
    }

    /// The span rows, whose ✕ comes from `lost` rather than from a past day.
    @Test("A span row draws one unlit span for a week before the habit")
    func spanRowsAreOneInactiveSpan() {
        let later = TestCalendar.date(2026, 8, 31)
        let habit = HabitSnapshot(
            id: UUID(), name: "New", icon: "star", frequency: .timesPerWeek(3),
            completionCounts: [:], isSpacer: false, createdDay: later
        )
        let spans = WeekSpans.spans(
            for: habit, in: week, today: later, target: 3,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(spans.count == 1)
        #expect(spans[0].state == .inactive)
        #expect(spans[0].firstDay == 0 && spans[0].lastDay == 6)
        #expect(spans[0].actionDay == nil)
        #expect(!spans.contains { $0.state == .missed })
    }

    @Test("A span row preserves pre-creation completions without inventing misses")
    func spanRowsShowPreCreationFacts() {
        let later = TestCalendar.date(2026, 8, 31)
        let habit = HabitSnapshot(
            id: UUID(), name: "New", icon: "star", frequency: .timesPerWeek(3),
            completionCounts: [day(1): 1, day(4): 1],
            isSpacer: false, createdDay: later
        )
        let spans = WeekSpans.spans(
            for: habit, in: week, today: later, target: 3,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )

        #expect(spans.count == 7)
        #expect(spans[1].state == .filled)
        #expect(spans[4].state == .filled)
        #expect(spans.count { $0.state == .filled } == 2)
        #expect(!spans.contains { $0.state == .missed || $0.state == .open })
        #expect(spans.allSatisfy { $0.actionDay == nil })
    }

    /// A finished unmet span row becomes a seven-day diary (#476).
    @Test("A span row in a week the habit lived through crosses every blank day")
    func spanRowsAreOtherwiseUnchanged() {
        let later = TestCalendar.date(2026, 8, 31)
        let habit = HabitSnapshot(
            id: UUID(), name: "Old", icon: "star", frequency: .timesPerWeek(3),
            completionCounts: [:], isSpacer: false, createdDay: day(0)
        )
        let spans = WeekSpans.spans(
            for: habit, in: week, today: later, target: 3,
            editing: .todayOnly, restDay: nil, calendar: calendar
        )
        #expect(spans.count == 7)
        #expect(spans.allSatisfy { $0.state == .missed && $0.dayCount == 1 })
    }
}
