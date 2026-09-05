import XCTest

/// Correcting history is This Week in another mode (#557), reached from the
/// week already on screen and left on the week it was showing.
@MainActor
final class EditHistoryTests: XCTestCase {
    func testCorrectingAdaptsThisWeekInPlaceAndDoneIsTheExit() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        // Enter from a browsed week, not the current one: the mode has to
        // carry over whatever week This Week was already showing.
        let previous = app.buttons["Previous Week"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        previous.tap()
        XCTAssertTrue(app.navigationBars["Last Week"].waitForExistence(timeout: 3))

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        let correct = app.buttons["Correct History"]
        XCTAssertTrue(correct.waitForExistence(timeout: 3))
        correct.tap()

        // The same screen: no new navigation bar, the week unchanged, the
        // menu gone and Done in its place.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Last Week"].exists)
        XCTAssertFalse(app.navigationBars["Correct History"].exists)
        XCTAssertFalse(app.buttons["More"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

        let cells = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "edit-history-cell-"
        ))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 3))
        // Five deterministic habits by seven days. Every cell exists and is a
        // control regardless of cadence, creation date or relation to today.
        XCTAssertEqual(cells.count, 35)

        let last = cells.element(boundBy: cells.count - 1)
        let before = try XCTUnwrap(last.value as? String)
        XCTAssertTrue(last.isHittable)
        last.tap()

        let expected = before == "Selected" ? "Not selected" : "Selected"
        let changed = NSPredicate(format: "value == %@", expected)
        expectation(for: changed, evaluatedWith: last)
        waitForExpectations(timeout: 3)

        // The pager stays, and in this mode it reaches ahead of today (#543):
        // twice forward from last week is a week browsing cannot show.
        let next = app.buttons["Next Week"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            next.waitForExistence(timeout: 3),
            "no forward chevron on the current week while correcting"
        )
        next.tap()
        XCTAssertTrue(app.navigationBars["Next Week"].waitForExistence(timeout: 3))
        XCTAssertEqual(cells.count, 35, "a week ahead still offers every day")
        XCTAssertTrue(
            app.buttons["Today"].exists,
            "the way home is offered ahead of the current week as it is behind it"
        )

        // Done is the sole exit. Leaving from a week ahead clamps back into
        // browsing's reach, which ends on the current week; the menu returns
        // and the circles go.
        done.tap()
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Next Week"].exists)
        XCTAssertEqual(cells.count, 0)
    }
}
