import Foundation

/// The exact dated controls an open widget span can expose.
///
/// WidgetKit does not report a touch location inside one custom control, so an
/// open multi-day span cannot truthfully use its single fallback `actionDay`.
/// This projection keeps the continuous drawn span while giving each eligible
/// column its own AppIntent-bound control.
enum WidgetSpanActions {
    struct Action: Identifiable, Equatable, Sendable {
        let column: Int
        let day: Date
        var id: Int { column }
    }

    /// Every column of an open span, all of them writing the one day the span
    /// can write.
    ///
    /// **The whole pill is one tap target, subdivided only for drawing**
    /// (#614). It used to ask `WeekSpans.day(atColumn:)` per column and keep
    /// the columns that came back non-nil — but `SlotEditing` has one case and
    /// it is `.todayOnly`, so exactly one column could ever answer: today's.
    /// Every other column produced no `Action`, `WidgetSpan.openSpan` laid a
    /// bare `Color.clear` over it, and a tap there fell through to WidgetKit's
    /// default and opened the app. A four-day open pill was three-quarters
    /// dead, and the dead part did something unrelated.
    ///
    /// So the per-column question was the wrong question. There is one day this
    /// span writes; the columns are zones of one control, not eight controls
    /// with eight dates. This resolves that day once — through the same
    /// `WeekSpans.day` call, under the same `.todayOnly` policy, so the widget
    /// still cannot write a day other than today — and gives it to every
    /// column. An open span always runs through today
    /// (`WeekSpansTests.openSpanEndsAtToday`), which is why one column
    /// answering is the normal case rather than a lucky one; when none answers
    /// — today is the rest day, the habit did not exist yet — the span offers
    /// nothing at all, exactly as before.
    ///
    /// The rest day's own column is inside the pill and is now tappable with
    /// the rest. It is not a write to the rest day: there is one day here and
    /// it is today, and today is not the rest day or there would be no actions
    /// to hand out. The notch stays drawn; only the pixels over it act.
    ///
    /// `column` survives because `openSpan` still needs it — the drawn face is
    /// centred on the zone under the finger. What changed is only which day a
    /// zone means.
    static func openActions(
        for span: SlotSpan,
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Action] {
        guard span.state == .open else { return [] }
        let columns = span.firstDay...span.lastDay
        let writable = columns.lazy.compactMap { column in
            WeekSpans.day(
                atColumn: column,
                of: span,
                for: habit,
                in: week,
                today: today,
                editing: .todayOnly,
                restDay: restDay,
                calendar: calendar
            )
        }
        guard let day = writable.first else { return [] }
        return columns.map { Action(column: $0, day: day) }
    }
}
