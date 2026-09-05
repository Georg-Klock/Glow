import CoreGraphics
import SwiftUI

/// Whether a habit row gives its icon column to the name, so the name can
/// grow with the reader's text size (#567).
///
/// **Text on the grid is `WidgetMetrics.textSize` × scale whatever the reader
/// has asked for**, and that was a decision (docs/decisions.md, 2026-08-24):
/// the screen is the large widget at one factor, and a label column that grows
/// on its own is the one thing a scaled copy cannot have. The same entry named
/// the middle position — exact fidelity at the default size, growth only once
/// someone has actually asked for larger text — and this is it, with one
/// departure: growth is behind a toggle rather than automatic, because it
/// changes *what the row shows*, not only how large. The icon goes.
///
/// Two conditions, both required. The toggle says the person would rather have
/// a bigger name than a glyph; the type size says they have asked iOS for
/// bigger text at all. With either missing the row is exactly what it was —
/// icon in its 24pt column, name at 12pt — so the render baselines, which pin
/// the default state, do not move.
///
/// Pure and here rather than in `RowGeometry` or the widget, for the reason
/// `TypeTier` is: two surfaces draw this row and a rule written twice drifts.
/// `SwiftUI` is imported for `DynamicTypeSize` alone — a value type, the way
/// `WidgetMetrics` imports `WidgetKit` for `WidgetFamily` — and the toggle
/// arrives as a parameter, read once at the view or widget boundary from
/// `GlowSettings`, never here.
enum LargeTextPolicy {
    /// What one row draws in its label column: whether the icon is there, and
    /// how large the name is — in the design's own points, before the screen's
    /// scale factor. `RowGeometry` multiplies; the widget uses it as is.
    struct Layout: Equatable, Sendable {
        let showsIcon: Bool
        let textSize: CGFloat

        /// The row as designed: icon and a 12pt name.
        static let standard = Layout(showsIcon: true, textSize: WidgetMetrics.textSize)

        /// How far the name may run. With the icon, the label column less the
        /// icon and the one gap between them — `WidgetMetrics.nameMaxWidth`'s
        /// derivation. Without it, the whole column: the name starts where
        /// the icon started and reclaims `iconWidth + iconGap`.
        ///
        /// Floored at zero for `RowGeometry.nameMaxWidth`'s reason (#136): it
        /// is a difference, and a zero proposal makes it negative.
        func nameMaxWidth(labelWidth: CGFloat, iconWidth: CGFloat, iconGap: CGFloat) -> CGFloat {
            showsIcon ? max(0, labelWidth - iconWidth - iconGap) : max(0, labelWidth)
        }
    }

    /// The size iOS treats as the default — `.large`. Anything above it is a
    /// reader who has asked for larger text; anything at or below it is not.
    ///
    /// **Any step above the default, not only the accessibility sizes.** The
    /// issue left that open. The accessibility range starts at `xxxLarge` +1,
    /// where body text is already 28pt against 17 — a reader who set xLarge
    /// asked for larger text too, and answering only the loudest request would
    /// leave three of the five larger steps doing nothing.
    static let defaultSize: DynamicTypeSize = .large

    /// Whether this type size is one the reader has raised above the default.
    static func isLargerThanDefault(_ size: DynamicTypeSize) -> Bool {
        size > defaultSize
    }

    /// The row's label layout for a toggle state and a type size.
    static func layout(dropsIcon: Bool, size: DynamicTypeSize) -> Layout {
        guard dropsIcon, isLargerThanDefault(size) else { return .standard }
        return Layout(showsIcon: false, textSize: textSize(for: size))
    }

    /// The name's size at a type size the reader has raised: the design's 12pt
    /// scaled by the same factor iOS applies to body text, then capped.
    ///
    /// **Capped at `WidgetMetrics.textSizeCap`, whatever the setting.** The
    /// issue asked whether the cap should climb at the largest accessibility
    /// sizes. It does not: the label column is 98pt and does not grow, so a
    /// name at 20pt already reads about half the characters a 12pt one did,
    /// and beyond that the row would be an ellipsis with a track beside it.
    /// The cap lands at `accessibility2` and holds from there.
    ///
    /// | size | body | name |
    /// | --- | --- | --- |
    /// | xLarge | 19 | 13.41 |
    /// | xxLarge | 21 | 14.82 |
    /// | xxxLarge | 23 | 16.24 |
    /// | accessibility1 | 28 | 19.76 |
    /// | accessibility2… | 33… | 20 |
    static func textSize(for size: DynamicTypeSize) -> CGFloat {
        guard isLargerThanDefault(size) else { return WidgetMetrics.textSize }
        let factor = bodyPoints(for: size) / bodyPoints(for: defaultSize)
        return min(WidgetMetrics.textSizeCap, WidgetMetrics.textSize * factor)
    }

    /// iOS's body text size at each Dynamic Type step, in points — the
    /// Human Interface Guidelines' own table, so the name grows at the rate
    /// the rest of the phone's text does rather than at a rate of this app's.
    ///
    /// A table rather than `UIFontMetrics`: that reads the *process's* content
    /// size category, which is not the environment a widget is rendered in,
    /// and a table is a thing a test can hold. A step this table does not know
    /// — a future one — is treated as the last one it does, which above the
    /// default is the cap.
    static func bodyPoints(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: size > defaultSize ? 53 : 17
        }
    }
}
