import Foundation
import Testing
@testable import Glow

/// The boundary as a row, and the offset translation that lets it be one
/// without splitting the list in two (#621).
///
/// #515 rejected a row because it assumed two `ForEach`es. These are the
/// arithmetic that makes one `ForEach` enough — and the reason the screen can
/// keep a single reorderable region while still drawing a line nobody can
/// drag.
@Suite("Widget boundary rows")
struct GridBoundaryTests {
    private let capacity = 10

    @Test("The boundary appears only once a habit is below it")
    func boundaryNeedsARowBeneathIt() {
        #expect(GridBoundary.position(habitCount: 0, capacity: capacity) == nil)
        #expect(GridBoundary.position(habitCount: 9, capacity: capacity) == nil)
        // Exactly full is not over: the tenth habit is the last one the widget
        // shows, and a line under it would explain a limit nobody has reached.
        #expect(GridBoundary.position(habitCount: 10, capacity: capacity) == nil)
        #expect(GridBoundary.position(habitCount: 11, capacity: capacity) == 10)
        #expect(GridBoundary.position(habitCount: 40, capacity: capacity) == 10)
    }

    @Test("A drawn row count is the habits plus the line, when there is one")
    func rowCountCountsTheLine() {
        #expect(GridBoundary.rowCount(habitCount: 10, capacity: capacity) == 10)
        #expect(GridBoundary.rowCount(habitCount: 11, capacity: capacity) == 12)
    }

    @Test("Every drawn offset maps to the habit it draws")
    func drawnOffsetsMapToHabits() {
        let boundary = GridBoundary.position(habitCount: 11, capacity: capacity)
        // Above the line, drawn and stored agree.
        for drawn in 0..<10 {
            #expect(GridBoundary.habitOffset(drawn, boundary: boundary) == drawn)
        }
        // The line itself, and the row after it, are the same insertion point:
        // between habit 9 and habit 10. A drop either side of something that
        // is not data cannot mean two different places.
        #expect(GridBoundary.habitOffset(10, boundary: boundary) == 10)
        #expect(GridBoundary.habitOffset(11, boundary: boundary) == 10)
        #expect(GridBoundary.habitOffset(12, boundary: boundary) == 11)
    }

    @Test("With no boundary, drawn offsets are habit offsets")
    func withoutABoundaryNothingShifts() {
        for drawn in 0..<10 {
            #expect(GridBoundary.habitOffset(drawn, boundary: nil) == drawn)
        }
    }

    /// **The regression #621 is named for.** Eleven habits, drag the last one
    /// up across the line. The habits have to move; the line is not one of
    /// them and cannot be dragged into or out of position.
    @Test("A habit dragged across the line reorders the habits, and only them")
    func draggingAcrossTheLineMovesHabits() {
        let boundary = GridBoundary.position(habitCount: 11, capacity: capacity)
        var habits = Array(0..<11)

        // Drawn row 11 is the habit below the line; drawn row 9 is the one
        // above it. Dropping there puts it inside the widget's ten.
        let move = GridBoundary.move(source: IndexSet([11]), destination: 9, boundary: boundary)
        #expect(move.source == IndexSet([10]))
        #expect(move.destination == 9)

        habits.move(fromOffsets: move.source, toOffset: move.destination)
        #expect(habits == [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 9])
    }

    @Test("A move entirely above the line is untouched")
    func movesAboveTheLineAreUnchanged() {
        let boundary = GridBoundary.position(habitCount: 11, capacity: capacity)
        let move = GridBoundary.move(source: IndexSet([2]), destination: 0, boundary: boundary)
        #expect(move.source == IndexSet([2]))
        #expect(move.destination == 0)
    }

    @Test("Deleting below the line deletes the habit, not its neighbour")
    func deletingBelowTheLineHitsTheRightHabit() {
        let boundary = GridBoundary.position(habitCount: 11, capacity: capacity)
        // Drawn row 11 is habit 10 — the one habit below the line.
        #expect(GridBoundary.deleteOffsets(IndexSet([11]), boundary: boundary) == IndexSet([10]))
        #expect(GridBoundary.deleteOffsets(IndexSet([0]), boundary: boundary) == IndexSet([0]))
    }

    /// The row carries `.deleteDisabled(true)`, so the system never offers
    /// this. If it ever did, deleting the habit below the line is not what
    /// deleting the line would have meant.
    @Test("The line's own offset is dropped rather than translated")
    func theLineItselfIsNeverDeleted() {
        let boundary = GridBoundary.position(habitCount: 11, capacity: capacity)
        #expect(GridBoundary.deleteOffsets(IndexSet([10]), boundary: boundary).isEmpty)
        #expect(
            GridBoundary.deleteOffsets(IndexSet([10, 11]), boundary: boundary) == IndexSet([10])
        )
    }

    /// Every drawn offset resolves to a habit that exists, at every count
    /// either side of the boundary appearing. A translation that runs off the
    /// end of `habits` is an index-out-of-range in `deleteAt`.
    @Test("No drawn offset ever resolves past the end of the habits")
    func translationStaysInBounds() {
        for count in 0...25 {
            let boundary = GridBoundary.position(habitCount: count, capacity: capacity)
            let rows = GridBoundary.rowCount(habitCount: count, capacity: capacity)
            for drawn in 0..<rows where drawn != boundary {
                let habit = GridBoundary.habitOffset(drawn, boundary: boundary)
                #expect(habit >= 0 && habit < count, "count \(count), drawn \(drawn)")
            }
        }
    }
}
