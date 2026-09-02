import XCTest

@MainActor
final class WidgetPreviewTouchTests: XCTestCase {
    func testWidgetPreviewReceivesPhysicalTap() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-widget-preview-ui-test")
        app.launch()

        openWidgets(in: app)
        let control = try XCTUnwrap(
            firstVisiblePreviewMark(in: app),
            "expected the deterministic actionable widget-preview fixture"
        )
        XCTAssertTrue(control.isHittable, "the visible preview mark must accept a real touch")

        let before = control.label
        let expected = toggledLabel(before)
        control.tap()

        let reconciled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expected))
            .firstMatch
        XCTAssertTrue(
            reconciled.waitForExistence(timeout: 3),
            "a physical tap did not optimistically toggle and reconcile: \(before)"
        )
    }

    private func openWidgets(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Widgets"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Widgets tab was not available")
        tab.tap()
        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 3))
    }

    private func firstVisiblePreviewMark(in app: XCUIApplication) -> XCUIElement? {
        let marks = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "widget-preview-mark-"
            ))

        guard marks.firstMatch.waitForExistence(timeout: 3) else { return nil }
        // The week now exposes past-day controls too (#508). Keep this
        // physical acknowledgement gate on today's emitting control: its
        // label is the stable semantic distinction, independent of locale's
        // formatted date and of which weekday today happens to be.
        return marks.allElementsBoundByIndex.first {
            $0.isHittable
                && ($0.label.hasSuffix(", due today") || $0.label.hasSuffix(", done"))
        }
    }

    private func toggledLabel(_ label: String) -> String {
        if label.hasSuffix(", due today") {
            return String(label.dropLast("due today".count)) + "done"
        }
        if label.hasSuffix(", done") {
            return String(label.dropLast("done".count)) + "due today"
        }
        XCTFail("unexpected actionable mark label: \(label)")
        return label
    }
}
