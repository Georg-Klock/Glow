import AppIntents
import Foundation
import SwiftData

/// The week widget's configuration: which rows it shows, and in what order.
///
/// In the shared sources for the same load-bearing reason as
/// `MonthWidgetConfig`: the system consolidates AppIntents metadata under the
/// app, and an intent defined only in the extension configures but never
/// resolves — the stored choice arrives unresolved on every render, the entity
/// query is never consulted, and the widget silently falls back to the default.
/// Compiled into both targets, the choice round-trips.
///
/// A separate entity from `WeeklyHabitEntity`, and not because a second one is
/// nicer: the entity type is what binds a picker to its query, and the two
/// pickers offer different sets. This one offers the week-shaped rows — every
/// habit the grid draws **and the blank rows**, which the month widget's picker
/// excludes because a blank row holds a position in a list and means nothing in
/// a month. A blank row is the whole reason someone opens this picker: #172's
/// finding was that the app's own clustering puts a gap where a medium widget's
/// cut falls, and the answer is to let a widget place its own gap rather than
/// to reorder the app.
struct WeekRowEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Row"
    static let defaultQuery = WeekRowQuery()

    let id: UUID
    let name: String
    let isSpacer: Bool

    /// Several blank rows appear as several identically-labelled entries, and
    /// that is accepted rather than numbered. It is what the app itself draws —
    /// indistinguishable blank rows — and a "Blank Row 2" would be a name for
    /// something that has no name anywhere else in the product.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: isSpacer ? "Blank Row" : "\(name)")
    }
}

struct WeekRowQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WeekRowEntity] {
        let all = try await suggestedEntities()
        // Resolved **in the order asked for**, not in the store's order. This
        // query is the only place the configuration's order can survive: the
        // system hands back an array, and returning it sorted by `sortOrder`
        // would silently undo any ordering the identifiers carry. Whether they
        // carry one is the open question — see `SelectWeekLayoutIntent`. This
        // side of it is correct either way, and costs nothing.
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matched = identifiers.compactMap { byID[$0] }
        // Resolution is the step that silently failed under extension-only
        // metadata, so it stays traced for the device check. Ids only — see
        // `WidgetTrace`.
        WidgetTrace.record(
            WidgetTrace.resolution("week query", asked: identifiers, got: matched.map(\.id))
        )
        return matched
    }

    func suggestedEntities() async throws -> [WeekRowEntity] {
        WeekWidgetStore.rowNames().map {
            WeekRowEntity(id: $0.id, name: $0.name, isSpacer: $0.isSpacer)
        }
    }

    // No `defaultResult()`, same as the month widget: an unconfigured
    // widget is answered by the provider, which keeps the app's own order. The
    // query does not guess on the system's behalf.
}

/// Which rows this widget shows.
///
/// **What the system's own sheet turned out to offer**, measured in the
/// simulator on 2026-08-22 rather than assumed:
///
/// * A **multi-select checklist**, in this query's suggested order, with a
///   confirm button. Selection persists and the sheet summarises it
///   ("Charlie and Bla…", or "All").
/// * **No reordering.** No drag handles, no edit mode, and the summary reads
///   back in the suggested order rather than the order the rows were tapped.
///   So the "and in what order" half of #188 is *not* something this control
///   can express today; the fallback the issue names — an in-app screen
///   reached through `widgetURL` — is what would express it.
/// * On that simulator the stored choice **did not reach the timeline**:
///   `rows` arrived as an empty array on every render, whatever was selected,
///   and `WeekRowQuery.entities(for:)` was never called in the extension. That
///   is the same class of failure `MonthWidgetConfig` records for the
///   single-entity case, which only a device could settle. Empty falls back to
///   the app's order (`WidgetRows.rows`), so the widget kept drawing exactly
///   what it draws today — which is why this is shippable while the question
///   is open. See #191, which carries the trace and what to check on hardware.
struct SelectWeekLayoutIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habits"
    static let description = IntentDescription("Which habits this widget shows, and in what order.")

    /// Nil until someone opens the sheet, and nil is the answer that keeps
    /// today's behaviour — see `WidgetRows.rows`. It is also what every widget
    /// already on a home screen arrives with when this ships, which is what
    /// makes the change invisible to anyone who does not want it.
    @Parameter(title: "Habits")
    var rows: [WeekRowEntity]?
}

/// One query shared by the week widget's provider and its entity query, so the
/// picker and the render cannot disagree about which rows exist.
///
/// Two readings of it, the shape #135 settled: the picker lists names and reads
/// no completions at all, the provider draws one week and reads that week.
enum WeekWidgetStore {
    /// Every week-shaped row, in the app's own order, with no history read.
    ///
    /// Blank rows are included and say so. They are rows on this surface —
    /// they occupy a slot on the home screen exactly as a habit does — which is
    /// the same reason `WeeklyGridView` counts them against the widget's
    /// capacity.
    static func rowNames() -> [(id: UUID, name: String, isSpacer: Bool)] {
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        return (try? context.fetch(descriptor))?.map { ($0.id, $0.name, $0.isSpacer) } ?? []
    }

    /// The rows this widget draws over `week`, in the order it draws them.
    ///
    /// `chosen` is the configured order, or nil on a widget nobody has
    /// configured. Which rows come out is `WidgetRows`' decision and is tested
    /// there; this reads the store and hands it the answer.
    ///
    /// The whole chosen order comes back, uncut. How many of them fit is the
    /// view's question, because only the view has measured a frame — see
    /// `WidgetRows`.
    static func rows(chosen: [UUID]?, in week: Week) -> [HabitSnapshot] {
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        // Bounded to the week it draws (#135). A home screen widget reloading
        // every time a completion lands was reading every completion of every
        // habit to fill in seven columns.
        let all = Habit.snapshots(
            of: (try? context.fetch(descriptor)) ?? [], within: week.dayIDs()
        )
        return WidgetRows.rows(from: all, chosen: chosen)
    }

    /// One definition, so the picker and the grid cannot offer different rows.
    private static let descriptor = FetchDescriptor<Habit>(
        predicate: Habit.weekly,
        sortBy: [SortDescriptor(\Habit.sortOrder)]
    )
}
