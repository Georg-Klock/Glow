import XCTest

/// How the UI tests find an edit-mode row and its reorder handle without
/// reading the system's wording (#555).
///
/// In edit mode the `List` wraps every habit row in chrome of its own, and the
/// two runtimes the app ships to label that chrome differently. On iOS 26 the
/// row is one button labelled `Remove, Edit <name>` and the handle beside it is
/// `Reorder Remove`; on iOS 18 the row stays `Edit <name>` and the handle is
/// `Reorder Edit <name>`, which puts the habit's own name inside the handle. A
/// test matching either string, or counting matches of the row's own label,
/// passes on one runtime and fails on the other — which is what the nightly
/// minimum-iOS lane reported.
///
/// What *is* the same on both, measured from the accessibility tree on an
/// iPhone 16e / iOS 18.5 and an iPhone 17e / iOS 26.5: every habit is one
/// `Cell`, the row button inside it carries the app's own `Edit <name>` label
/// somewhere in whatever the system wrapped it in, and the reorder handle is
/// the one other button in the cell, standing at the cell's trailing edge. So
/// a row is the cell containing the app's label, and its handle is the
/// trailing-most button in that cell.
extension XCUIApplication {
    /// The List cells of every habit row whose app label contains
    /// `labelFragment`, top to bottom.
    func editRows(containing labelFragment: String) -> [XCUIElement] {
        editRowQuery(containing: labelFragment)
            .allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// The single habit row whose app label contains `labelFragment`.
    func editRow(containing labelFragment: String) -> XCUIElement {
        editRowQuery(containing: labelFragment).firstMatch
    }

    /// The system's reorder handle inside `row`: the trailing-most button in
    /// the cell, on both runtimes.
    func reorderHandle(in row: XCUIElement) -> XCUIElement? {
        row.buttons.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }
    }

    private func editRowQuery(containing labelFragment: String) -> XCUIElementQuery {
        cells.containing(NSPredicate(format: "label CONTAINS %@", "Edit \(labelFragment)"))
    }
}
