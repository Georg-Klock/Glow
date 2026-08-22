import Foundation
import Testing
@testable import Glow

/// #137: what the historical half of the app says out loud.
///
/// The week grid announced a state and no date — "Read, missed" seven times
/// over, with nothing saying which day was missed, because the only thing that
/// carries the dates is a header hidden from VoiceOver. The year and the month
/// widget announced nothing at all.
///
/// These assert the strings against the real types, including the two cases
/// that must stay silent. What they cannot assert is the spoken result: see the
/// note in docs/decisions.md.
@Suite("The voice of a day")
struct SlotVoiceTests {
    private let calendar = TestCalendar.monday
    /// Wednesday of the week beginning Monday 2026-08-17.
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func day(_ index: Int) -> Date { week.days[index] }

    /// `restColumn` is a column of this week, converted the way every suite
    /// that sets a rest day converts it.
    private func slots(_ habit: HabitSnapshot, restColumn: Int? = nil) -> [Slot] {
        let restDay = restColumn.map {
            TestPreferences.weekday(ofColumn: $0, in: week, calendar: calendar)
        }
        return TestPreferences.withWeek(restDay: restDay) {
            WeekGrid.slots(for: habit, in: week, today: today, editing: .todayOnly, calendar: calendar)
        }
    }

    // MARK: - All seven columns

    @Test("Every column of the week names its own date and state")
    func sevenDistinctColumns() {
        let habit = HabitSnapshot.fixture(
            name: "Read", completedDays: [day(0)]
        )
        let spoken = slots(habit).map {
            SlotVoice.label(habitName: habit.name, mark: $0.mark, day: day($0.index), calendar: calendar)
        }

        #expect(spoken == [
            "Read, Monday 17 August, done",
            "Read, Tuesday 18 August, missed",
            "Read, Wednesday 19 August, due today",
            "Read, Thursday 20 August, upcoming",
            "Read, Friday 21 August, upcoming",
            "Read, Saturday 22 August, upcoming",
            "Read, Sunday 23 August, upcoming",
        ])
        // The property that matters more than any single string: a swipe
        // through the row is seven different sentences, so no two stops are
        // indistinguishable.
        #expect(Set(spoken).count == 7)
    }

    @Test("A completion is one word, whichever day it fell on")
    func doneIsDone() {
        // `doneToday` and `donePast` are one word now: the date in front of it
        // already says which day, and "done today, Monday 17 August" would be
        // two answers to the same question.
        #expect(SlotVoice.state(.doneToday) == "done")
        #expect(SlotVoice.state(.donePast) == "done")
    }

    @Test("What is not drawn is not spoken: the rest day says rest, not done")
    func restDayKeepsItsWord() {
        // #72: the rest column draws nothing at all, a stored completion
        // included. The completion still counts everywhere it counted — it is
        // simply not drawn there — so the column must not announce it either.
        let habit = HabitSnapshot.fixture(name: "Read", completedDays: [day(2)])
        let row = slots(habit, restColumn: 2)  // Wednesday, which is today
        let label = SlotVoice.label(
            habitName: habit.name, mark: row[2].mark, day: day(2), calendar: calendar
        )
        #expect(label == "Read, Wednesday 19 August, rest day")
        #expect(!label.contains("done"))
    }

    @Test("A tappable slot says what a tap would do")
    func hints() {
        #expect(SlotVoice.hint(isDone: false) == "Mark as done")
        #expect(SlotVoice.hint(isDone: true) == "Mark as not done")
    }

    // MARK: - Locale

    @Test("The date is named by the calendar's own locale, not the process's")
    func localeIsTheCalendars() {
        // The trap #104 measured on `WeekDots.spokenDays`: names taken from
        // one locale and joined by another. Here it would be a date ordered by
        // one and named by the other.
        var german = calendar
        german.locale = Locale(identifier: "de_DE")
        let spoken = SlotVoice.day(day(1), calendar: german)
        #expect(spoken.contains("Dienstag"))
        #expect(spoken.contains("August"))
        #expect(!spoken.contains("Tuesday"))

        var american = calendar
        american.locale = Locale(identifier: "en_US")
        // en_US puts the month first; en_GB puts the day first. Both are
        // produced from the same call, which is the whole point.
        #expect(SlotVoice.day(day(1), calendar: american) == "Tuesday, August 18")
        #expect(SlotVoice.day(day(1), calendar: calendar) == "Tuesday 18 August")
    }

    @Test("The date is formatted in the calendar's own time zone")
    func timeZoneTravels() {
        // A midnight normalized in UTC and formatted in a zone behind it lands
        // on the day before, which is how a row ends up a day out of step with
        // the header it is drawn under.
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        let midnight = TestCalendar.date(2026, 8, 18)
        #expect(SlotVoice.day(midnight, calendar: calendar).contains("18"))
        // Same instant, a calendar nine hours ahead: still the 18th, because
        // the style is handed the calendar's zone rather than the process's.
        #expect(SlotVoice.day(midnight, calendar: tokyo).contains("18"))
    }

    // MARK: - Spans

    @Test("A span speaks a date only when it acts on one")
    func spansAreNotDayPinned() {
        // A habit due N times a week is not day-pinned: a span is a share of
        // the week, and the dots say which days it was logged on. The one date
        // a span has is the day a tap would touch, which is always today.
        let habit = HabitSnapshot.fixture(
            name: "Workout", frequency: .timesPerWeek(3), completedDays: [day(0)]
        )
        let spans = TestPreferences.withWeek(restDay: nil) {
            WeekSpans.spans(for: habit, in: week, today: today, target: 3, editing: .todayOnly, calendar: calendar)
        }
        let spoken = spans.map {
            SlotVoice.span(
                habitName: habit.name, state: $0.state,
                actionDay: $0.actionDay, calendar: calendar
            )
        }

        // Exactly one of them carries the date, and it is the one with the
        // action on it.
        #expect(spoken.count { $0.contains("Wednesday 19 August") } == 1)
        #expect(spoken.first { $0.contains("Wednesday") } == "Workout, Wednesday 19 August, due today")
        #expect(spoken.contains("Workout, done"))
        #expect(spoken.contains("Workout, still to come"))
    }

    @Test("An undo says the day it would take back")
    func undoIsDated() {
        let habit = HabitSnapshot.fixture(
            name: "Workout", frequency: .timesPerWeek(3), completedDays: [day(2)]
        )
        let spans = TestPreferences.withWeek(restDay: nil) {
            WeekSpans.spans(for: habit, in: week, today: today, target: 3, editing: .todayOnly, calendar: calendar)
        }
        let tappable = spans.filter(\.isTappable)
        #expect(tappable.count == 1)
        #expect(
            SlotVoice.span(
                habitName: habit.name, state: tappable[0].state,
                actionDay: tappable[0].actionDay, calendar: calendar
            ) == "Workout, Wednesday 19 August, done"
        )
    }

    @Test("A lost repetition is spoken as missed, not as a day")
    func lostSpans() {
        // #82's ✕: a rep with no day left to land on. It has no date of its
        // own — it is a share of the week that ran out of week — so it says
        // what it is and nothing more.
        let saturday = TestCalendar.date(2026, 8, 22)
        let habit = HabitSnapshot.fixture(name: "Workout", frequency: .timesPerWeek(3))
        let spans = TestPreferences.withWeek(restDay: nil) {
            WeekSpans.spans(
                for: habit, in: week, today: saturday, target: 3, editing: .todayOnly, calendar: calendar
            )
        }
        let missed = spans.filter { $0.state == .missed }
        #expect(!missed.isEmpty)
        for span in missed {
            #expect(
                SlotVoice.span(
                    habitName: habit.name, state: span.state,
                    actionDay: span.actionDay, calendar: calendar
                ) == "Workout, missed"
            )
        }
    }
}

