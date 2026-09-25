import XCTest

/// The one interaction the app exists for, on whatever device the run is on
/// (#632).
///
/// The hosted render frames reproduce an iPad's size and size class but not
/// its idiom or the system chrome around the app; this is the half that does.
/// `GLOW_DEVICE_KIND=ipad Tools/test.sh` runs it on an iPad simulator, and the
/// ordinary run runs it on the iPhone, so it is never skipped on either lane
/// and a failure on one is a difference between devices rather than a test
/// that only exists somewhere else.
@MainActor
final class TodaySlotSmokeTests: XCTestCase {
    func testTodaysSlotOnTheFirstRowTakesATap() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-glow-edit-pitch-ui-test=5")
        app.launch()

        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 5))

        // Five daily habits created today, so every row has exactly one mark
        // that is due today: today's column. `SlotVoice` names it "<habit>,
        // <date>, due today", and "done" once it is logged.
        let open = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label ENDSWITH %@",
            "Pitch Fixture 1, ", ", due today"
        )).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3), "no open slot for today on the first row")
        XCTAssertTrue(open.isHittable, "today's slot on the first row is not hittable")

        let before = open.label
        let expected = String(before.dropLast("due today".count)) + "done"
        open.tap()

        let done = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expected))
            .firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "the tap did not log today: \(before)")

        // What the run looked like, and on what. The window size is recorded
        // rather than asserted: whether an iPad presents the app full screen
        // or in a window is the multitasking setting's call, not the app's.
        let window = app.windows.firstMatch.frame
        let device = UIDevice.current
        let facts = XCTAttachment(string: """
            idiom: \(device.userInterfaceIdiom == .pad ? "pad" : "phone")
            model: \(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? device.model)
            system: \(device.systemName) \(device.systemVersion)
            window: \(Int(window.width)) x \(Int(window.height)) pt
            """)
        facts.name = "today-slot-smoke.txt"
        facts.lifetime = .keepAlways
        add(facts)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "today-slot-smoke.png"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
