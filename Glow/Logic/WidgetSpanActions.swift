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

    static func openActions(
        for span: SlotSpan,
        habit: HabitSnapshot,
        week: Week,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Action] {
        guard span.state == .open else { return [] }
        return (span.firstDay...span.lastDay).compactMap { column in
            WeekSpans.day(
                atColumn: column,
                of: span,
                for: habit,
                in: week,
                today: today,
                editing: .todayOnly,
                restDay: restDay,
                calendar: calendar
            ).map { Action(column: column, day: $0) }
        }
    }
}
