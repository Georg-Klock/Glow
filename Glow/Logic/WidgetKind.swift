import Foundation
import WidgetKit

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
enum WidgetKind: String, CaseIterable, Sendable {
    case week = "GlowWidget"
    case month = "GlowMonthSmall"

    static var allNames: Set<String> { Set(allCases.map(\.rawValue)) }

    /// The families this kind can actually be placed in.
    ///
    /// **This is the list `supportedFamilies` is declared from**, not a second
    /// copy of it — `GlowWidget` and `MonthWidget` read it, and so does the
    /// Widgets tab (#210). A page that offers a size the extension does not
    /// serve is a page telling somebody to look for something that is not in
    /// the gallery, and a page missing one is a size nobody is told about; both
    /// are what a second list eventually produces.
    var families: [WidgetFamily] {
        switch self {
        // Small, medium and large, each independently placeable: three widgets
        // as far as the Home Screen is concerned, from one kind.
        case .week: [.systemSmall, .systemMedium, .systemLarge]
        // Small only, deliberately — see `MonthWidget`.
        case .month: [.systemSmall]
        }
    }

    /// What the widget gallery calls this kind, without the app's name in
    /// front of it. `configurationDisplayName` is `"Glow Up: \(displayName)"`,
    /// which is how the gallery has always read; inside the app the prefix
    /// would only repeat the app you are already in.
    var displayName: String {
        switch self {
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    /// The gallery's own sentence about the widget, and the Widgets tab's.
    /// Same words in both places, because they are answering the same question.
    var summary: String {
        switch self {
        case .week: "Your habits for the week. Tap today's slot to log it."
        case .month: "One habit's month. Tap today's dot to log it."
        }
    }
}
