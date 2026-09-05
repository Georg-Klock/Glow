import CoreGraphics

/// Whether a change moves, decided in one place for every surface.
///
/// The app has two kinds of animation. **A completion arriving** is drawn three
/// ways: the ring closing (`SlotView`), the bar closing (`SpanView`), and the
/// label dimming beside it (`HabitRowView`). It was four while the Today ring's
/// sweep shipped (#209). Reduce Motion was honoured in one of those, plus the
/// widget's burst, which records the setting at the tap and leaves a timeline
/// with one still entry in it (`WidgetBurst`, #107). SPEC §3's "Reduce Motion
/// snaps" was written about the ring and read as if it covered the grid; it did
/// not (#137).
///
/// **A row leaving the list** is the second kind, added by #398. It is not a
/// completion and it is not a reward — it is the list closing a gap, and it
/// exists because a row that vanishes between two frames reads as a glitch
/// rather than as a delete. It gets its own rule here rather than inheriting
/// whatever a bare `.onDelete` animates by default, which was the whole point
/// of that issue's flag.
///
/// The rules are here rather than in each view for the reason `WeekGrid`'s
/// are: a predicate in a view is a predicate no test can reach, and three
/// copies of "and not while Reduce Motion is on" is three chances to keep two.
///
/// **The reduced path is a snap, not a shorter animation.** A quicker sweep is
/// still a sweep; what the setting asks for is the final state, arrived at with
/// nothing scheduled in between — no closing layer, no delayed hand-back, no
/// intermediate frame at all. Each caller expresses that by taking its "no
/// animation" branch, which is the branch that already exists for every other
/// state change, so the reduced path is the app's own instant path rather than
/// a second one written for accessibility.
enum MotionPolicy {
    /// Whether a mark's change of state cross-fades, or lands in one frame.
    ///
    /// **A cross-fade, not a closing** (2026-09-05). Until then a ring became a
    /// dot or a bar by shrinking — `SlotView.close`, a 0.34s spring — and the
    /// undo landed instantly. Georg asked for the morph to go: the old mark
    /// and the new one now cross-fade in `SlotView.close`'s 0.12s, in both
    /// directions, so a ring turning into a pill and a pill turning back are
    /// the same quick event rather than one animation and one cut.
    ///
    /// **Reduce Motion takes the instant path**, as everywhere else here: the
    /// final state with nothing scheduled in between (SPEC).
    ///
    /// **Today's bonus tap on a met row is not this case, and that is a
    /// decision rather than an omission.** The bar covering today is already
    /// lit, and the tap splits it into two lit bars — the covering mark ending
    /// on its own day and today's taking the remainder. Neither of those views
    /// existed before the tap (`SlotSpan.id` is the range), so nothing survives
    /// the split to fade; the row arrives at its new shape in one frame, which
    /// is the same instant path Reduce Motion takes and the same one the undo
    /// takes back. A grown-in reveal would also be the app applauding a rep the
    /// week did not ask for, which SPEC §1's "brightness must not mean well
    /// done" reaches as well.
    static func crossfadesMark(
        from previous: SlotMark,
        to next: SlotMark,
        reduceMotion: Bool
    ) -> Bool {
        previous != next && !reduceMotion
    }

    /// Whether a deleted row collapses over time, or is simply gone.
    ///
    /// **The reduced path is the app's own instant path**, as everywhere else
    /// here: `withAnimation(nil)` around the same store write, so the list
    /// arrives at the state it was going to arrive at with no frame in
    /// between. A shorter collapse would still be a collapse.
    ///
    /// Not conditioned on *why* the row left. Swipe-delete and edit mode's
    /// minus button remove the same row from the same list, and a rule that
    /// told them apart would be animating the gesture rather than the change.
    static func collapsesRemoval(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Whether entering or leaving list edit mode moves the rows and chrome.
    ///
    /// This transition is neither a completion reward nor a row removal, so it
    /// owns a named rule rather than borrowing either one's meaning. The
    /// reduced path is the same instant state change with no frames between.
    static func changesEditMode(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// How far a press pushes a mark past its resting size.
    ///
    /// A press growing 32% and springing back is the same overshoot the
    /// completion is built on, and it is motion under a fingertip: 1 is the
    /// scale that does not move. The `ButtonStyle` keeps its `.animation` —
    /// animating a value that never changes costs nothing and keeps one code
    /// path rather than two.
    static func pressScale(_ scale: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : scale
    }
}
