import Foundation

/// What a mark says out loud.
///
/// A slot is a circle in a column, and which column it is in is the whole
/// answer to *which day*. Sighted, that is read off the header two lines up;
/// spoken, the header is not there — it is one element per weekday saying a
/// letter and a number, which is a table read aloud, so it has always been
/// `accessibilityHidden`. The date therefore has to ride on the mark itself
/// (#137), and it does so on every mark rather than only on the tappable one:
/// a row swiped through end to end is seven dated facts, and a person who
/// stops in the middle of it knows where they are.
///
/// **A span is not given a date it does not have.** A habit due N times a week
/// is not day-pinned — `WeekSpans` divides the week into shares that say *how
/// much*, and `WeekDots` says *when* — so a span speaks a day only when it
/// carries one, and the one it carries is the day a tap on it would act on.
/// See #47, #104 and #116.
///
/// Pure, per the `WeekGrid` / `WeekDots` pattern, so the app and the widget
/// cannot disagree about a word and the strings are testable without a
/// renderer.
enum SlotVoice {
    /// A day, named the way the person's own calendar names it: "Tuesday
    /// 18 August" in en_GB, "Tuesday, August 18" in en_US, "Dienstag,
    /// 18. August" in de_DE.
    ///
    /// Built from the calendar rather than from the process locale, for the
    /// reason #104 measured on `WeekDots.spokenDays`: a calendar set one way
    /// and a format style taking its locale from somewhere else name and order
    /// the same date by two different rules. Its time zone travels too, or a
    /// midnight normalized in one zone is formatted in another and lands on
    /// the day before.
    static func day(_ day: Date, calendar: Calendar = WeekCalendar.calendar) -> String {
        let style = Date.FormatStyle(
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .weekday(.wide)
        .day()
        .month(.wide)
        return day.formatted(style)
    }

    /// What a mark is, as a word.
    ///
    /// `doneToday` and `donePast` are one word, because with the date in front
    /// of it "done" already says which day it was done on. The rest day's word
    /// is #72's: the column draws nothing at all, so without it a VoiceOver
    /// user meets a hole in the row and no explanation.
    static func state(_ mark: SlotMark) -> String {
        switch mark {
        case .doneToday, .donePast: "done"
        case .openToday: "due today"
        case .missed: "missed"
        case .upcoming: "upcoming"
        case .rest: "rest day"
        }
    }

    /// One day-pinned column: the habit, the day it stands for, and its state.
    static func label(
        habitName: String,
        mark: SlotMark,
        day: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        "\(habitName), \(self.day(day, calendar: calendar)), \(state(mark))"
    }

    /// One exact-date widget control inside an otherwise continuous open span.
    /// "Due today" is wrong for a past column; the toggle's actual state is
    /// the useful fact, and its hint already says what activating it will do.
    static func actionLabel(
        habitName: String,
        day: Date,
        isDone: Bool,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        "\(habitName), \(self.day(day, calendar: calendar)), "
            + (isDone ? "done" : "not done")
    }

    /// A span's state, which is not a mark's.
    ///
    /// A filled span and one still to come draw the same unlit line — a span
    /// is structure, not a mark (#47) — but they are not the same fact, and
    /// the spoken row is where that distinction survives. What the span does
    /// *not* say is which days: the dots say that, once, for the whole row.
    static func spanState(_ state: SlotState) -> String {
        switch state {
        case .filled: "done"
        case .open: "due today"
        case .missed: "missed"
        // A span is never `.rest` — see the note on `SlotSpan.mark`.
        case .inactive, .rest: "still to come"
        }
    }

    /// One span: the habit, its state, and a day only when it has one.
    ///
    /// The day is `actionDay` rather than the span's own columns. A span
    /// covers a run of days and an activation with no location touches exactly
    /// one of them, so that is the date the control is about; the columns it
    /// happens to cover would be a date it does not act on. On every cadence
    /// surface that date is today after #543; arbitrary-day edits use factual
    /// circles with their own exact-date labels.
    static func span(
        habitName: String,
        state: SlotState,
        actionDay: Date?,
        completionDay: Date? = nil,
        isBonus: Bool = false,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        if isBonus {
            let fact = "bonus completion"
            guard let completionDay else { return "\(habitName), \(fact)" }
            return "\(habitName), \(day(completionDay, calendar: calendar)), \(fact)"
        }
        guard let actionDay else { return "\(habitName), \(spanState(state))" }
        // **A filled mark is not dated with a day it did not happen on** (#560).
        // On a met row the mark covering today carries today as its action
        // while today is unlogged; saying "Thursday, done" there would announce
        // a completion that does not exist. The mark says what it is, and the
        // hint — `bonusHint` — says what the day under the action is.
        if state == .filled, let completionDay, completionDay != actionDay {
            return "\(habitName), \(spanState(state))"
        }
        return "\(habitName), \(day(actionDay, calendar: calendar)), \(spanState(state))"
    }

    /// What a tap on a met row's filled mark does when today is still unlogged
    /// (#560): logs one more, today, as a bonus mark. Dated, because the label
    /// above deliberately is not — the date belongs to the action here rather
    /// than to the mark, and "Mark as done" alone would read as re-marking the
    /// completion the mark already shows.
    static func bonusHint(for day: Date, calendar: Calendar = WeekCalendar.calendar) -> String {
        "Log a bonus completion for \(self.day(day, calendar: calendar))"
    }

    /// What a tap would do. The glow is the only thing marking a slot as
    /// actionable and it is invisible to VoiceOver, so the hint carries what a
    /// sighted user reads off the screen.
    static func hint(isDone: Bool) -> String {
        isDone ? "Mark as not done" : "Mark as done"
    }
}
