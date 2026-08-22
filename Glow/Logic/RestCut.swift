import CoreGraphics

/// Which rows the rest day's line runs through, and where across them it sits.
///
/// The cut is one vertical line down the rest day's column, and where it starts
/// and stops is a decision rather than a drawing detail: it lands on a habit at
/// both ends. Above the first habit is the header's air and below the last one
/// is the end of what the surface shows, and a line running into either says
/// the week is stopped somewhere there is no week.
///
/// A blank row *between* two habits still draws its segment. The line is a cut
/// through the grid, not a mark on each row, and a gap the user placed is part
/// of the grid it cuts.
///
/// Here rather than in a view because both surfaces need the same answer and
/// they compute their row lists differently: the widget takes `capacity` rows
/// and stops, the app draws all of them and marks the widget's boundary with a
/// hairline. Passing the capacity in is what makes the app's line end on that
/// hairline rather than at the bottom of a list that scrolls.
enum RestCut {
    /// The inclusive range of row indices that draw the line, or nil when none
    /// does — no rest day is not this type's business, but a surface with no
    /// habit on it is.
    ///
    /// `capacity` is how many rows the surface shows. Rows past it are not
    /// considered at all, so a habit below the widget's boundary neither
    /// extends the line nor starts one.
    static func rows(_ rows: [HabitSnapshot], capacity: Int) -> ClosedRange<Int>? {
        let visible = rows.prefix(max(0, capacity))
        guard let first = visible.firstIndex(where: { !$0.isSpacer }),
              let last = visible.lastIndex(where: { !$0.isSpacer })
        else { return nil }
        return first...last
    }

    /// The centre of the rest day's column, measured from the row's leading
    /// edge — so it includes the label column the track starts after.
    ///
    /// One formula for both surfaces. The widget's small family passes zero for
    /// the label column and its gap, which is exactly what it draws, so the
    /// same line comes out without a second case.
    static func x(
        restIndex: Int,
        trackWidth: CGFloat,
        labelWidth: CGFloat,
        labelGap: CGFloat
    ) -> CGFloat {
        labelWidth + labelGap
            + SlotLayout.columnCentre(trackWidth: trackWidth, index: restIndex)
    }
}
