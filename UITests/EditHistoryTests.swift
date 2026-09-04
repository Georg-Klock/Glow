import XCTest

@MainActor
final class EditHistoryTests: XCTestCase {
    func testEveryDayCircleWritesImmediatelyAndDoneIsTheExit() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()

        let openHistory = app.buttons["Edit History"]
        XCTAssertTrue(openHistory.waitForExistence(timeout: 3))
        openHistory.tap()

        XCTAssertTrue(app.navigationBars["Edit History"].waitForExistence(timeout: 3))
        let done = app.buttons["Done"]
        XCTAssertTrue(done.exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists)

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

        done.tap()
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))
    }
}