/// A month and a year, counted rather than listed.
@Suite("The voice of a stretch of days")
struct HistoryVoiceTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func day(_ index: Int) -> Date { week.days[index] }

    // MARK: - The month widget

    @Test("A month is one sentence, counted off the cells the grid draws")
    func monthIsCounted() {
        // August 2026 begins on a Saturday and today is the 19th: 18 days
        // behind it, of which two were logged.
        let habit = HabitSnapshot.fixture(
            name: "Read",
            completedDays: [TestCalendar.date(2026, 8, 3), TestCalendar.date(2026, 8, 4)]
        )
        let cells = TestPreferences.withWeek(restDay: nil) {
            MonthGrid.cells(for: habit, today: today, calendar: calendar)
        }
        let spoken = HistoryVoice.month(cells, calendar: calendar)

        // Counted off the marks rather than off the completions, so the
        // sentence and the picture cannot disagree.
        let logged = cells.count { $0.mark == .donePast || $0.mark == .doneToday }
        let missed = cells.count { $0.mark == .missed }
        let upcoming = cells.count { $0.mark == .upcoming }
        #expect(logged == 2)
        #expect(spoken == "\(logged) days logged this month, \(missed) days missed, due today and \(upcoming) days still to come")
    }

    @Test("A month with nothing in it says so, once")
    func emptyMonth() {
        let cells = TestPreferences.withWeek(restDay: nil) {
            MonthGrid.cells(for: .fixture(name: "Read"), today: today, calendar: calendar)
        }
        #expect(
            HistoryVoice.month(cells, calendar: calendar)?
                .hasPrefix("nothing logged this month") == true
        )
    }

    @Test("One day is a day, not one days")
    func singularDay() {
        let habit = HabitSnapshot.fixture(
            name: "Read", completedDays: [TestCalendar.date(2026, 8, 3)]
        )
        let cells = TestPreferences.withWeek(restDay: nil) {
            MonthGrid.cells(for: habit, today: today, calendar: calendar)
        }
        #expect(HistoryVoice.month(cells, calendar: calendar)?.hasPrefix("1 day logged this month") == true)
    }

    @Test("No cells, no sentence")
    func noCells() {
        // A spacer has no month. nil rather than an empty string, so the view
        // drops the value instead of announcing nothing.
        #expect(HistoryVoice.month([], calendar: calendar) == nil)
    }

    // MARK: - The year

    @Test("A year column says which week it is and how it went")
    func weekColumn() {
        let fills: [YearHistory.DayFill] = [.full, .full, .partial, .empty, .future, .future, .future]
        #expect(
            HistoryVoice.week(startingOn: week.start, fills: fills, calendar: calendar)
                == "Week of 17 August, 2 days complete, 1 day partly done, 1 day with nothing logged and 3 days still to come"
        )
    }

    @Test("A week still to come says only that")
    func futureWeek() {
        let fills = [YearHistory.DayFill](repeating: .future, count: 7)
        #expect(
            HistoryVoice.week(startingOn: week.start, fills: fills, calendar: calendar)
                == "Week of 17 August, 7 days still to come"
        )
    }

    @Test("The week's date is the calendar's, in its own locale")
    func weekDateIsLocalized() {
        var american = calendar
        american.locale = Locale(identifier: "en_US")
        #expect(HistoryVoice.weekStart(week.start, calendar: american) == "Week of August 17")
        #expect(HistoryVoice.weekStart(week.start, calendar: calendar) == "Week of 17 August")
    }
}

