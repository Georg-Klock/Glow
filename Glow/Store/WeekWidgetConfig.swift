import AppIntents
import Foundation
import SwiftData

/// The week widget's configuration: which rows it shows.
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
        // Resolved **in the app's own order**, not in the order asked for.
        //
        // The identifiers do carry an order: #191 measured on an iPhone 14 Pro
        // that WidgetKit hands this array back in the sequence the rows were
        // tapped. The order is deliberately dropped here for the reason
        // `WidgetRows` records — the picker draws checkmarks, so a tap order is
        // invisible while it is being made — and it is dropped *here* as well
        // as there so the sheet's own summary reads in the same order the
        // widget draws. Two surfaces describing one selection differently would
        // be the configuration explaining itself wrongly.
        let wanted = Set(identifiers)
        let matched = all.filter { wanted.contains($0.id) }
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
/// * **No reordering affordance.** No drag handles, no edit mode, no numbered
///   selection — checkmarks only, confirmed on an iPhone 14 Pro as well as in
///   the simulator.
/// * On that simulator the stored choice **did not reach the timeline**:
///   `rows` arrived as an empty array on every render, whatever was selected,
///   and `WeekRowQuery.entities(for:)` was never called in the extension.
///
/// **The device disagreed with the simulator on both counts** (#191). On an
/// iPhone 14 Pro, iOS 26.5.2, three rows selected through the real sheet:
///
/// ```
/// week query resolve 3 id(s) -> 334920AF-…,1E23A402-…,465AF651-…
/// week timeline: rows=3
/// ```
///
/// The query ran in the extension and the parameter arrived non-empty — so the
/// simulator's empty array was the stale-configuration artifact
/// `docs/decisions.md` already records for chronod, not a platform limit. And
/// the array **is ordered by the sequence the rows were tapped**: the row
/// tapped first came back first, putting the app's own first habit second.
///
/// That ordering is deliberately not used. `WidgetRows` and `entities(for:)`
/// both re-impose the app's order, and the reason is on `WidgetRows`: a control
/// that draws checkmarks cannot show an order while it is being chosen, so
/// carrying one out of it is gesture history rather than a decision.
struct SelectWeekLayoutIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habits"
    static let description = IntentDescription("Which habits this widget shows.")

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

    /// The rows this widget draws over `week`, in the app's own order.
    ///
    /// `chosen` is the configured selection, or nil on a widget nobody has
    /// configured. Which rows come out is `WidgetRows`' decision and is tested
    /// there; this reads the store and hands it the answer.
    ///
    /// Every chosen row comes back, uncut. How many of them fit is the
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
