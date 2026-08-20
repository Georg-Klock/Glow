import CoreGraphics

/// The large widget's layout, in the design file's own numbers.
///
/// Node `83:1676` is authored at 1x — 338 × 354, which is the real point size of
/// a large widget on this phone — so these are read straight off it rather than
/// halved from a 2x frame or measured off a render.
///
/// Every value here is a *design* number. Nothing is derived from a screenshot
/// and nothing is rounded to something tidier; where the file is on a half point
/// this is too, because half a point is a real pixel at 2x and two of them at 3x.
enum WidgetMetrics {
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

    /// The weekday header's own row: shorter than a slot row, and its cells are
    /// wider than a slot with almost no gap, because a letter needs the width
    /// and a slot does not.
    static let headerHeight: CGFloat = 14

    /// The container gradient. Very nearly nothing — five percent of a light
    /// grey down to fifteen percent of a near-black — but it is what keeps the
    /// widget from disappearing entirely on a black wallpaper.
    static let backgroundTop = (red: 70.0 / 255, green: 70.0 / 255, blue: 73.0 / 255, alpha: 0.05)
    static let backgroundBottom = (red: 10.0 / 255, green: 10.0 / 255, blue: 15.0 / 255, alpha: 0.15)
}
