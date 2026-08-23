import Foundation

/// The kind string of every widget this bundle ships.
///
/// **A kind is a persistent identifier, not a label.** WidgetKit stores it
/// against every widget a person has placed, so renaming one orphans their
/// widget — it stops being the thing they configured. That is why these live
/// here as a fixed list rather than being spelled out at each `StaticConfiguration`
/// and again wherever a reload is asked for.
///
/// It is also what makes `reloadTimelines(ofKind:)` usable at all: a kind that
/// drifts from the widget's own is not an error, it is a reload that silently
/// does nothing. One source, read by both. See `WidgetRefresh` and #134.
///
/// **`GlowTodaySmall` and `GlowTodayMedium` were here and are gone** (#209).
/// Removing a kind is not renaming one, and the difference is where the loss
/// lands: a rename leaves a widget on somebody's Home Screen configured against
/// a kind nothing serves, while removing the widget entirely takes it off the
/// Home Screen with the extension that drew it. That is what pulling a feature
/// does, and it is intended here rather than routed around. The strings are not
/// reusable for anything else — they name the Today widget in WidgetKit's own
/// records, and 2.0 restoring the feature should restore them exactly.
enum WidgetKind: String, CaseIterable {
    case week = "GlowWidget"
    case month = "GlowMonthSmall"

    static var allNames: Set<String> { Set(allCases.map(\.rawValue)) }
}
