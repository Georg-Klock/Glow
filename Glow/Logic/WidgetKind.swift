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
enum WidgetKind: String, CaseIterable {
    case week = "GlowWidget"
    case todaySmall = "GlowTodaySmall"
    case todayMedium = "GlowTodayMedium"
    case month = "GlowMonthSmall"

    static var allNames: Set<String> { Set(allCases.map(\.rawValue)) }
}
