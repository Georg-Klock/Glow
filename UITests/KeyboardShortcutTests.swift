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

        // Browsing stops at the current week, so ⌘→ there has no button to
        // press and changes nothing; back first, then forward.
        app.typeKey(.leftArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Last Week"].waitForExistence(timeout: 3))

        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 3))

        // ⌘→ on the current week: no forward chevron, so no forward key.
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
