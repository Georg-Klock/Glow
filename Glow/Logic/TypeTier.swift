import Foundation

/// Which of the two tiers a piece of type takes (#334; #603 reversing #335's
/// third step, `docs/week-marks.md` §8.5).
///
/// Light has two tiers and type has exactly those two: the emitting tier is
/// reserved for what is still actionable, and everything else is lit at full
/// strength.
///
/// | | Weekday letter | Habit label |
/// | --- | --- | --- |
/// | `.emitting` | today, any habit open | this habit open today |
/// | `.lit` | every other case | every other case |
///
/// #335 had a third, half-strength step under these — every other weekday, and a
/// label nothing was logged for today — so that a finished row went quiet rather
/// than dark. In use the header read as six dimmed letters and one bright one,
/// and a row that had nothing asked of it read as *less* than a row that had
/// done its work, which is a judgement the grid does not make about a day
/// (SPEC §1: what stays dark is absence, and a name is not absent). Two tiers:
/// asking, or not.
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

    /// The weekday letter's tier.
    ///
    /// **Today is not automatically the loudest thing on screen.** It was:
    /// today's letter glowed whatever the week was doing, which meant the
    /// emitting tier said *this is today* rather than *this wants you*. It
    /// steps down to `.lit` once every habit is handled — the day is still
    /// today and still reads as today, it has simply stopped asking. Every
    /// other letter is lit too (#603): the header marks today by asking, not
    /// by dimming the rest of the week.
    static func weekday(isToday: Bool, anyHabitOpen: Bool) -> TypeTier {
        isToday && anyHabitOpen ? .emitting : .lit
    }

    /// A habit's own label. The tier always belongs to the name, and an SF
    /// Symbol takes it too because the glyph is part of the typography. Emoji
    /// keep their own full-colour pixels outside the tier's glow mask (#457).
    /// The state answer is still shared by both surfaces; only the view decides
    /// how that answer is painted for each kind of icon.
    static func label(isOpenToday: Bool) -> TypeTier {
        isOpenToday ? .emitting : .lit
    }

    // MARK: - Deriving the state

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
