import CoreGraphics

/// How wide This Week's panel may grow before the surplus becomes margin
/// (#634).
///
/// **At compact width, the large widget's own 338pt** (#588): every iPhone,
/// and a narrow iPad window, draws the widget at its true size or smaller.
///
/// **At regular width, the readable-content width** — the 672pt UIKit's
/// `readableContentGuide` settles on at the default text size, which is the
/// width the system itself considers one comfortable column on an iPad. Up to
/// there the grid grows in the widget's proportions: marks, type, label column
/// and track together, by one factor, so the screen is still the widget, seen
/// closer. #588's "never larger" was written for phones, where a larger widget
/// was a wider phone's surplus turned into bigger marks; on an iPad the same
/// cap drew a 338pt card in the middle of a 1180pt screen.
///
/// A parameter of the size class, not of the device. Stage Manager, Split
/// View and any phone whose width changes reach both size classes, and
/// `WeeklyGridView` reads `horizontalSizeClass` at its boundary and hands the
/// answer in, the way `calendar:` and `restDay:` arrive.
enum PanelCeiling {
    /// UIKit's readable width at regular width and the default text size.
    static let regularWidth: CGFloat = 672

    static func maximumPanelWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? regularWidth : WidgetMetrics.largeWidth
    }
}
