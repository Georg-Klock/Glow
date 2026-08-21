import Foundation

/// One run of days drawn as a single shape.
///
/// A habit due a number of times a week is not day-pinned, so it is not drawn
/// as seven columns — it is drawn as N shapes that stretch across the week. A
/// span is one of those: which columns it covers, and what state it is in.
struct SlotSpan: Identifiable, Equatable, Sendable {
    let index: Int
    /// Inclusive column range, 0 through 6.
    let firstDay: Int
    let lastDay: Int
    let state: SlotState
    /// The day a tap would toggle, or nil when the span is not tappable.
    let actionDay: Date?

    var id: Int { index }
    var dayCount: Int { lastDay - firstDay + 1 }
    var isTappable: Bool { actionDay != nil }

    var mark: SlotMark {
        switch state {
        case .open: .openToday
        case .filled: .donePast
        case .missed, .inactive: .upcoming
        }
    }
}

/// Turns a habit due N times a week into the spans to draw.
///
/// **The rule is inferred, not specified.** It was read off the design file's
/// two large-widget frames — six examples across two different weekdays — and
/// reproduces five of them exactly. The sixth is a two-a-week row that spans one
/// day more than the rule gives; the identical row in the other frame follows
/// the rule, so it reads as a slip in the mock rather than a different rule.
/// Worth re-checking if a row ever looks wrong:
///
///  - **The goal met** is one bright span across the whole week. Nothing is
///    outstanding, so the week stops being divided at all.
///  - **Otherwise there are exactly N spans.** Completions pack to the left over
///    the days already gone, days still to come pack to the right, and the open
///    span takes what is left in the middle — so the open span always contains
///    today, which is the property that makes the row readable at a glance.
///  - **A completion logged today** belongs to the left-hand block rather than
///    the open one. There is nothing open once today is spent.
enum WeekSpans {
    static func spans(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        target: Int,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [SlotSpan] {
        guard !habit.isSpacer else { return [] }
        // A per-day habit is not spread across a week, so there is nothing here
        // to divide. Same backstop as in `WeekGrid.slots`.
        guard !habit.frequency.isCountedPerDay else { return [] }
        let todayStart = WeekCalendar.day(today, calendar: calendar)
        let dayCount = week.days.count
        guard target > 0, dayCount == 7 else { return [] }

        let completions = habit.completedDays.count { week.contains($0) }
        // A habit edited from 5x down to 2x can hold more completions than it
        // has spans. Clamp rather than draw a row that overflows its own goal.
        let done = min(completions, target)
        let doneToday = habit.completedDays.contains(todayStart)

        // The goal is met: one span, the whole week, and the only thing left to
        // do with it is undo today.
        guard done < target else {
            return [SlotSpan(
                index: 0,
                firstDay: 0,
                lastDay: dayCount - 1,
                state: .filled,
                actionDay: doneToday ? todayStart : nil
            )]
        }

        guard let todayIndex = week.days.firstIndex(of: todayStart) else {
            // Looking at a week that is not the current one: nothing is open,
            // so completions pack left and the rest is still to come.
            return divide(0, dayCount - 1, into: target, from: 0) { i in
                i < done ? .filled : .inactive
            }
        }

        // Today is spent, so it closes the left-hand block and nothing is open.
        if doneToday {
            var spans = divide(0, todayIndex, into: done, from: 0) { _ in .filled }
            if todayIndex < dayCount - 1, target > done {
                spans += divide(
                    todayIndex + 1, dayCount - 1, into: target - done, from: done
                ) { _ in .inactive }
            }
            // The most recent completion is today's, so it is the one a tap undoes.
            if let last = spans.indices.last(where: { spans[$0].state == .filled }) {
                let s = spans[last]
                spans[last] = SlotSpan(
                    index: s.index, firstDay: s.firstDay, lastDay: s.lastDay,
                    state: s.state, actionDay: todayStart
                )
            }
            return spans
        }

        // Today is still open. Completions take the days already gone, the days
        // still to come take the right, and the open span takes the middle.
        let upcoming = target - done - 1
        var spans = done > 0 && todayIndex > 0
            ? divide(0, todayIndex - 1, into: done, from: 0) { _ in .filled }
            : []

        let futureSpans = upcoming > 0 && todayIndex < dayCount - 1
            ? divide(todayIndex + 1, dayCount - 1, into: upcoming, from: target - upcoming) { _ in .inactive }
            : []

        let openFirst = spans.last.map { $0.lastDay + 1 } ?? 0
        let openLast = futureSpans.first.map { $0.firstDay - 1 } ?? dayCount - 1
        spans.append(SlotSpan(
            index: spans.count,
            firstDay: openFirst,
            lastDay: max(openFirst, openLast),
            state: .open,
            actionDay: todayStart
        ))
        return spans + futureSpans
    }

    /// Splits an inclusive column range into `count` spans as evenly as the
    /// whole days allow, giving the remainder to the leftmost spans.
    private static func divide(
        _ first: Int,
        _ last: Int,
        into count: Int,
        from startIndex: Int,
        state: (Int) -> SlotState
    ) -> [SlotSpan] {
        guard count > 0, last >= first else { return [] }
        let days = last - first + 1
        let base = days / count
        let extra = days % count

        var spans: [SlotSpan] = []
        var cursor = first
        for i in 0..<count {
            // A span must cover at least one day, so a block with fewer days
            // than spans simply runs out and the rest are dropped.
            let width = base + (i < extra ? 1 : 0)
            guard width > 0, cursor <= last else { break }
            spans.append(SlotSpan(
                index: startIndex + i,
                firstDay: cursor,
                lastDay: min(cursor + width - 1, last),
                state: state(i),
                actionDay: nil
            ))
            cursor += width
        }
        return spans
    }
}
