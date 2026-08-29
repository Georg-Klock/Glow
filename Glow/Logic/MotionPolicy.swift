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
    /// Whether a slot or a span closes over time.
    ///
    /// Only a completion just made animates, which was already the rule:
    /// un-completing is a correction, and animating a correction dresses a
    /// mistake up as an achievement. Reduce Motion adds the second clause.
    static func closesCompletion(
        from previous: SlotState,
        to next: SlotState,
        reduceMotion: Bool
    ) -> Bool {
        previous == .open && next == .filled && !reduceMotion
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
