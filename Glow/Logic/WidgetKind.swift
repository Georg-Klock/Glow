import Foundation
import WidgetKit

/// The kind string of every widget this bundle ships.
///
/// **A kind is a persistent identifier, not a label.** WidgetKit stores it
/// against every widget a person has placed, so renaming one orphans their
/// widget — it stops being the thing they configured. That is why these live
/// here as a fixed list rather than being spelled out at each widget's own
/// configuration and again wherever a reload is asked for.
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
/// **`GlowMonthSmall` was here and is gone too** (#322). Week and Month
/// collapsed into this one kind: three sizes, one content type per size —
/// Small draws one habit's month, Medium and Large draw the week. The month
/// kind's placements freeze the way #209's did, and that was accepted on the
/// issue; see SPEC.md's widgets section for why the arithmetic, not the
/// mechanism, is what made it acceptable.
enum WidgetKind: String, CaseIterable, Sendable {
    case week = "GlowWidget"

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
        // Medium and large, each independently placeable. **Small was here and
        // is gone** (PR #277): it drew the same habits with the labels dropped,
        // so it said how much of the week was done without saying what of —
        // and #237 had already found it had no per-habit axis to vary a
        // second preview over. A size that can only be read by someone who
        // already knows the row order is not a size worth offering.
        //
        // Removing a family is not removing a kind (#209): `GlowWidget` still
        // serves the same kind string, so a placed medium or large is
        // untouched, and a placed *small* stops being served. `WidgetCatalog`
        // already drops a family a kind does not support — see
        // `unsupportedFamilyIsIgnored` — so the Widgets tab says nothing about
        // one rather than showing a row it cannot explain.
        //
        // **Small is back, with a different meaning** (#322). #277's objection
        // was to a small *week*: rows with the labels dropped, readable only
        // by someone who knew their own order. At small this kind draws one
        // habit's month instead — content that names its habit — so the
        // objection does not transfer. One kind, three sizes, one content
        // type per size.
        case .week: [.systemSmall, .systemMedium, .systemLarge]
        }
    }

    /// What the widget gallery calls this kind, without the app's name in
    /// front of it. The gallery itself shows `galleryName`, which puts the app
    /// in front; inside the app the prefix would only repeat the app you are
    /// already in.
    var displayName: String {
        switch self {
        case .week: "This Week"
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
        case .week: "Your habits for the week — or one habit's month at the small size. Tap today to log it."
        }
    }

    /// Whether this kind at this family draws **one habit somebody chose**.
    ///
    /// A property of the family now, not of the kind (#322): the one kind
    /// carries both content types, and the per-habit axis — the thing that
    /// makes several previews several *different* previews rather than one
    /// picture repeated (#237) — exists exactly where the month content is,
    /// at small. Medium and large stay the whole week: their configuration is
    /// which rows show (#188), which is not an axis a preview can vary over.
    func previewsOneHabit(at family: WidgetFamily) -> Bool {
        family == .systemSmall
    }
}
