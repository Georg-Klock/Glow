import XCTest

@MainActor
final class EditModeGestureBoundsTests: XCTestCase {
    func testNativeSwipeActionsStopAtTheDayTrack() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Pitch Fixture 3"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()

        let delete = app.buttons.matching(NSPredicate(
            format: "label == %@", "Delete"
        )).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))

        // The app grid has a fixed 20pt panel margin, then scales the widget's
        // 14pt trailing inset from its 338pt design width. A native swipe
        // action used to end at the panel instead of at the track, one scaled
        // trailing inset too far right (#548).
        let scale = (app.frame.width - 40) / 338
        let expectedTrackEnd = app.frame.width - 20 - 14 * scale
        XCTAssertEqual(delete.frame.maxX, expectedTrackEnd, accuracy: 1)
    }

    func testNativeReorderStillMovesTheRow() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))

        let handles = app.buttons.matching(NSPredicate(
            format: "label == %@", "Reorder Remove"
        ))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 3))
        let handle = handles.element(boundBy: 2)
        handle.press(forDuration: 1, thenDragTo: handles.element(boundBy: 0))

        let labels = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Pitch Fixture"
        )).allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(labels.first?.label, "Pitch Fixture 3")
    }
}
