import Foundation

/// One run of days drawn as a single shape.
///
/// A live habit due a number of times a week is drawn as rep windows rather
/// than seven day slots. A finished unmet week deliberately becomes a
/// seven-day diary instead (#476). A span is one drawn shape in either form:
/// which columns it covers, and what state it is in.
struct SlotSpan: Identifiable, Equatable, Sendable {
    /// Which span this is in reading order. Kept for the arithmetic below and
    /// for the record of order; it is **not** what identifies a span. See `id`.
    let index: Int
    /// Inclusive column range, 0 through 6.
    let firstDay: Int
    let lastDay: Int
    let state: SlotState
    /// The day a tap would toggle, or nil when the span is not tappable.
    let actionDay: Date?
    /// The exact day represented by a completion mark. Ordinary completed
    /// spans keep using the row's one combined logged-days sentence, while a
    /// bonus uses this date for its own VoiceOver fact. Keeping it on every
    /// completion also lets today's cadence action find the exact mark to undo
    /// when Edit History has already recorded a later day (#543).
    let completionDay: Date?
    let isBonus: Bool

    init(
        index: Int,
        firstDay: Int,
        lastDay: Int,
        state: SlotState,
        actionDay: Date?,
        completionDay: Date? = nil,
        isBonus: Bool = false
    ) {
        self.index = index
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.state = state
        self.actionDay = actionDay
        self.completionDay = completionDay
        self.isBonus = isBonus
    }

    /// **A span is identified by the division it is, not by where it sits**
    /// (#196).
    ///
    /// `Slot` can be identified by its index and is: a daily row always has
    /// seven slots, index N is weekday N forever, and completing one changes
    /// neither how many there are nor what any of them means. A span has none
    /// of that. `divided()` recomputes the number of spans *and their day
    /// ranges* from `done`, `repsLeft`, `lost` and `live` — precisely the
    /// numbers a completion or an undo moves — so the span at index 2 before a
    /// tap and the one at index 2 after it can be different widths covering
    /// different days.
    ///
    /// `ForEach` believed the index, so `SpanView` kept its `@State` across
    /// that. The state it kept is `closing`, the mid-flight size of a
    /// completion animation: a span whose range changed under a running
    /// animation inherited a size measured for a different span and drew a mark
    /// at it, in a frame it no longer fits — and since the `Button`'s hit area
    /// is the mark, the row went dead to taps along with looking wrong. Two
    /// fast taps on a weekly row is all it takes; #116 and #117 widen that to
    /// any tap on a past day, in any week on the pager.
    ///
    /// **The range, and only the range.** #196 proposed hashing the state in
    /// too, and that would take the animation with it: a completion arriving is
    /// exactly a span holding its range while its state goes `.open → .filled`,
    /// and `SpanView` starts the close from `.onChange(of: span.state)`. Put
    /// state in the identity and that span is a *new* view instead of a changed
    /// one, `onChange` never fires, and the bar stops closing at all — measured
    /// frame by frame before this was written. Range is the identity that keeps
    /// the animation the app has and drops the one it never asked for.
    var id: Division { Division(firstDay: firstDay, lastDay: lastDay) }

    /// The columns a span covers — what makes two spans the same span across a
    /// re-render.
    struct Division: Hashable, Sendable {
        let firstDay: Int
        let lastDay: Int
    }

    var dayCount: Int { lastDay - firstDay + 1 }
    var isTappable: Bool { actionDay != nil }

