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
    /// front of it. The gallery itself shows `galleryName`, which puts the app
    /// in front; inside the app the prefix would only repeat the app you are
    /// already in.
    var displayName: String {
        switch self {
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    /// The gallery's own title, prefixed with the app — the exact argument
    /// `configurationDisplayName` is given.
    ///
    /// **This exists as a `String` property because the alternative crashed the
    /// extension** (#254). Written at the call site as
    /// `.configurationDisplayName("Glow Up: \(displayName)")`, the interpolated
    /// literal binds to the `LocalizedStringKey` overload rather than the
    /// `StringProtocol` one, and a `LocalizedStringKey` carrying an interpolated
    /// segment is *formatted text*. WidgetKit refuses it — `WidgetKit/Text.swift`
    /// traps with "Formatted text for `…` is not supported" — inside its own
    /// evaluation of the widget's body, before any provider runs.
    ///
    /// A `String` binds to the `StringProtocol` overload, which is plain text
    /// and is what the literal was before #210 introduced the interpolation.
    /// `summary` was never affected for the same reason: it is a property, so
    /// `.description(_:)` has always taken the string overload.
    var galleryName: String { "Glow Up: \(displayName)" }

    /// The gallery's own sentence about the widget — `configurationDisplayName`'s
    /// companion, read by `GlowWidget` and `MonthWidget` as `.description(_:)`.
    ///
    /// **It used to be the Widgets tab's sentence too, and is not any more**
    /// (#237). In the gallery it is the only thing there is: a scrolling list
    /// of unfamiliar tiles, where a sentence is what tells them apart. On the
    /// Widgets tab the widget itself is drawn directly above it, over the
    /// person's own habits, which is the same sentence said better — so the
    /// page prints the name and the size and lets the preview do the rest.
    /// The property stays because the gallery still needs it.
    var summary: String {
        switch self {
        case .week: "Your habits for the week. Tap today's slot to log it."
        case .month: "One habit's month. Tap today's dot to log it."
        }
    }

    /// Whether a placed widget of this kind draws **one habit somebody chose**.
    ///
    /// `.month` does: `SelectWeeklyHabitIntent` asks which habit as the widget
    /// is placed, so "which one" is the real variable in it. That is what makes
    /// several Month previews several *different* previews rather than one
    /// picture repeated, and it is the axis the Widgets tab varies over (#237).
    ///
    /// `.week` does not, at any family. It is a `StaticConfiguration` over
    /// whatever habits the week holds; small drops the labels, not the habits,
    /// so there is no per-habit choice in it to preview. #188 would add one — a
    /// habit order held per widget — and until that lands, a second Week-Small
    /// card would be the same rendering twice. This stays `false` rather than
    /// inventing an axis to fill the space.
    var isPerHabit: Bool {
        switch self {
        case .week: false
        case .month: true
        }
    }
}
