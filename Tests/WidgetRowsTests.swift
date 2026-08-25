import Foundation
import Testing
@testable import Glow

/// Which rows a configured week widget draws (#188).
///
/// The half of this feature that is a decision rather than a fetch or a
/// layout. Every case below is about a configuration outliving the store it
/// was made against, because that is the only way this function can be wrong:
/// the happy path is a lookup.
@Suite("Widget rows")
struct WidgetRowsTests {
    private func row(_ name: String, isSpacer: Bool = false) -> HabitSnapshot {
        HabitSnapshot.fixture(name: name, isSpacer: isSpacer)
    }

    /// The app's own order: two habits, a blank row, two more. The shape #123
    /// seeds and #172 found the cost of.
    private func appOrder() -> [HabitSnapshot] {
        [row("Workout"), row("Stretch"), row("", isSpacer: true), row("Study"), row("Read")]
    }

    @Test("An unconfigured widget keeps the app's order, unchanged")
    func unconfiguredIsUntouched() {
        // The requirement this feature is allowed to ship under: every widget
        // already on a home screen arrives here with nil the first time this
        // runs, and none of them may move.
        let all = appOrder()
        #expect(WidgetRows.rows(from: all, chosen: nil) == all)
    }

    @Test("An empty choice is the same as no choice")
    func emptyIsUnconfigured() {
        // A picker that has been opened and left empty is not a request for an
        // empty widget. There is no way to ask for one, and a blank home screen
        // panel would be indistinguishable from the store having failed to open.
        let all = appOrder()
        #expect(WidgetRows.rows(from: all, chosen: []) == all)
    }

    @Test("The app's order is the drawn order, whatever order was chosen in")
    func orderIsTheApps() {
        // **The selection does carry an order and it is deliberately dropped**
        // (#191). Measured on an iPhone 14 Pro: WidgetKit hands the array back
        // in the sequence the rows were tapped, so this could have been the
        // configuration's order. It is not, because the system's picker draws
        // checkmarks — an order chosen there is invisible while it is being
        // chosen and unfixable afterwards without clearing every row. See
        // `WidgetRows`.
        let all = appOrder()
        let chosen = [all[4].id, all[0].id, all[3].id]
        #expect(WidgetRows.rows(from: all, chosen: chosen).map(\.name) == ["Workout", "Study", "Read"])
    }

    @Test("The same selection draws the same rows however it was tapped")
    func tapOrderIsNotRemembered() {
        // The property the one above asserts by example, asserted as a
        // property: this is what stops a widget quietly reordering itself by
        // gesture history.
        let all = appOrder()
        let ids = [all[4].id, all[0].id, all[3].id]
        let orderings = [
            [ids[0], ids[1], ids[2]],
            [ids[2], ids[1], ids[0]],
            [ids[1], ids[2], ids[0]],
        ]
        let drawn = orderings.map { WidgetRows.rows(from: all, chosen: $0).map(\.name) }
        #expect(Set(drawn).count == 1, "the tap order changed what was drawn: \(drawn)")
    }

    @Test("A blank row is chosen and placed like any other row")
    func spacerIsJustARow() {
        // The whole reason someone opens this picker (#172): a gap where they
        // want one, rather than where the app's own clustering put it.
        let all = appOrder()
        let spacer = all[2]
        let chosen = [all[3].id, spacer.id, all[0].id]
        let rows = WidgetRows.rows(from: all, chosen: chosen)
        // The app's order, so the blank row sits where the app has it —
        // between Workout and Study — rather than where it was tapped.
        #expect(rows.map(\.name) == ["Workout", "", "Study"])
        #expect(rows.map(\.isSpacer) == [false, true, false])
    }

    @Test("A row that no longer exists is dropped, not held as a gap")
    func deletedRowsFallOut() {
        let all = appOrder()
        let chosen = [all[0].id, UUID(), all[3].id]
        // A deleted habit is not a blank row. Someone who wants a gap has a
        // real one to pick, and leaving a hole would make a deletion look like
        // a layout choice.
        #expect(WidgetRows.rows(from: all, chosen: chosen).map(\.name) == ["Workout", "Study"])
    }

    @Test("A repeated choice appears once")
    func duplicatesCollapse() {
        // The view's `ForEach` is keyed by `id` and the rest day's cut is a
        // range of row indices into this list, so a duplicated identity would
        // be two kinds of wrong at once. Whether the system's picker can even
        // produce one is unconfirmed — this makes it not matter.
        let all = appOrder()
        let chosen = [all[0].id, all[3].id, all[0].id]
        #expect(WidgetRows.rows(from: all, chosen: chosen).map(\.name) == ["Workout", "Study"])
    }

    @Test("Two blank rows are two rows, because they are two habits")
    func spacersAreIndependent() {
        // Blank rows are indistinguishable in the picker and distinct in the
        // store — each has its own id. Picking both is picking two gaps, and
        // the duplicate rule must not fold them together.
        let all = [row("Workout"), row("", isSpacer: true), row("", isSpacer: true), row("Study")]
        let chosen = [all[1].id, all[2].id]
        #expect(WidgetRows.rows(from: all, chosen: chosen).count == 2)
    }

    @Test("Nothing comes out that was not in the store's list")
    func nothingIsInvented() {
        let all = appOrder()
        let known = Set(all.map(\.id))
        let rows = WidgetRows.rows(from: all, chosen: [UUID(), all[1].id, UUID()])
        #expect(rows.allSatisfy { known.contains($0.id) })
        #expect(rows.count == 1)
    }

    @Test("A choice of nothing that still exists draws nothing")
    func everythingDeletedIsEmpty() {
        // Distinct from the unconfigured case on purpose: this widget was
        // configured, and every row it was configured with is gone. It shows
        // the empty state rather than silently becoming the app's first rows,
        // which is the same rule the month widget follows for its one deleted
        // habit — see `MonthStore.month(of:containing:)`.
        #expect(WidgetRows.rows(from: appOrder(), chosen: [UUID()]).isEmpty)
    }

    @Test("No rows at all is no rows, configured or not")
    func emptyStore() {
        #expect(WidgetRows.rows(from: [], chosen: nil).isEmpty)
        #expect(WidgetRows.rows(from: [], chosen: [UUID()]).isEmpty)
    }
}
