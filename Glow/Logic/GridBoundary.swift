import Foundation

/// Where the widget boundary sits among the rows, and how a list operation in
/// the rows the screen *draws* becomes one in the habits it *stores*.
///
/// **The boundary is a row now, and it used to be a decoration** (#621). The
/// hairline saying where an unconfigured large widget stops was an
/// `.overlay(alignment: .bottom)` on whichever habit occupied
/// `largeRowCapacity - 1`, and the empty row's worth of space around it was
/// that same habit's bottom inset. Both belonged to a cell, so both went where
/// the cell went: dragging the eleventh habit above the tenth left the line
/// drawn through a row's name — measured at 460.7pt with the label at 460.8pt,
/// a tenth of a point apart — and the boundary habit's own delete control sat
/// 15.9pt below its label all the time, because the system centres that
/// control in a cell the gap had made half a boundary taller.
///
/// **#515 considered a row and rejected it, and this supersedes that**, so its
/// reasoning is worth stating rather than quietly dropping. It said the list is
/// one `ForEach` carrying `.onMove` and `.onDelete` that index straight into
/// `habits`, and that putting a row between the tenth and eleventh would mean
/// two `ForEach`es — two separate reorderable regions — breaking a drag across
/// the boundary, "a real regression on the one screen where reordering is the
/// point". That is true of two `ForEach`es and it is still true.
///
/// It is not true of one `ForEach` over a list that already contains the
/// boundary. The region stays single, the drag still crosses, and the only new
/// obligation is this type: the offsets `List` reports are positions among the
/// drawn rows, and `habits` has no element at the boundary's position, so every
/// offset is translated before it reaches the store.
enum GridBoundary {
    /// Which drawn position the boundary occupies, or nil when there is none.
    ///
    /// It sits after `capacity` habits — the first row it separates is the
    /// first one an unconfigured large widget does not show. Absent unless
    /// there is a habit below it to explain, which is `showsWidgetBoundary`'s
    /// rule unchanged: never on a fresh install, never a limit nobody reached.
    static func position(habitCount: Int, capacity: Int) -> Int? {
        guard capacity > 0, habitCount > capacity else { return nil }
        return capacity
    }

    /// How many drawn rows there are for `habitCount` habits.
    static func rowCount(habitCount: Int, capacity: Int) -> Int {
        habitCount + (position(habitCount: habitCount, capacity: capacity) == nil ? 0 : 1)
    }

    /// The habit offset a drawn offset stands for.
    ///
    /// The boundary occupies no habit, so everything after it is one place
    /// further along in `habits` than it is on screen.
    ///
    /// **The boundary's own position and the position after it give the same
    /// answer, and that is correct rather than a collision.** As an insertion
    /// point both mean "between the last habit above the line and the first
    /// one below it", and that is one place in `habits`. A drop on either side
    /// of a line that is not data cannot mean two different things.
    static func habitOffset(_ drawn: Int, boundary: Int?) -> Int {
        guard let boundary, drawn > boundary else { return drawn }
        return drawn - 1
    }

    /// A `List` move, in habit terms.
    ///
    /// Both ends are translated in the pre-move list, which is the space
    /// `move(fromOffsets:toOffset:)` is defined in — the destination is an
    /// index into the array as it stands before anything has moved, so
    /// translating it against the same boundary the source was translated
    /// against is the whole of the correspondence.
    static func move(
        source: IndexSet, destination: Int, boundary: Int?
    ) -> (source: IndexSet, destination: Int) {
        (
            IndexSet(source.map { habitOffset($0, boundary: boundary) }),
            habitOffset(destination, boundary: boundary)
        )
    }

    /// Delete offsets, in habit terms.
    ///
    /// The boundary's own offset can never appear here — the row carries
    /// `.deleteDisabled(true)`, so the system does not offer it — and it is
    /// dropped rather than translated if it ever does, because deleting the
    /// habit below the line is not what deleting the line would have meant.
    static func deleteOffsets(_ drawn: IndexSet, boundary: Int?) -> IndexSet {
        IndexSet(
            drawn
                .filter { $0 != boundary }
                .map { habitOffset($0, boundary: boundary) }
        )
    }
}
