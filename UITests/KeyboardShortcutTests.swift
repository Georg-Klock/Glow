import XCTest

/// The This Week shortcuts are the toolbar's own buttons (#641): ⌘← and ⌘→
/// are the pager's chevrons, ⌘T is Today and ⌘N is the More menu's New
/// Habit. What only a delivered key event proves is that the shortcut reaches
/// the button — a still render cannot, and `accessibilityActivate()` bypasses
/// the keyboard entirely.
@MainActor
final class KeyboardShortcutTests: XCTestCase {
    func testCommandArrowsPageTheWeekAndCommandTReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))

        // The simulator's first synthesized key event after launch is not
        // reliably delivered: measured, the same opening ⌘← paged the week
        // on one run and did nothing on the next, while every later key in
        // both runs landed. So the first key sent is one whose right answer
        // is "nothing happens" either way — ⌘→ on the current week, where
        // browsing has no forward chevron and so no forward key.
        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))

        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Last Week"].waitForExistence(timeout: 3))

        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))

        // Delivered this time, and still nothing: no forward chevron on the
        // current week, so no forward key.
        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertFalse(app.navigationBars["Next Week"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.navigationBars["This Week"].exists)

        // Two back, then Today in one step.
        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Last Week"].waitForExistence(timeout: 3))
        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertFalse(app.navigationBars["Last Week"].waitForExistence(timeout: 1))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))

        // ⌘N opens the same editor the menu's New Habit does, without the
        // menu being opened first.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["New Habit"].waitForExistence(timeout: 3))
    }
}
