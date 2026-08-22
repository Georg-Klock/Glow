import CoreGraphics

/// The large widget's layout, in the design file's own numbers.
///
/// Lives in `Glow/Logic` rather than in the widget target because the app needs
/// one number out of it: how many rows the widget can show. The grid marks that
/// boundary, and a second copy of the figure in the app would be a copy that
/// could drift.
///
/// Node `83:1676` is authored at 1x — 338 × 354, which is the real point size of
/// a large widget on this phone — so these are read straight off it rather than
/// halved from a 2x frame or measured off a render.
///
/// Every value here is a *design* number. Nothing is derived from a screenshot
/// and nothing is rounded to something tidier; where the file is on a half point
/// this is too, because half a point is a real pixel at 2x and two of them at 3x.
enum WidgetMetrics {
    /// The large widget's own size, on a 6.1" iPhone. The design file is
    /// authored at exactly this, at 1x.
    static let largeWidth: CGFloat = 338
    static let largeHeight: CGFloat = 354

    /// How many rows a large widget shows.
    ///
    /// Eleven, and derived rather than written down — every input to it has
    /// moved at least once. The app reads this to mark where its grid stops
    /// being visible on the home screen.
    static var largeRowCapacity: Int {
        let track = largeWidth - padLeading - padTrailing - labelWidth - labelGap
        return rowCapacity(
            height: largeHeight - padVertical * 2,
            slot: SlotLayout.slotHeight(trackWidth: track),
            hasHeader: true
        )
    }

    /// Content inset. Not symmetric in the file, and left alone rather than
    /// averaged: the extra point on the right is what stops the last column
    /// sitting hard against the widget's rounded corner.
    static let padLeading: CGFloat = 15
    static let padTrailing: CGFloat = 16
    static let padVertical: CGFloat = 16

    /// Header to the first row, and row to row.
    static let headerGap: CGFloat = 13
    static let rowGap: CGFloat = 10

    /// The label column, and its distance to the track.
    static let labelWidth: CGFloat = 98
    static let labelGap: CGFloat = 15

    /// Inside the label: the icon's column, and where the name starts.
    ///
    /// The file places the name at x=28.5 with the symbol at x=0, so the icon
    /// column and the space after it have to add up to exactly that or every
    /// habit name in the widget sits a point off.
    static let iconWidth: CGFloat = 24
    static let iconGap: CGFloat = 4.5

    /// SF Pro Regular, one size for the habit name and every weekday letter.
    static let textSize: CGFloat = 12
    /// The habit icon is a step larger than the name it sits beside.
    static let iconSize: CGFloat = 14

    /// How far a habit name may run before it is truncated.
    ///
    /// Not the label column — a name is allowed to overflow it and use the gap
    /// before the track, which is how the design fits "Watch Sunset". The limit
    /// is where the track begins, so a name can never collide with the grid:
    ///
    ///     (label 98 + gap 15) − icon 24 − iconGap 4.5 = 84.5
    ///
    /// The longest name in the design measures 79, so nothing there reaches it.
    static let nameMaxWidth: CGFloat = (labelWidth + labelGap) - iconWidth - iconGap

    /// The weekday header's own row: shorter than a slot row, and its cells are
    /// wider than a slot with almost no gap, because a letter needs the width
    /// and a slot does not.
    static let headerHeight: CGFloat = 14

    /// How many habit rows fit in a given height.
    ///
    /// Derived rather than written down, so it cannot drift when the padding,
    /// the gap or the slot changes — all three have moved at least once. The
    /// Eleven for the large family, and asserted by a test rather than
    /// written down anywhere: every input to it has moved at least once.
    ///
    /// `height` is the content box, inside the vertical padding.
    static func rowCapacity(height: CGFloat, slot: CGFloat, hasHeader: Bool) -> Int {
        guard slot > 0 else { return 0 }
        let available = height - (hasHeader ? headerHeight + headerGap : 0)
        guard available > 0 else { return 0 }
        // n slots and n-1 gaps fit in `available`.
        return max(0, Int((available + rowGap) / (slot + rowGap)))
    }

    // No background constants any more. The design draws a gradient container
    // and the widget followed it for a while; on a real home screen it read as
    // a panel sitting on the wallpaper rather than marks floating on it. See
    // GlowWidget.swift.
}
