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
        // trailing inset too far right (#548). The same expectation on every
        // runtime: iOS 26 floats the action 10pt inside the List's bound and
        // iOS 18 runs it out to the bound, and the List's bound is placed so
        // the action lands on the track either way (#555).
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

        // Rows and handles by structure, not by the system's labels (#555);
        // see `EditModeRows.swift`.
        XCTAssertTrue(app.editRow(containing: "Pitch Fixture").waitForExistence(timeout: 3))
        let rows = app.editRows(containing: "Pitch Fixture")
        XCTAssertEqual(rows.count, 5, "edit rows were \(rows.map(\.frame))")
        let source = try XCTUnwrap(app.reorderHandle(in: rows[2]))
        let target = try XCTUnwrap(app.reorderHandle(in: rows[0]))

        // Evidence for the next intermittent failure (#556): which element is
        // about to be dragged, where, and what the screen held at the drop.
        let handles = rows.compactMap { app.reorderHandle(in: $0) }
        print("reorder: \(handles.count) handles at \(handles.map(\.frame)); "
            + "dragging \(source.frame) to \(target.frame)")

        // **Slow, and held before lifting** (#556). The two-argument form
        // drags at the default velocity and lifts the moment it arrives, and
        // under load the list can discard that gesture whole: locally, at a
        // load average around 240, the failing iterations' own screen
        // recordings held not one frame with the row lifted, and the default
        // form failed within two and five iterations on iOS 18.5 and 26.5
        // where this form moved the row in 30 of 30 on each. That is one of
        // the two ways this test has failed; the other was the app's, on the
        // runner, where the drag landed and a second `onMove` was applied to
        // a stale query array — see `HabitStore.reorder`.
        source.press(
            forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 1
        )
        let drop = XCTAttachment(screenshot: app.screenshot())
        drop.name = "after the drop"
        drop.lifetime = .keepAlways
        add(drop)

        // A List commits a reorder on an animation, so give the rows the same
        // moment everything else in this file waits for — and no more than
        // that: #554 showed that three seconds after the drop the order was
        // still unchanged on the runner, so waiting here is only the fair
        // reading, not the fix.
        let moved = app.editRow(containing: "Pitch Fixture 3")
        let topOfRows = { app.editRows(containing: "Pitch Fixture").first?.frame.minY }
        let deadline = Date().addingTimeInterval(3)
        while moved.frame.minY != topOfRows(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(
            moved.frame.minY,
            topOfRows(),
            "rows after the drop were \(app.editRows(containing: "Pitch Fixture").map(\.frame))"
        )
    }
}
