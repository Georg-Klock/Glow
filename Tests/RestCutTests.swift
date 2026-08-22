import Foundation
import Testing
@testable import Glow

/// The rest day's line starts and stops on a habit, and nowhere else.
///
/// Every case here is about an end of the line rather than about the middle:
/// the middle was never in doubt, and the bugs this replaces were both at the
/// ends — the line overshooting into the header's air above the first row, and
/// running past the last habit into the list's bottom.
@Suite("Rest cut")
struct RestCutTests {
    private func rows(_ kinds: [Bool]) -> [HabitSnapshot] {
        kinds.map { HabitSnapshot.fixture(isSpacer: $0) }
    }

    @Test("Both ends land on a habit, never on a blank row")
    func endsOnHabits() {
        // spacer, habit, habit, spacer
        let cut = RestCut.rows(rows([true, false, false, true]), capacity: 4)
        #expect(cut == 1...2)
    }

    @Test("A blank row between two habits still draws its segment")
    func spacerInTheMiddleIsInsideTheCut() {
        let cut = RestCut.rows(rows([false, true, false]), capacity: 3)
        #expect(cut == 0...2)
        // The point of the range rather than a per-row predicate: the middle
        // row is a spacer and is still in it.
        #expect(cut?.contains(1) == true)
    }

    @Test("A leading blank row is above the line")
    func leadingSpacerExcluded() {
        #expect(RestCut.rows(rows([true, true, false]), capacity: 3) == 2...2)
    }

    @Test("A trailing blank row is below the line")
    func trailingSpacerExcluded() {
        #expect(RestCut.rows(rows([false, true, true]), capacity: 3) == 0...0)
    }

    @Test("One habit draws one row-tall segment")
    func singleHabit() {
        #expect(RestCut.rows(rows([false]), capacity: 1) == 0...0)
    }

    @Test("Nothing but blank rows draws nothing")
    func allSpacers() {
        #expect(RestCut.rows(rows([true, true, true]), capacity: 3) == nil)
    }

    @Test("An empty grid draws nothing")
    func empty() {
        #expect(RestCut.rows([], capacity: 11) == nil)
    }

    @Test("The line stops where the surface stops")
    func capacityCutsIt() {
        // Five habits, three rows shown: the line ends on the third, not on the
        // fifth. This is the widget's hard cut, and in the app it is the same
        // number, so the cut ends on the boundary hairline.
        #expect(RestCut.rows(rows([false, false, false, false, false]), capacity: 3) == 0...2)
    }

    @Test("A habit past the capacity neither extends the line nor starts one")
    func habitBelowCapacityIgnored() {
        // The only habit is out of view, so there is no line at all — rather
        // than one anchored to a row nothing draws.
        #expect(RestCut.rows(rows([true, true, false]), capacity: 2) == nil)
    }

    @Test("A surface showing no rows draws nothing")
    func zeroCapacity() {
        #expect(RestCut.rows(rows([false, false]), capacity: 0) == nil)
    }

    @Test("A negative capacity is no rows, not a crash")
    func negativeCapacity() {
        // Reachable by arithmetic rather than by intent: `rowCapacity` divides
        // an available height that a small enough widget makes negative.
        #expect(RestCut.rows(rows([false, false]), capacity: -3) == nil)
    }

    @Test("The column's centre is the same formula the track is divided by")
    func xIsTheColumnCentre() {
        let track: CGFloat = 194
        let slot = SlotLayout.dailySlot(trackWidth: track)
        let gap = SlotLayout.gap(trackWidth: track)

        // Monday's centre is half a slot in; Sunday's is half a slot from the
        // track's far end. Asserting the last column against the track width
        // rather than against the same multiplication is what would catch an
        // off-by-one in the index.
        #expect(RestCut.x(restIndex: 0, trackWidth: track, labelWidth: 0, labelGap: 0)
            .isApproximately(slot / 2))
        #expect(RestCut.x(restIndex: 6, trackWidth: track, labelWidth: 0, labelGap: 0)
            .isApproximately(track - slot / 2))
        #expect(RestCut.x(restIndex: 1, trackWidth: track, labelWidth: 0, labelGap: 0)
            .isApproximately(slot + gap + slot / 2))
    }

    @Test("The label column shifts the line without changing the track")
    func xIncludesTheLabelColumn() {
        let track: CGFloat = 194
        let bare = RestCut.x(restIndex: 3, trackWidth: track, labelWidth: 0, labelGap: 0)
        let labelled = RestCut.x(restIndex: 3, trackWidth: track, labelWidth: 98, labelGap: 8)
        #expect((labelled - bare).isApproximately(106))
    }
}

private extension CGFloat {
    func isApproximately(_ other: CGFloat, within tolerance: CGFloat = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