/// The verdict the year grid draws, and now speaks, from one place.
@Suite("A year of days")
struct YearHistoryTests {
    private let calendar = TestCalendar.monday
    private let today = TestCalendar.date(2026, 8, 19)
    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func day(_ index: Int) -> Date { week.days[index] }

    @Test("A day everything was done on is full; some of it is partial")
    func fullAndPartial() {
        TestPreferences.withWeek(restDay: nil) {
            let read = HabitSnapshot.fixture(name: "Read", completedDays: [day(0)])
            let walk = HabitSnapshot.fixture(name: "Walk", completedDays: [day(0), day(1)])
            #expect(YearHistory.fill(
                for: day(0), habits: [read, walk], today: today, calendar: calendar
            ) == .full)
            #expect(YearHistory.fill(
                for: day(1), habits: [read, walk], today: today, calendar: calendar
            ) == .partial)
            #expect(YearHistory.fill(
                for: day(2), habits: [read, walk], today: today, calendar: calendar
            ) == .empty)
        }
    }

    @Test("A day that has not arrived is not a day that went badly")
    func futureIsNotEmpty() {
        TestPreferences.withWeek(restDay: nil) {
            #expect(YearHistory.fill(
                for: day(3), habits: [.fixture()], today: today, calendar: calendar
            ) == .future)
        }
    }

    @Test("Nothing expected is not a failure")
    func nothingExpected() {
        TestPreferences.withWeek(restDay: nil) {
            // A weekly-cadence habit has no opinion about a given weekday, so a
            // day with only those on it expects nothing and is empty rather
            // than missed.
            let weekly = HabitSnapshot.fixture(frequency: .timesPerWeek(3))
            #expect(YearHistory.fill(
                for: day(0), habits: [weekly], today: today, calendar: calendar
            ) == .empty)
            // And a spacer is a position in a list, never a habit.
            #expect(YearHistory.fill(
                for: day(0), habits: [.fixture(isSpacer: true)], today: today, calendar: calendar
            ) == .empty)
        }
    }

    @Test("A rest day expects nothing, and a completion on one still counts")
    func restDay() {
        // #72 stopped the week grid *drawing* a rest-day completion. It never
        // stopped it counting, and the year is where it still shows.
        let monday = TestPreferences.weekday(ofColumn: 0, in: week, calendar: calendar)
        TestPreferences.withWeek(restDay: monday) {
            let habit = HabitSnapshot.fixture(completedDays: [day(0)])
            #expect(YearHistory.fill(
                for: day(0), habits: [habit], today: today, calendar: calendar
            ) == .full)
            #expect(YearHistory.fill(
                for: day(0), habits: [.fixture()], today: today, calendar: calendar
            ) == .empty)
        }
    }

    @Test("A column is seven verdicts in the calendar's own day order")
    func columnIsAWeek() {
        TestPreferences.withWeek(restDay: nil) {
            let habit = HabitSnapshot.fixture(completedDays: [day(0)])
            let fills = YearHistory.fills(
                in: week, habits: [habit], today: today, calendar: calendar
            )
            #expect(fills == [.full, .empty, .empty, .future, .future, .future, .future])
        }
    }
}
