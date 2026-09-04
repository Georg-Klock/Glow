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
        // Slowly, and hold before lifting. The default two-argument form drags
        // as fast as the device will accept, and a `List` that never tracks the
        // row drops it back where it started — a pass or a fail depending on
        // how busy the machine is, which is not what this test is asking.
        handle.press(
            forDuration: 1,
            thenDragTo: handles.element(boundBy: 0),
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )

        // Then wait for the move to commit, rather than reading the order the
        // instant the drag returns. Every other check in this file waits; this
        // one used to read straight through the reorder animation, and a row
        // still mid-flight reads as the old order — exactly the "Pitch Fixture
        // 1 is not Pitch Fixture 3" seen on CI at f236216 (#551), on a commit
        // that touched only widget sizing and cannot have moved this row.
        let deadline = Date().addingTimeInterval(3)
        var top = topPitchFixtureLabel(app)
        while top != "Pitch Fixture 3", Date() < deadline {
            usleep(100_000)
            top = topPitchFixtureLabel(app)
        }
        XCTAssertEqual(top, "Pitch Fixture 3")
    }

    /// The topmost fixture row's label, by on-screen position.
    private func topPitchFixtureLabel(_ app: XCUIApplication) -> String? {
        app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Pitch Fixture"
        )).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .first?.label
    }
}
