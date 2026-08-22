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

    /// **A span is structure, not a mark** (#47).
    ///
    /// An achieved span and one still to come draw the same unlit line, and
    /// that is the change rather than an oversight: a span says how the week
    /// was *divided*, and the division does not change when a share of it is
    /// achieved. What says a share was achieved is the lit dot on the weekday
    /// it happened, which `WeekDots` places — so the row stops being a progress
    /// bar and becomes a record of when.
    ///
    /// The two spans that are still marks keep their light and their shape. The
    /// open one is the one thing outstanding, and the ✕ is a rep that can no
    /// longer happen.
    var mark: SlotMark {
        switch state {
        case .open: .openToday
        // Structure. The same line an upcoming span draws, because it is the
        // same thing: a share of the week with no ask left in it.
        case .filled: .upcoming
        // A rep that can no longer happen. Reachable only through #81's `lost`,
        // and only once the miss is unavoidable — never as a warning.
        case .missed: .missed
        // `.rest` never arrives here: a span covers a run of days rather than
        // one, so the rest day is a hole *inside* a span rather than a state a
        // whole span can be in. Subtracting that hole from the shape is #73.
        case .inactive, .rest: .upcoming
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
///  - **Otherwise there are exactly N spans**, each at least one column wide,
///    together covering all seven columns with no gaps. Completions pack to the
///    left over the days already gone, days still to come pack to the right,
///    and the open span takes what is left in the middle — so the open span
///    always contains today, which is the property that makes the row readable
///    at a glance.
///  - **A completion logged today** belongs to the left-hand block rather than
///    the open one. There is nothing open once today is spent.
///
/// **Exactly N, however late in the week it is** (#81). This used to produce
/// *fewer* than N spans, and it did so precisely when the goal was running out
/// of room — the moment the row most needs to be honest about what is left. A
/// 3x/week row on Saturday drew two marks and nothing said the third was gone.
/// The mechanism was `divide` flooring a span at zero columns and stopping,
/// with the open span then absorbing what the dropped ones would have covered.
///
/// So a rep with no day left to land on still gets a column; it just stops
/// being the open one. Two numbers carry it:
///
///  - **`lost`** — reps owed against days that no longer exist:
///    `max(0, repsLeft - actionableLeft)`, where an actionable day is one from
///    today onward that is not the rest day, and not today once today is spent.
///  - **`live`** — the rest, `repsLeft - lost`, of which exactly one is open.
///
/// The completed block *yields* to make room for both, which it never did
/// before: it takes everything before today, or everything before the columns
/// the remaining reps need, whichever is less.
///
/// Those lost spans draw as a ✕ (#82). The strictness matters: `lost` uses
/// `repsLeft > actionableLeft`, not `>=`, so on Saturday with two reps owed and
/// Sunday still live the row stays clean and the ✕ arrives on Sunday. The mark
/// says a miss has *become unavoidable*; it is never a warning and never a
/// prediction.
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
        let repsLeft = target - done
        let doneToday = habit.completedDays.contains(todayStart)
        // The rest day stops these rows like any other: nothing can be logged
        // on it and nothing un-logged, so no span carries an action and the
        // span that would be open waits, unlit. Same rule as `WeekGrid`, and
        // the store refuses the write even if a stale surface offers one.
        let todayRests = WeekPreferences.isRestDay(todayStart, calendar: calendar)
        let lastColumn = dayCount - 1

        // The goal is met: one span, the whole week, and the only thing left to
        // do with it is undo today.
        guard repsLeft > 0 else {
            return [SlotSpan(
                index: 0,
                firstDay: 0,
                lastDay: lastColumn,
                state: .filled,
                actionDay: doneToday && !todayRests ? todayStart : nil
            )]
        }

        let todayIndex = week.days.firstIndex(of: todayStart)

        // A week that has not started: nothing has been lost and nothing is
        // open, so the seven columns divide evenly and the completions — a
        // future week can hold them, through an edit or a sync — pack left.
        if todayIndex == nil, week.start > todayStart {
            return divide(0, lastColumn, into: target, from: 0) { i in
                i < done ? .filled : .inactive
            }
        }

        // The columns a rep could still land on: every day from today onward
        // that is not the rest day, and not today itself once today is spent —
        // a weekly cadence holds one completion per day (R3), so a logged today
        // has no room for a second.
        //
        // This is the whole of the rest day's part in the arithmetic. The
        // *shape* still divides seven columns and subtracts the rest column
        // from what is drawn (`RestWindow`, #73); what counting `A` does is
        // bring the squeeze forward by a day, which is a fact about the week
        // rather than about the drawing.
        let actionable = (0...lastColumn).filter {
            !WeekPreferences.isRestDay(week.days[$0], calendar: calendar)
        }
        let actionableLeft: Int
        if let todayIndex {
            actionableLeft = actionable.count { doneToday ? $0 > todayIndex : $0 >= todayIndex }
        } else {
            // A week already over. Every rep still owed has run out of days.
            actionableLeft = 0
        }

        // Reps with no day left to land on, and reps that still have one.
        let lost = max(0, repsLeft - actionableLeft)
        let live = repsLeft - lost

        var spans: [SlotSpan] = []
        var cursor = 0

        // 1. The completed block, which yields.
        //
        // It takes everything before today, *or* everything before the columns
        // the remaining reps need — whichever is less. The second term is what
        // #81 adds: without it a late day leaves fewer columns than there are
        // reps still to draw, and the surplus spans were silently dropped.
        if done > 0 {
            let roomForTheRest = lastColumn - repsLeft
            let doneLast: Int
            if let todayIndex {
                // The first column the block must leave alone. Today belongs
                // *to* the block once it is spent; otherwise the block also has
                // to clear the columns the lost reps will take, or a lost span
                // lands on today and the open one starts after it. That last
                // term is not in #81's formula, which reads `min(t - 1, ...)`
                // — right for every row the issue tabulates, and a column out
                // as soon as a rest day makes something lost before the last
                // day. The invariant it breaks is the issue's own primary one:
                // the open span always contains today.
                let reserved = doneToday ? todayIndex + 1 : todayIndex - lost
                doneLast = min(reserved - 1, roomForTheRest)
            } else {
                doneLast = roomForTheRest
            }
            spans += divide(0, doneLast, into: done, from: 0) { _ in .filled }
            cursor = doneLast + 1
        }

        // 2. Reps that can no longer happen.
        //
        // One column each while something is still live, because the open span
        // absorbs the slack. With nothing live they *are* the rest of the row,
        // so they divide it — which is also the only way the seven columns stay
        // covered when nothing was ever logged.
        guard live > 0 else {
            spans += divide(cursor, lastColumn, into: lost, from: spans.count) { _ in .missed }
            return withUndo(spans, doneToday: doneToday, todayRests: todayRests, today: todayStart)
        }
        for _ in 0..<lost {
            spans.append(SlotSpan(
                index: spans.count, firstDay: cursor, lastDay: cursor,
                // Inert and permanent for the week: never tappable, never
                // undoable, and it does not take the row down with it — the
                // reps still reachable keep glowing beside it.
                state: .missed, actionDay: nil
            ))
            cursor += 1
        }

        // 3. The span today sits in.
        //
        // It ends at today, or at the last day that still leaves one actionable
        // column for each rep behind it — whichever is sooner. When it is the
        // last span in the row it runs to the end instead, which is what keeps
        // the seven columns covered.
        let deadline = actionable[actionable.count - live]
        var openLast = min(todayIndex ?? deadline, deadline)
        if live == 1 { openLast = lastColumn }
        openLast = max(openLast, cursor)

        // Open only when today can actually carry it: not a rest day, not
        // already spent, and inside this week. Otherwise the span keeps its
        // place and its geometry and simply asks for nothing.
        let isOpen = todayIndex != nil && !doneToday && !todayRests
        spans.append(SlotSpan(
            index: spans.count,
            firstDay: cursor,
            lastDay: openLast,
            state: isOpen ? .open : .inactive,
            actionDay: isOpen ? todayStart : nil
        ))
        cursor = openLast + 1

        // 4. What is still to come.
        spans += divide(cursor, lastColumn, into: live - 1, from: spans.count) { _ in .inactive }
        return withUndo(spans, doneToday: doneToday, todayRests: todayRests, today: todayStart)
    }

    /// Hands the undo to the most recent completion, which is today's.
    ///
    /// Spans are not day-pinned, so "today's completion" is the last filled
    /// span rather than the one over today's column — they fill in completion
    /// order and today is the most recent day.
    private static func withUndo(
        _ spans: [SlotSpan],
        doneToday: Bool,
        todayRests: Bool,
        today: Date
    ) -> [SlotSpan] {
        guard doneToday, !todayRests,
              let last = spans.indices.last(where: { spans[$0].state == .filled })
        else { return spans }
        var spans = spans
        let s = spans[last]
        spans[last] = SlotSpan(
            index: s.index, firstDay: s.firstDay, lastDay: s.lastDay,
            state: s.state, actionDay: today
        )
        return spans
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
