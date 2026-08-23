import CoreGraphics
import WidgetKit

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

    /// A small widget's own size, on the same phone. Square, and the width the
    /// medium and large families share is two of these plus the gap between
    /// them.
    static let smallSide: CGFloat = 158

    /// What the system gives each family on a 6.1" iPhone.
    ///
    /// One list, three readers: the render harness renders every family at its
    /// own size, the Widgets tab previews the real views at theirs (#210), and
    /// `largeRowCapacity` above is the same numbers by another name. A preview
    /// at a size no phone gives is a preview of a layout nobody sees — the slot
    /// size falls out of the track width, so a widget drawn 20pt narrow is not
    /// the same widget slightly smaller.
    ///
    /// Sizes do vary by device; this is the phone the design is authored
    /// against, and the previews scale from here rather than measuring the
    /// screen they are on.
    static func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: CGSize(width: largeWidth, height: smallSide)
        case .systemLarge: CGSize(width: largeWidth, height: largeHeight)
        // Small, and anything this app does not ship — a square is the least
        // wrong answer, and `WidgetKind.families` is what keeps the question
        // from being asked.
        default: CGSize(width: smallSide, height: smallSide)
        }
    }

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
    /// 15, not the file's 16 — the one number in this type that is not the
    /// design's, and the point it gives up buys the medium widget's fifth row.
    ///
    /// The medium family missed five rows by hundredths of a row on every phone
    /// measured: 126pt of content against a 27.45pt pitch is 4.95 rows, and the
    /// hard cut takes the floor. One point anywhere in that sum closes it, and
    /// there were two candidates. `rowGap` is the other, and it is the one that
    /// must not move: it is set by how far a halo spills out of a row, so
    /// closing it would put each row's light into its neighbour — a functional
    /// number wearing a spacing number's clothes. `padVertical` is a margin
    /// against the widget's own rounded edge and carries no such job, so it is
    /// the one that gives.
    ///
    /// The large family is unaffected: 11 rows before and after, because its
    /// spare change was never within a point of the next row. `WidgetMetricsTests`
    /// asserts both counts. See #57.
    static let padVertical: CGFloat = 15

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
