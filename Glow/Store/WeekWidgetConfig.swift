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
    /// Which blank row this is, counted down the app's own order. Meaningless
    /// on a habit, which has a name of its own.
    var number: Int = 1

    /// **Blank rows are numbered** (#371), and that reverses what this comment
    /// used to say.
    ///
    /// It read that several blank rows appear as several identically-labelled
    /// entries, accepted rather than numbered, because the app itself draws
    /// indistinguishable blank rows and "Blank Row 2" names something that has
    /// no name anywhere else in the product. The objection is still true about
    /// the *product*. It stopped being affordable when the rows did not reach
    /// the picker at all: the store hands one over correctly titled — asserted
    /// in `BlankRowPickerTests` — and it is lost downstream, and an identical
    /// `DisplayRepresentation` on every one of them is the single property that
    /// distinguishes a blank row from a habit in that list.
    ///
    /// So the name exists for the picker rather than for the product. Numbered
    /// from one even when there is only one, because a lone "Blank Row 1" is
    /// odd in a way somebody notices and reports, where a silently missing row
    /// is what this issue already was.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: isSpacer ? "Blank Row \(number)" : "\(name)")
    }
}

struct WeekRowQuery: EntityQuery {
    /// The store to read, or nil for the real one. The same seam
    /// `WeekWidgetStore.rowNames(container:)` carries and for the same reason:
    /// a test that built its own entities would be asserting against a copy of
    /// this query rather than against it. See `BlankRowPickerTests`.
    var container: ModelContainer?

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
        // Numbered here rather than on the entity, because "which blank row is
        // this" is a question about the list and an entity holds only itself.
        // `entities(for:)` resolves through this same call, so a row keeps the
        // number the picker offered it under.
        var blanks = 0
        return try WeekWidgetStore.rowNames(
            container: container ?? GlowStore.makeReadOnlyContainer()
        ).map { row in
            if row.isSpacer { blanks += 1 }
            return WeekRowEntity(
                id: row.id, name: row.name, isSpacer: row.isSpacer, number: blanks
            )
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
    static let description = IntentDescription(
        "Which habits the week shows — and which habit the small size shows."
    )

    /// Nil until someone opens the sheet, and nil is the answer that keeps
    /// today's behaviour — see `WidgetRows.rows`. It is also what every widget
    /// already on a home screen arrives with when this ships, which is what
    /// makes the change invisible to anyone who does not want it.
    /// **Capped per family, by the system** (#366). A medium widget draws four
    /// rows and a large one ten, and the picker now refuses an eleventh rather
    /// than taking it and letting the view cut it silently.
    ///
    /// **The numbers must be literals, and that is the whole problem.**
    /// `IntentCollectionSize(min:max:)` takes `_const Int`, which rejects even
    /// a `static let` bound to a literal — tried, and it fails to compile with
    /// *expect a compile-time constant literal*. So the cap cannot be
    /// `WidgetMetrics`' derived capacity, and this is a second copy of a number
    /// the grid already computes.
    ///
    /// The copy cannot be removed, so it is watched instead:
    /// `WidgetRowLimitTests` reads these two literals back out of this file and
    /// fails if either stops matching the capacity the frame yields. A scan,
    /// for the same reason `WidgetPlacementTests` scans for #254's interpolated
    /// literal — the constraint is on the source, so the source is the only
    /// place to check it.
    ///
    /// `min: 0` keeps the existing meaning of an empty selection: a widget
    /// nobody configured, which draws the app's own list. See `WidgetRows`.
    @Parameter(title: "Habits", size: [
        .systemMedium: IntentCollectionSize(min: 0, max: 4),
        .systemLarge: IntentCollectionSize(min: 0, max: 10),
    ])
    var rows: [WeekRowEntity]?

    /// Which habit the **small** size shows (#322). The small family draws one
    /// habit's month; medium and large draw the week and ignore this the same
    /// way small ignores `rows`. One intent for one kind, so both choices sit
    /// in one sheet — the sheet cannot vary by family. Nil falls back to the
    /// first offered habit, exactly as the month kind's unconfigured widget
    /// always has (`MonthStore.month`).
    ///
    /// The parameter is *added* rather than the intent replaced, deliberately:
    /// keeping the type is what lets a placed medium or large widget keep its
    /// stored `rows` through the merge, since changing a kind's intent type is
    /// what resets its configuration.
    @Parameter(title: "Habit (Small size)")
    var habit: WeeklyHabitEntity?

    /// **The sheet varies by family** (#366), and the comment above used to say
    /// it could not.
    ///
    /// That claim was the load-bearing reason this kind was going to be split
    /// into one per family, which would have re-frozen every placed widget the
    /// way #209 and #322 did. It is false: `When(widgetFamily:)` is iOS 17 and
    /// the per-family `size:` is iOS 18, against a deployment target of 18.0.
    /// Checked in the iOS 26.5 SDK's `AppIntents.swiftinterface`, not from
    /// memory — the same discipline `WidgetsView` records for `WidgetKit`.
    ///
    /// So small offers the habit and nothing else, and the other two offer the
    /// rows and nothing else. Each parameter still exists on every family; what
    /// changes is which one the sheet draws.
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemSmall) {
            Summary { \.$habit }
        } otherwise: {
            Summary { \.$rows }
        }
    }
}

