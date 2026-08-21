import Foundation

/// One day of a habit's month: where it sits and what it draws.
struct MonthCell: Identifiable, Equatable, Sendable {
    let date: Date
    /// Zero-based row in the month grid. The first and last rows are ragged,
    /// because the 1st sits under the weekday it really falls on.
    let row: Int
    /// Column 0 through 6, in the calendar's own display order — the same
    /// order every other grid in the app uses.
    let column: Int
    let mark: SlotMark
    /// The day a tap would toggle, or nil when the cell is not tappable. Only
    /// today ever carries one, which is R2 holding in this grid too.
    let actionDay: Date?

    var id: Date { date }
    var isTappable: Bool { actionDay != nil }
}

/// Turns a weekly-cadence habit plus a date into its calendar month of cells.
///
/// Weekly cadences only. A per-day habit's day is a count, not a yes, and a
/// dot meaning "some of the water" would be a third mark state that exists
/// nowhere else — callers filter those out, and this returns nothing for one
/// as the backstop.
///
/// The marks are the week grid's, by construction rather than imitation:
///
/// - **Daily habits** are day-pinned, so each week of the month is handed to
///   `WeekGrid.slots` and the columns read straight off it. Every settled rule
///   — missed only in the past, only today open, a rest day never missed —
///   arrives from the one place it is defined, and any future change there is
///   inherited here without a second edit.
/// - **N×/week habits** are not day-pinned, so the week row has no opinion
///   about which weekday a completion sits on — but the month is a calendar,
///   so a completion shows on the day it really happened. Whether *today* is
///   open is still the week row's own verdict: `WeekGrid.slots` decides, and
///   this asks. Every other day is an empty socket — never missed, because an
///   empty Monday is not a failure on Tuesday, and a week already lost is a
///   judgement this grid does not invent (see the note in the widget's spec
///   entry: a per-week verdict was left as an open question).
enum MonthGrid {
    static func cells(
        for habit: HabitSnapshot,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [MonthCell] {
        guard !habit.isSpacer, !habit.frequency.isCountedPerDay else { return [] }
        let todayStart = WeekCalendar.day(today, calendar: calendar)
        guard let month = calendar.dateInterval(of: .month, for: todayStart) else { return [] }

        // The week row's verdict on today, asked once rather than re-derived:
        // is anything open, and is a completion made today still undoable? For
        // a daily habit the per-day marks below come from the same call, so
        // the two grids can never disagree about today — and whatever the week
        // row withholds (a rest day, a spent week), this inherits.
        let thisWeek = WeekCalendar.week(containing: todayStart, calendar: calendar)
        let weekVerdict = WeekGrid.slots(
            for: habit, in: thisWeek, today: todayStart, calendar: calendar
        )
        let todayIsOpen = weekVerdict.contains { $0.state == .open }
        let todayHasUndo = weekVerdict.contains { $0.isTappable && $0.state == .filled }

        var cells: [MonthCell] = []
        var weekStart = WeekCalendar.startOfWeek(containing: month.start, calendar: calendar)
        var row = 0
        while weekStart < month.end {
            let week = WeekCalendar.week(containing: weekStart, calendar: calendar)
            let slots: [Slot]? = habit.frequency == .daily
                ? WeekGrid.slots(for: habit, in: week, today: todayStart, calendar: calendar)
                : nil

            for (column, day) in week.days.enumerated() where month.contains(day) && day < month.end {
                let mark: SlotMark
                let actionDay: Date?
                if let slots {
                    mark = slots[column].mark
                    actionDay = slots[column].actionDay
                } else if habit.count(on: day) > 0 {
                    mark = day == todayStart ? .doneToday : .donePast
                    // Today's completion is undoable exactly when the week
                    // row says its own tap is — same rule, one place.
                    actionDay = day == todayStart && todayHasUndo ? todayStart : nil
                } else if day == todayStart, todayIsOpen {
                    mark = .openToday
                    actionDay = todayStart
                } else {
                    mark = .upcoming
                    actionDay = nil
                }
                cells.append(MonthCell(
                    date: day, row: row, column: column, mark: mark, actionDay: actionDay
                ))
            }

            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
            row += 1
        }
        return cells
    }

    /// How many rows the month occupies — four through six, depending on where
    /// the 1st falls.
    static func rowCount(of cells: [MonthCell]) -> Int {
        (cells.map(\.row).max() ?? -1) + 1
    }
}
