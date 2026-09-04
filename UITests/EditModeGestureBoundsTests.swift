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

        // **Dropped above the target's centre, slowly, and held before
        // lifting** (#556). Two ways this drag has failed, both measured:
        //
        // Under load the two-argument form, which drags at the default
        // velocity and lifts the moment it arrives, is discarded whole: at a
        // load average around 240 the failing iterations' recordings held no
        // frame with the row lifted, and the default form failed within two
        // and five iterations on iOS 18.5 and 26.5 where the slow, held form
        // moved the row in 30 of 30 on each.
        //
        // Dropped on the target handle's centre, the lifted cell's centre
        // sits 0.6pt past the first row's, and whether the List has registered
        // that crossing by touch-up is a coin flip. When it has not, the List
        // reports the move as ending in the slot *between* rows 1 and 2 —
        // the trace below read `[1]->3` on 1,2,3,4,5, which is that
        // permutation written as row 2's displacement — while the cell
        // visibly lands at the top, and the screen then re-renders to an
        // order matching neither. Seen on the runner (iOS 18.5) and locally
        // on both runtimes. Dropping a third of the way into the target row
        // puts the centre 13pt clear of the boundary.
        let lift = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let land = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        lift.press(forDuration: 1, thenDragTo: land, withVelocity: .slow, thenHoldForDuration: 1)
        let drop = XCTAttachment(screenshot: app.screenshot())
        drop.name = "after the drop"
        drop.lifetime = .keepAlways
        add(drop)

        // What the rows did in the three seconds after the drop, and what the
        // app's `onMove` received (#556): the runner's failure is not the
        // gesture being lost, so the callbacks are the evidence.
        func order() -> String {
            app.editRows(containing: "Pitch Fixture").map { row in
                let label = row.buttons.matching(NSPredicate(
                    format: "label CONTAINS %@", "Edit Pitch Fixture"
                )).firstMatch.label
                return String(label.suffix(1))
            }.joined()
        }
        var timeline: [(Double, String)] = []
        let start = Date()
        let orderDeadline = start.addingTimeInterval(3)
        let trace = app.descendants(matching: .any)["reorder-trace"]
        var calls = "no trace element"
        while Date() < orderDeadline {
            let now = order() + (trace.exists ? " / " + trace.label : "")
            if timeline.last?.1 != now {
                timeline.append((Date().timeIntervalSince(start), now))
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if trace.exists { calls = trace.label }
        let evidence = "order timeline \(timeline.map { "\($0.1)@\(String(format: "%.1f", $0.0))s" }); "
            + "onMove calls: \(calls)"
        print("reorder: \(evidence)")

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
            "rows after the drop were \(app.editRows(containing: "Pitch Fixture").map(\.frame)); \(evidence)"
        )
    }
}