/// How many rows the picker will accept, per family.
///
/// **Not read by the intent** — it cannot be, because `_const` demands a
/// literal there. This is the number the *test* checks the literal against, and
/// the number the rest of the app should ask when it wants to know the cap. It
/// is deliberately not a third opinion: `WidgetRowLimitTests` ties it to
/// `WidgetMetrics` at one end and to the source literal at the other, so all
/// three move together or the suite says which one did not.
enum WidgetRowLimit {
    static let medium = 4
    static let large = 10
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
    ///
    /// **Throws on a failed read** (#282). The caller is an entity query,
    /// which is `async throws` for exactly this: the system's picker shows its
    /// own failure and offers the person another try, where a silent `[]` was
    /// a configuration sheet claiming there is nothing to choose.
    static func rowNames(
        container: ModelContainer? = GlowStore.makeReadOnlyContainer()
    ) throws -> [(id: UUID, name: String, isSpacer: Bool)] {
        guard let container else { throw GlowStore.Unreadable() }
        let context = ModelContext(container)
        return try context.fetch(descriptor).map { ($0.id, $0.name, $0.isSpacer) }
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
    ///
    /// **A failed read is `unavailable`, not an empty week** (#282). The
    /// container failing to open and the fetch failing both used to come back
    /// as `[]`, which the view drew as "No habits yet" — a database failure
    /// rendered as the deletion of every habit. The three outcomes now stay
    /// three all the way to the view. `container` is injectable so a test can
    /// hand this the failure the simulator cannot produce on demand.
    static func rows(
        chosen: [UUID]?, in week: Week,
        container: ModelContainer? = GlowStore.makeReadOnlyContainer()
    ) -> StoreRead<[HabitSnapshot]> {
        guard let container else {
            WidgetTrace.record("week rows: container unavailable")
            return .unavailable
        }
        let context = ModelContext(container)
        // Bounded to the week it draws (#135). A home screen widget reloading
        // every time a completion lands was reading every completion of every
        // habit to fill in seven columns.
        do {
            let all = try Habit.fetchedSnapshots(
                of: context.fetch(descriptor), within: week.dayIDs()
            )
            return StoreRead(read: WidgetRows.rows(from: all, chosen: chosen))
        } catch {
            // Counts and outcomes only, per `WidgetTrace` — never the error's
            // own text, which can carry a path.
            WidgetTrace.record("week rows: fetch failed")
            return .unavailable
        }
    }

    /// One definition, so the picker and the grid cannot offer different rows.
    private static let descriptor = FetchDescriptor<Habit>(
        predicate: Habit.weekly,
        sortBy: [SortDescriptor(\Habit.sortOrder)]
    )
}