    /// **A mark is a mark, and a completed one is lit** (#344, reversing #47).
    ///
    /// #47 made an achieved span draw the same unlit line an upcoming one
    /// draws, on the grounds that a span said how the week was *divided* and a
    /// division does not change when a share of it is achieved — with the lit
    /// dot `WeekDots` placed on the real weekday carrying *when*. That was
    /// coherent while a span floated. It stopped being so when a mark started
    /// ending on its own day (#339): the mark's left edge carries when, and an
    /// unlit track with a lit dot inside it leaves the swallowed day visible as
    /// a gap, which is the thing the mark model exists to remove.
    ///
    /// So a completion is lit here, as SPEC §1 says it is everywhere else. The
    /// row becomes a progress bar again, and that cost was weighed rather than
    /// missed — see `docs/decisions.md`.
    ///
    /// **`donePast`, never `doneToday`.** A span covers a run of days, so it is
    /// not the single day `doneToday` means; and under the two tiers (#334) a
    /// completion is lit but does not emit, which is exactly the difference
    /// between the two marks.
    var mark: SlotMark {
        switch state {
        case .open: .openToday
        // A rep that happened. Lit, whatever day of the week it fell on.
        case .filled: .donePast
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
/// > **A mark spans from the end of the previous mark through its own anchor
/// > day.**
///
/// That one sentence is the layout (#339, `docs/week-marks.md` §4), and it is
/// also the forgiveness mechanism. A day that goes by unused has no mark of its
/// own, so it is swallowed by whatever mark comes next — never a hole in the
/// row, and never an accusation. The app shows a failure only once one has
/// become arithmetically unavoidable, and then exactly as many as are.
///
/// **The rule used to be inferred rather than specified** (#4), read off two
/// large-widget frames in the design file. It is specified now. The inference
/// it replaces divided the columns before today *evenly* among the
/// completions, which put a mark's edge nowhere in particular; an anchored mark
/// ends on the day its rep happened, so the mark's left edge carries when.
///
///  - **A live row has `target` marks; a met row keeps every completion.** A
///    completion beyond the target is a bonus mark, capped naturally at seven
///    because the store holds at most one per civil day. Each mark is at least
///    one column wide and their ranges are ordered and contiguous. The latest
///    completion owns the remainder of a met week; a finished unmet row instead
///    has seven day-sized diary marks (#476, #495, #543).
///  - **A completion anchors on the day it was logged**, a lost rep is a
///    one-day cross on the earliest blank day it could have used. An open mark
///    ends on today while reps follow it; those reps divide the days after
///    today, **remainder to the right** (#340, #476).
///  - **A completed or open final mark ends on the final column.** A met 1x row
///    is one lit bar; an unmet 1x row is one open bar. The latter still writes
///    today on normal surfaces — geometry does not grant future editing (#495).
///  - **A completion logged today closes the row.** There is nothing open once
///    today is spent, so what follows the completions is arithmetic that
///    divides rather than a mark that ends on today.
///  - **A met goal keeps every completion on its day** (#342, widened by #543). It used to
///    collapse to one span across the week, which forgot what it had just
///    recorded; the latest mark runs to the end instead, including when it is a
///    bonus completion past the target.
///
/// Two numbers carry the reps that have run out of days (#81):
///
///  - **`lost`** — reps owed against days that no longer exist:
///    `max(0, repsLeft - actionableLeft)`, where an actionable day is one from
///    today onward that is not the rest day, and not today once today is spent.
///  - **`live`** — the rest, `repsLeft - lost`, of which at most one is open.
///
/// Those lost marks draw as a ✕ (#82). The strictness matters: `lost` uses
/// `repsLeft > actionableLeft`, not `>=`, so on Saturday with two reps owed and
/// Sunday still live the row stays clean. The mark says a miss has *become
/// unavoidable*; it is never a warning and never a prediction. In the shipping
/// seven-day path each loss is one day wide on the earliest blank day that rep
/// could have used. The retained legacy-rest-day path still uses #341's older
/// break-day pinning until the separate rest-day design work returns.
enum WeekSpans {
    /// The spans to draw, with today's one action decided by the cadence
    /// surface policy.
    ///
    /// **The arithmetic below does not know about `SlotEditing`** (#116). Which
    /// spans exist, how wide they are and which one is open are all decided by
    /// today, exactly as before — a span is a division of the week, and the
    /// week does not divide differently because it is editable. Since #543
    /// there is one policy, `.todayOnly`; the required parameter keeps a new
    /// cadence caller from inheriting an unstated editing scope.
    /// `restDay` is the weekday nothing is expected on, or nil for none — a
    /// parameter for the same reason the calendar is one (#181).
    static func spans(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        target: Int,
        editing: SlotEditing,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [SlotSpan] {
        _ = editing
        return divided(
            for: habit, in: week, today: today, target: target,
            restDay: restDay, calendar: calendar
        )
    }

    /// The day a tap on one column of a span writes, or nil where that column
    /// takes no write.
    ///
    /// `SlotEditing` decides whether the *surface* writes that day. This adds
    /// the one thing that depends on the span: **a filled span is an undo, and
    /// may only land on a day that carries a completion** (#256).
    ///
    /// `HabitStore.toggleCompletion` is a per-day toggle — on a day with
    /// nothing logged it *adds* a completion rather than removing one. A filled
    /// span covers columns that mostly have no dot on them, so without this a
    /// tap between the dots logged a new day. Before #543 that write was also
    /// visually hidden by the target clamp; it now becomes a bonus mark. This
    /// guard remains the correct inverse contract: a cadence-surface undo may
    /// only remove the exact day it names.
    ///
    /// An open span is untouched: it exists to *take* a completion, so the
    /// column under the finger is right whether or not anything is logged
    /// there.
    static func day(
        atColumn column: Int,
        of span: SlotSpan,
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        editing: SlotEditing,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date? {
        guard week.days.indices.contains(column) else { return nil }
        // A span covering a week the habit did not live in is not a division of
        // anything, so there is no day in it a tap could mean (#265). Daily
        // rows are deliberately different: a dot *is* a day, so one before the
        // habit existed stays tappable and back-filling it is allowed. What
        // #265 removes is the accusation, not the ability to log.
        guard habit.existed(on: week.days[column]) else { return nil }
        guard span.state != .filled || habit.completedDays.contains(week.days[column]) else {
            return nil
        }
        return editing.day(
            atColumn: column, in: week, today: today,
            restDay: restDay, calendar: calendar
        )
    }

    private static func divided(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        target: Int,
        restDay: Int?,
        calendar: Calendar
    ) -> [SlotSpan] {
        guard !habit.isSpacer else { return [] }
        let todayStart = WeekCalendar.day(today, calendar: calendar)
        let dayCount = week.days.count
        guard target > 0, dayCount == 7 else { return [] }

        // The columns completions landed on, in order. **These are the
        // anchors** (#339): a mark ends on the day its rep happened, and starts
        // wherever the mark before it ended, so the blank days between two
        // completions are swallowed rather than left as holes.
        let doneColumns = week.days.indices.filter { habit.completedDays.contains(week.days[$0]) }

        // **A week the habit did not live in asks for nothing** (#265). Without
        // this the arithmetic below runs normally: nothing is done, no day is
        // actionable, so every rep is dead and the row draws a ✕ per mark —
        // the app asserting a failure for a week that ended before the habit
        // was made. One unlit span across the week is the same claim a week
        // still to come makes, which is the true one.
        //
        // The whole week, not a day of it: a habit made mid-week was alive that
        // week, and the days before it in *that* week are the daily rows'
        // question rather than this one's. See `HabitSnapshot.existed(on:)`.
        if let last = week.days.last, !habit.existed(on: last) {
            guard !doneColumns.isEmpty else {
                return [SlotSpan(
                    index: 0, firstDay: 0, lastDay: dayCount - 1,
                    state: .inactive, actionDay: nil
                )]
            }
            // Edit History may record something that really happened before the
            // habit was added. Preserve every such fact while keeping #265's
            // promise: unlogged pre-creation days are inactive, never missed.
            // Day-sized marks are the only division that says both things
            // without making a cadence claim about a week the habit did not
            // yet owe (#543).
            let completed = Set(doneColumns)
            return week.days.indices.map { column in
                let isDone = completed.contains(column)
                return SlotSpan(
                    index: column,
                    firstDay: column,
                    lastDay: column,
                    state: isDone ? .filled : .inactive,
                    actionDay: nil
                )
            }
        }

        // Reps forgiven for the days before the habit existed (#343). Zero for
        // a habit that lived the whole week, which is every habit made before
        // this one.
        let credit = credit(for: habit, in: week, target: target, calendar: calendar)
        let requiredCompletions = target - credit
        let done = doneColumns.count
        let repsLeft = max(0, requiredCompletions - done)
        let doneToday = habit.completedDays.contains(todayStart)
        // The rest day stops these rows like any other: nothing can be logged
        // on it and nothing un-logged, so no mark carries an action and the
        // mark that would be open waits, unlit. Same rule as `WeekGrid`, and
        // the store refuses the write even if a stale surface offers one.
        let todayRests = WeekPreferences.isRestDay(
            todayStart, restDay: restDay, calendar: calendar
        )
        let lastColumn = dayCount - 1

        // **The goal is met, and the row still says when** (#342). It used to
        // return one span across the whole week, which forgot every day it had
        // just recorded the moment the last rep landed. Each completion keeps
        // its own mark on its own day; the last one runs to the end, because
        // there is nothing after it to divide.
        guard repsLeft > 0 else {
            // The credit marks pack left, unlit: they are arithmetic, not a
            // claim that anything was done, so a met row that was partly
            // forgiven still says so.
            let marks = Array(
                repeating: Mark(state: .inactive, anchor: nil), count: credit
            ) + completionMarks(
                doneColumns,
                required: requiredCompletions,
                in: week
            )
            let spans = assignColumns(marks, lastColumn: lastColumn)
            return withUndo(
                spans, doneToday: doneToday, todayRests: todayRests, today: todayStart
            )
        }

        let todayIndex = week.days.firstIndex(of: todayStart)

        // A week that has not started: nothing has been lost and nothing is
        // open, so the seven columns divide evenly and the completions — a
        // future week can hold them, through an edit or a sync — pack left.
        // Nothing here is anchored: a week nobody has reached is arithmetic.
        if todayIndex == nil, week.start > todayStart {
            let marks = (0..<target).map {
                Mark(state: $0 >= credit && $0 < credit + done ? .filled : .inactive, anchor: nil)
            }
            return assignColumns(marks, lastColumn: lastColumn)
        }

        // Rest days are retired from the shipping app (#390), and their return
        // has its own design work. #476 deliberately changes only the live
        // seven-day rule; a stored legacy rest day keeps the division it had.
        if restDay == nil {
            return dividedWithoutRestDay(
                for: habit,
                in: week,
                today: todayStart,
                todayIndex: todayIndex,
                credit: credit,
                doneColumns: doneColumns,
                repsLeft: repsLeft,
                doneToday: doneToday,
                lastColumn: lastColumn
            )
        }

        // The columns a rep could still land on: every day from today onward
        // that is not the rest day and does not already carry a completion —
        // **a weekly cadence holds one completion per day (R3), so a day that
        // has one has no room for a second** (#381).
        //
        // That rule used to be applied to today alone (`doneToday ? > : >=`),
        // which is the only day it can reach when every completion is in the
        // past. It is not: the week view opens the days *after* today on a
        // demo-seeded store, and moving the rest day in Settings turns a day
        // that was logged into a day nothing may be logged on. Both put a
        // completion where this count was still offering the day, so `lost`
        // came out smaller than the days `deadDays` had already found — and
        // `lost - dead.count` went negative into `Array(repeating:count:)`,
        // which traps. Six TestFlight crashes on build 202608282309 were this.
        //
        // Excluding a completed day here is also what keeps this count and the
        // walk in `deadDays` measuring the same thing; see the capacity note
        // there. The two must agree, and the trap is what happens when they do
        // not.
        //
        // This is the whole of the rest day's part in the arithmetic. The
        // *shape* still divides seven columns and subtracts the rest column
        // from what is drawn (`RestWindow`, #73); what counting `A` does is
        // bring the squeeze forward by a day, which is a fact about the week
        // rather than about the drawing.
        let actionable = (0...lastColumn).filter {
            !WeekPreferences.isRestDay(week.days[$0], restDay: restDay, calendar: calendar)
        }
        let completedColumns = Set(doneColumns)
        let actionableLeft: Int
        if let todayIndex {
            actionableLeft = actionable.count {
                $0 >= todayIndex && !completedColumns.contains($0)
            }
        } else {
            // A week already over. Every rep still owed has run out of days.
            actionableLeft = 0
        }

        // Reps with no day left to land on, and reps that still have one.
        let lost = max(0, repsLeft - actionableLeft)
        let live = repsLeft - lost

        // The days those reps ran out on. The walk cannot produce more than
        // `lost` — see `deadDays` — and produces fewer only in the one case
        // §5.1 names, where there is no blank column left to pin to.
        let dead = deadDays(
            owed: target - credit,
            completed: Set(doneColumns),
            past: 0..<(todayIndex ?? dayCount),
            actionable: actionable,
            existed: { habit.existed(on: week.days[$0]) }
        )

        // The mark list, in reading order. `assignColumns` turns it into
        // columns; nothing below this decides a boundary.
        //
        // **A dead rep with no column to pin to floats** (§5.1): it keeps its
        // place in the order and takes the leftmost free column. Reachable only
        // by editing a mid-week habit's target upward, where the credit stays
        // frozen while the target grows — the one place a ✕ lies about its day.
        var marks = Array(repeating: Mark(state: .inactive, anchor: nil), count: credit)
        marks += Array(
            repeating: Mark(state: .missed, anchor: nil), count: lost - dead.count
        )

        // The open mark, before it takes its place in the list.
        //
        // Split out from the append it used to be so that it can be *sorted in*
        // below rather than added after — see there.
        var open: Mark?
        var upcoming = 0
        if live > 0 {
            // The last day that still leaves one *actionable* column for each
            // rep behind this one. Columns and actionable days are not the same
            // count once a rest day is in the week, and it is the actionable
            // one a rep needs.
            let deadline = actionable[actionable.count - live]
            // Open only when today can actually carry it: not a rest day, not
            // already spent, and inside this week. Otherwise the mark keeps its
            // place and its geometry and simply asks for nothing.
            let isOpen = todayIndex != nil && !doneToday && !todayRests
            // **The open mark ends on today** (§4.2), unless it is the last in
            // the row, where `assignColumns` runs it to the end of the week.
            // Once today is spent there is no open mark at all, and what
            // follows the completions is arithmetic that divides.
            let anchor: Int? = doneToday ? nil : todayIndex.map { min($0, deadline) }
            open = Mark(
                state: isOpen ? .open : .inactive,
                anchor: anchor,
                actionDay: isOpen ? todayStart : nil
            )
            upcoming = live - 1
        }

        // Every anchored mark, in day order. Completions, dead reps and the
        // open mark interleave by day: a rep that ran out on Tuesday comes
        // before a completion logged on Wednesday, because a mark ends on its
        // own day and the days are in order.
        //
        // **The open mark is sorted in here rather than appended after** (#382).
        // It used to be added once the completions and dead reps were already
        // sorted, which is right only while every completion is in the past —
        // then every anchor to its left is already `<= todayIndex`. A
        // completion logged *after* today is an anchor to the right of the open
        // mark's, in a list `assignColumns` reads left to right, so the columns
        // came out in list order and the two swapped: today's ring was drawn on
        // a day it is not, and the completion's mark ended before the day it
        // was logged on. Both are things §4 says a mark never does, and neither
        // needs the anchor rule bent to fix — it needs applying to one more
        // mark. Arbitrary-day editing moved to Edit History in #543; cadence
        // surfaces only resolve today's action here now.
        //
        // A spent today has no anchor and cannot sort: it is not an event on a
        // day, it is the arithmetic that divides what the completions leave, so
        // it keeps its place after them.
        var anchored = doneColumns.map {
            Mark(state: .filled, anchor: $0, completionDay: week.days[$0])
        }
            + dead.map { Mark(state: .missed, anchor: $0) }
        if let open, open.anchor != nil { anchored.append(open) }
        marks += anchored.sorted { ($0.anchor ?? 0) < ($1.anchor ?? 0) }
        if let open, open.anchor == nil { marks.append(open) }
        marks += Array(repeating: Mark(state: .inactive, anchor: nil), count: upcoming)

        let spans = assignColumns(marks, lastColumn: lastColumn)
        return withUndo(spans, doneToday: doneToday, todayRests: todayRests, today: todayStart)
    }

    /// The shipping seven-day division settled in #476.
    ///
    /// An open rep owns every still-claimable day through today. While another
    /// rep follows, it stops there and future reps divide only future days,
    /// with shorter windows nearest today. When the open rep is final, it owns
    /// the remainder of the week (#495). Logging today changes that window to
    /// filled without moving its division; tomorrow's pass redistributes any
    /// future windows that remain.
    ///
    /// A rep that has run out is no longer a stretched mark ending on the day
    /// the week became unwinnable. It is one cross on the first blank day the
    /// rep could have used, and the next mark absorbs the days it gives up. A
    /// finished, unmet week is the diary form of the same rule: every blank day
    /// is a one-day cross. A met week returned above and never reaches either
    /// path, so it carries completions and no crosses.
    private static func dividedWithoutRestDay(
        for habit: HabitSnapshot,
        in week: Week,
        today: Date,
        todayIndex: Int?,
        credit: Int,
        doneColumns: [Int],
        repsLeft: Int,
        doneToday: Bool,
        lastColumn: Int
    ) -> [SlotSpan] {
        let completed = Set(doneColumns)

        // The week is over and the goal was not met. Pills only describe a rep
        // that happened; every other day is now a day that did not. Keeping the
        // seven day-sized marks also makes every correction in the pager name
        // the exact day it changes.
        guard let todayIndex else {
            return week.days.indices.map { column in
                let state: SlotState
                if completed.contains(column) {
                    state = .filled
                } else if habit.existed(on: week.days[column]) {
                    state = .missed
                } else {
                    state = .inactive
                }
                return SlotSpan(
                    index: column,
                    firstDay: column,
                    lastDay: column,
                    state: state,
                    actionDay: nil
                )
            }
        }

        // Today and every blank day after it can still carry one rep. The
        // strict subtraction keeps the final live rep open rather than warning
        // about a loss that has not happened.
        let actionableLeft = (todayIndex...lastColumn).count {
            !completed.contains($0)
        }
        let lost = max(0, repsLeft - actionableLeft)
        let live = repsLeft - lost

        // Lost reps take the earliest blank days on which they could have
        // happened. A mid-week habit normally excludes its pre-creation days;
        // the fallback is only the old upward-edit edge where frozen credit
        // leaves more real losses than post-creation columns to pin them to.
        let blankPast = (0..<todayIndex).filter { !completed.contains($0) }
        var lostColumns = Array(
            blankPast.lazy.filter { habit.existed(on: week.days[$0]) }.prefix(lost)
        )
        if lostColumns.count < lost {
            let alreadyPinned = Set(lostColumns)
            lostColumns += blankPast.filter { !alreadyPinned.contains($0) }
                .prefix(lost - lostColumns.count)
        }

        var marks = Array(
            repeating: Mark(state: .inactive, anchor: nil), count: credit
        )
        var anchored = doneColumns.map {
            Mark(state: .filled, anchor: $0, completionDay: week.days[$0])
        }
        anchored += lostColumns.map { Mark(state: .missed, anchor: $0) }

        let canOpen = live > 0 && !doneToday && habit.existed(on: today)
        if canOpen {
            anchored.append(Mark(state: .open, anchor: todayIndex, actionDay: today))
        }
        marks += anchored.sorted { ($0.anchor ?? 0) < ($1.anchor ?? 0) }

        // If today was just completed, all `live` reps are still the future
        // windows that were already on screen. Otherwise one of them is the
        // open rep and only the rest divide the days after today.
        let upcoming = live - (canOpen ? 1 : 0)
        marks += Array(repeating: Mark(state: .inactive, anchor: nil), count: upcoming)

        let spans = assignColumns(
            marks,
            lastColumn: lastColumn,
            finalAnchorExtendsToEnd: false,
            singleDayMisses: true
        )
        return withUndo(spans, doneToday: doneToday, todayRests: false, today: today)
    }

    /// Reps granted to a habit created part-way into this week (#343, §6).
    ///
    /// > `credit = max(0, target − days from the creation day to the end of the
    /// > week)`, frozen at creation, and on any target edit
    /// > `credit = min(frozen, max(0, new target − days from creation to week
    /// > end))`.
    ///
    /// A habit made on Friday has not failed the Monday it did not exist for.
    /// It is granted **the minimum credit that avoids a ✕, and not one more**:
    /// granting every pre-creation day would collapse the remaining reps into
    /// one wide pill, which reads as slack the habit does not have.
    ///
    /// **Frozen, so it can only shrink.** An upward edit gets no amnesty —
    /// 5x → 7x keeps the two it was granted rather than earning four — because
    /// the grant was for days that did not exist, and editing the target does
    /// not change how many of those there were. A downward edit does shrink it,
    /// because otherwise the row meets its goal off credit nobody earned: at
    /// 5x → 2x the two granted reps would be the whole target.
    ///
    /// Nil `targetAtCreation` means the row predates the column, and an unknown
    /// grant is no grant: it cannot be reconstructed, and claiming one would be
    /// the app inventing forgiveness it has no record of. Same rule as
    /// `createdDay` (#186, #265).
    ///
    /// Credit marks are unlit. They are arithmetic, not a claim that anything
    /// was done.
    private static func credit(
        for habit: HabitSnapshot,
        in week: Week,
        target: Int,
        calendar: Calendar
    ) -> Int {
        // Only a habit made *inside* this week is owed anything. One made
        // before it lived the whole week; one made after it is #265's case and
        // never reaches here.
        guard let created = habit.createdDay,
              let column = week.days.firstIndex(where: {
                  WeekCalendar.day($0, calendar: calendar) == created
              })
        else { return 0 }
        // The creation day counts itself: made on Friday, the week has Friday,
        // Saturday and Sunday left in it.
        let daysLeft = week.days.count - column
        // **A day before creation that carries a completion is not a day the
        // habit was forgiven for** (#415). `daysLeft` alone is the capacity of
        // a week nothing was back-filled into; a completion logged before the
        // creation day is a day a rep already landed on, so it adds to what the
        // target can be met out of exactly as a remaining day does.
        //
        // Without this the grant is not the minimum. A 6x habit made on
        // Wednesday with Monday and Tuesday logged has five days left and two
        // reps already banked — capacity seven against a target of six, so
        // nothing is unavoidable and nothing needs forgiving — and it was still
        // granted one. The over-grant is a mark: the credit mark takes column 0,
        // Monday's completion clamps up to 1 and Tuesday's to 2, and by the open
        // mark `assignColumns` has no column left before Thursday. The ring came
        // out on a day that is not today, breaking §3 invariant 4 and §4.2,
        // while `actionDay` stayed on today.
        //
        // So this is §6's own rule — "the minimum credit that avoids a ✕, and
        // not one more" — applied to a week the rule was written without: it
        // assumed no day before creation could carry anything. `DemoHistory`
        // writes exactly that week, and #265 lets a daily row back-fill one by
        // hand.
        let backfilled = (0..<column).count { habit.completedDays.contains(week.days[$0]) }
        let now = max(0, target - daysLeft - backfilled)
        guard let atCreation = habit.targetAtCreation else { return 0 }
        return min(max(0, atCreation - daysLeft), now)
    }

    /// The columns a rep ran out of days on (#341, `docs/week-marks.md` §5).
    ///
    /// > A **blank past day `d`** carries a dead rep when
    /// > `owed_through(d) > capacity_after(d)`, where
    /// > `owed_through(d) = target − credit − completions on or before d` and
    /// > `capacity_after(d)` is the days after `d` that can still carry one of
    /// > those reps: the blank actionable ones, plus the ones already
    /// > completed (#381).
    ///
    /// Pure, day-pinned, and computed from the record rather than from an event
    /// log — so a backfill recomputes it away with no stored state to migrate.
    /// It replaces `placeLost`, which parked a lost rep immediately left of the
    /// open span: a Monday missed on a 5x row surfaced on Thursday, a day it
    /// had nothing to do with.
    ///
    /// **The count is always right.** Walking the week,
    /// `owed_through − capacity_after` rises by exactly one on each blank
    /// actionable day, stays flat on each completed one — a completed day
    /// moves both sides by one — and stays flat on a blank rest day, which is
    /// in neither set. So it is monotone, and the days it is
    /// positive on are the last *k* blank days, where *k* is
    /// `max(0, repsLeft − actionableLeft)` today — the same `lost` the row is
    /// drawn from. The pinned ✕ and the arithmetic cannot disagree, and
    /// `WeekSpansTests` checks that equality rather than trusting it.
    ///
    /// **It never warns and never predicts.** A miss becomes a ✕ at the moment
    /// the day ends and the arithmetic tips, and not before: do Monday, Tuesday
    /// and Wednesday on a 3x row then stop, and the only ✕ lands on Saturday,
    /// which is exactly the day the week broke.
    ///
    /// **The rest day is not a day a rep can die on.** It is excluded from the
    /// candidates as well as from `actionable`, because nothing is expected on
    /// it (#72) and a ✕ there would be the app asking for a day it refuses to
    /// take. How the rest day should interact with the rest of this model is
    /// open and deliberately out of scope — see `docs/week-marks.md`,
    /// "Deferred, on purpose", and #346.
    private static func deadDays(
        owed: Int,
        completed: Set<Int>,
        past: Range<Int>,
        actionable: [Int],
        existed: (Int) -> Bool
    ) -> [Int] {
        past.filter { column in
            guard !completed.contains(column), actionable.contains(column) else { return false }
            // **A day before the habit existed is not a day it ran out on**
            // (#265). Credit normally makes this unreachable — `owed` is at
            // most the days from creation to the week's end, which is exactly
            // the count that keeps the inequality false before it. The one way
            // through is §5.1's: an upward target edit on a mid-week habit,
            // where the grant stays frozen while the target grows. The reps
            // that die there are real, and they lose their anchor and float
            // rather than pinning a ✕ to a day nothing was ever asked of.
            guard existed(column) else { return false }
            let owedThrough = owed - completed.count { $0 <= column }
            // What is left after `column` to carry those reps: every blank
            // actionable day, plus every day that already carries a completion
            // — that day has carried one, whether or not the rest day was
            // later moved onto it (#381).
            //
            // Counting `actionable.count { $0 > column }` instead double-books
            // in one direction and forgets in the other. A completion after
            // `column` is not subtracted from `owedThrough` — it is not on or
            // before the column — so the day it sits on has to be counted here
            // or the rep it satisfied is owed twice. And a completion on what
            // is now the rest day is not in `actionable` at all, so its day was
            // being dropped from both sides at once.
            //
            // With this the walk is monotone again: stepping from `d` to
            // `d + 1`, `owedThrough` drops by one if `d + 1` carries a
            // completion and the capacity drops by exactly the same one, so
            // the difference rises by one on each blank actionable day and by
            // nothing else. That is what makes this count equal to `lost`.
            let capacity = actionable.count { $0 > column && !completed.contains($0) }
                + completed.count { $0 > column }
            return owedThrough > capacity
        }
    }

    /// One repetition, before it has columns.
    ///
    /// `anchor` is the column the mark must **end** on: the day a completion
    /// was logged, the day a rep ran out, today for the open one. A mark
    /// without an anchor is arithmetic rather than an event — a rep still to
    /// come, or one granted for the days before a habit existed — and divides
    /// whatever its anchored neighbours leave it.
    private struct Mark {
        let state: SlotState
        let anchor: Int?
        var actionDay: Date?
        let completionDay: Date?
        let isBonus: Bool

        init(
            state: SlotState,
            anchor: Int?,
            actionDay: Date? = nil,
            completionDay: Date? = nil,
            isBonus: Bool = false
        ) {
            self.state = state
            self.anchor = anchor
            self.actionDay = actionDay
            self.completionDay = completionDay
            self.isBonus = isBonus
        }
    }

    /// Every real completion becomes a dated mark. Only the completions after
    /// the cadence's required count are bonuses; creation credit is
    /// forgiveness, not a completion, so it does not make a real logged day a
    /// bonus.
    private static func completionMarks(
        _ columns: [Int],
        required: Int,
        in week: Week
    ) -> [Mark] {
        columns.enumerated().map { offset, column in
            let bonus = offset >= required
            return Mark(
                state: .filled,
                anchor: column,
                completionDay: week.days[column],
                isBonus: bonus
            )
        }
    }

    /// Turns the mark list into the columns each mark covers.
    ///
    /// > **A mark spans from the end of the previous mark through its own
    /// > anchor day.**
    ///
    /// That sentence is the whole layout (#339), and it is also the forgiveness
    /// mechanism: a day nothing happened on has no mark of its own, so it is
    /// swallowed by whatever mark comes next rather than left as a hole.
    ///
    /// Four rules, and nothing else:
    ///
    ///  - **An anchored mark ends on its anchor** — clamped so every mark
    ///    before it and after it still has a column of its own. The clamp is
    ///    what the old completed block's `roomForTheRest` arithmetic did, and
    ///    it binds in exactly the same places: a completion logged late in a
    ///    week that still owes several reps cannot keep its own day, because
    ///    the reps behind it need the columns more than the record does.
    ///  - **A run of unanchored marks divides what its neighbours leave**, as
    ///    evenly as whole days allow, **remainder to the right** (#340). That
    ///    is the early bias: the near days are single columns and the slack
    ///    collects at the end of the week.
    ///  - A final filled or open mark ends on the final column. A caller can
    ///    keep another kind of final anchor on its own day by declining the
    ///    default extension (#476, #495).
    ///  - A caller can make anchored misses one day wide; the next mark then
    ///    absorbs the range the miss would otherwise have swallowed (#476).
    ///
    /// The result is ordered and non-overlapping, with exactly one span per
    /// mark and at least one column per span, and it covers all seven columns.
    /// The property sweep in `WeekSpansTests` checks those claims rather than
    /// trusting them.
    private static func assignColumns(
        _ marks: some Collection<Mark>,
        lastColumn: Int,
        finalAnchorExtendsToEnd: Bool = true,
        singleDayMisses: Bool = false
    ) -> [SlotSpan] {
        let marks = Array(marks)
        guard !marks.isEmpty else { return [] }
        let count = marks.count

        // Pass one: where every anchored mark ends. A final filled or open
        // anchor runs to the end of the week, which makes a 1x row one settled
        // or actionable bar. The surface's editing policy still decides which
        // day that shape can write (#495).
        var ends = [Int?](repeating: nil, count: count)
        var previousEnd = -1
        var previousIndex = -1
        for index in marks.indices {
            guard let anchor = marks[index].anchor else { continue }
            // One column for each mark since the last anchored one, and one
            // for each mark still to come. `low` never exceeds `high` while
            // there are no more marks than columns, which invariant 1 and a
            // target of 1...7 guarantee.
            let low = previousEnd + (index - previousIndex)
            let high = lastColumn - (count - 1 - index)
            // A completed or open final rep owns the remainder of the week.
            // Name both states: a final loss must never inherit this rule just
            // because the live path declined the general extension (#495).
            let end = index == count - 1
                && (finalAnchorExtendsToEnd
                    || marks[index].state == .filled
                    || marks[index].state == .open)
                ? lastColumn
                : max(low, min(anchor, high))
            ends[index] = end
            previousEnd = end
            previousIndex = index
        }

        // Pass two: fill. Each run of unanchored marks divides what the
        // anchored mark after it leaves; the run with no anchored mark after it
        // divides the rest of the week, the last of them landing on the final
        // column.
        var spans: [SlotSpan] = []
        var cursor = 0
        var runStart = 0
        for index in marks.indices {
            guard let end = ends[index] else { continue }
            for (offset, width) in widths(of: end - cursor, into: index - runStart).enumerated() {
                spans.append(span(
                    marks[runStart + offset], at: runStart + offset,
                    from: cursor, to: cursor + width - 1
                ))
                cursor += width
            }
            let first = singleDayMisses && marks[index].state == .missed
                ? end
                : cursor
            spans.append(span(marks[index], at: index, from: first, to: end))
            cursor = end + 1
            runStart = index + 1
        }
        for (offset, width) in widths(of: lastColumn - cursor + 1, into: count - runStart).enumerated() {
            spans.append(span(
                marks[runStart + offset], at: runStart + offset,
                from: cursor, to: cursor + width - 1
            ))
            cursor += width
        }
        return spans
    }

    private static func span(_ mark: Mark, at index: Int, from first: Int, to last: Int) -> SlotSpan {
        SlotSpan(
            index: index, firstDay: first, lastDay: last,
            state: mark.state, actionDay: mark.actionDay,
            completionDay: mark.completionDay, isBonus: mark.isBonus
        )
    }

    /// `columns` split into `count` widths, as evenly as whole days allow, with
    /// **the remainder to the right** (#340).
    ///
    /// A 6x week used to ship as a pill across Monday and Tuesday then five
    /// singles; it is five singles then a weekend pill. Missing a single costs
    /// nothing but room — the next mark reaches back over it — so the near days
    /// are pacing and the slack belongs at the end of the week.
    private static func widths(of columns: Int, into count: Int) -> [Int] {
        guard count > 0, columns >= count else { return [] }
        let base = columns / count
        let extra = columns % count
        return (0..<count).map { base + ($0 >= count - extra ? 1 : 0) }
    }

    /// Hands the undo to today's exact completion mark.
    ///
    /// Edit History can already contain a completion later than today, so the
    /// last filled span is not necessarily today's. Completion marks retain
    /// their factual date and make the cadence surface's one allowed undo
    /// unambiguous (#543).
    private static func withUndo(
        _ spans: [SlotSpan],
        doneToday: Bool,
        todayRests: Bool,
        today: Date
    ) -> [SlotSpan] {
        guard doneToday, !todayRests,
              let completion = spans.indices.first(where: {
                  spans[$0].state == .filled && spans[$0].completionDay == today
              })
        else { return spans }
        var spans = spans
        let s = spans[completion]
        spans[completion] = SlotSpan(
            index: s.index, firstDay: s.firstDay, lastDay: s.lastDay,
            state: s.state, actionDay: today,
            completionDay: s.completionDay, isBonus: s.isBonus
        )
        return spans
    }

}
