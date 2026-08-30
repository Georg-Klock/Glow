import Foundation

/// Which of the three steps a piece of type takes (#335, `docs/week-marks.md`
/// §8.5).
///
/// Light has two tiers (#334) and the reflecting one has two strengths, so type
/// has three states and they say what is still asked of you:
///
/// | | Weekday letter | Habit label |
/// | --- | --- | --- |
/// | `.emitting` | today, any habit open | this habit open today |
/// | `.lit` | today, everything closed | handled today |
/// | `.resting` | any other day | at rest |
///
/// Pure and here rather than in a view, for the reason `WeekGrid` and
/// `WeekSpans` are: two surfaces draw this row — the app's grid and the
/// widget's — and a rule written twice is a rule that drifts. The views turn a
/// tier into a style and nothing else.
enum TypeTier: Equatable, Sendable {
    /// White with the HDR tile over it. Reserved for what is still actionable.
    case emitting
    /// `#D9D9D9` at full strength: lit, but not a source of light.
    case lit
    /// `#D9D9D9` at half. Nothing is asked here.
    case resting

    /// The weekday letter's tier.
    ///
    /// **Today is not automatically the loudest thing on screen.** It was:
    /// today's letter glowed whatever the week was doing, which meant the
    /// emitting tier said *this is today* rather than *this wants you*. It
    /// steps down to `.lit` once every habit is handled — the day is still
    /// today and still reads as today, it has simply stopped asking.
    static func weekday(isToday: Bool, anyHabitOpen: Bool) -> TypeTier {
        guard isToday else { return .resting }
        return anyHabitOpen ? .emitting : .lit
    }

    /// A habit's own label: **the name and the icon together**, which §8.5 is
    /// explicit about — they carry the same value in every state and dim as a
    /// pair. A glowing name beside a resting icon would read as two facts.
    static func label(isOpenToday: Bool, isHandledToday: Bool) -> TypeTier {
        if isOpenToday { return .emitting }
        return isHandledToday ? .lit : .resting
    }

    // MARK: - Deriving the two states

    /// Whether this habit is still waiting on today.
    ///
    /// Asked of `WeekGrid`, which already answers it for both cadences — a
    /// daily row's open dot and a weekly row's open pill are the same claim.
    /// Re-deriving it from the record here would be the mirror copy this
    /// project's test rules forbid, and it would drift the first time the rest
    /// day or the reach moved.
    static func isOpen(
        _ habit: HabitSnapshot,
        in week: Week,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        guard !habit.isSpacer else { return false }
        return WeekGrid.slots(
            for: habit, in: week, today: today,
            editing: .todayOnly, restDay: restDay, calendar: calendar
        ).contains { $0.state == .open }
    }

    /// Whether this habit was logged today.
    ///
    /// **Logged today, not "goal met"**. A 2x habit that finished on Monday and
    /// Tuesday is not *handled today* on Friday — nothing was asked of it and
    /// nothing was done, so it rests. The middle step is for a habit that had
    /// something to do today and did it.
    static func isHandled(
        _ habit: HabitSnapshot,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        guard !habit.isSpacer else { return false }
        // The rest day draws nothing and asks nothing, so a completion stored
        // on one does not light its label either (#72).
        guard !WeekPreferences.isRestDay(today, restDay: restDay, calendar: calendar) else {
            return false
        }
        return habit.completedDays.contains(WeekCalendar.day(today, calendar: calendar))
    }

    /// Whether anything in this week still wants doing today — what the weekday
    /// letter needs, and the one piece of state that is not a row's own.
    static func anyOpen(
        in habits: [HabitSnapshot],
        week: Week,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        habits.contains {
            isOpen($0, in: week, today: today, restDay: restDay, calendar: calendar)
        }
    }
}
