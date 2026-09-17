import Foundation
import Testing
@testable import Glow

/// #179: a test process should not be running the app.
///
/// The app's views observe preferences through `@AppStorage` — `WeeklyGridView`
/// the week's first day, every `HabitRowView` the rest day, `GlowImageCache`
/// the glow level — and the tests write exactly those keys through
/// `TestPreferences`. Swift Testing runs off the main thread, so every write
/// published into a live SwiftUI hierarchy from a background thread. That is
/// undefined behaviour, and it surfaced as the host dying on an unwrap in
/// unrelated code, failing a different innocent test each time, twice on one
/// CI commit that contained no Swift at all.
///
/// Measured through the result bundle's own runtime-warning count, which #138
/// records: **106 in one `GlowTests` run before, 0 after, twice repeated** —
/// against 0 in `GlowRenderTests`, which hosts no interface and never had the
/// problem.
@Suite("Test host")
struct TestHostTests {
    @Test("The process knows it is hosting tests")
    func detectsItself() {
        // Everything below rests on this, and it is one environment read that
        // a future Xcode could rename.
        #expect(GlowSettings.isRunningTests)
    }

    @Test("The app's own store is not opened by the test host")
    func hostOpensNoStore() {
        // Two reasons, and the second is the one that bites: a test host that
        // opens the real store races the tests that open their own, and it was
        // seen taking the host down when the migration suite left a
        // deliberately malformed file where it looked.
        //
        // Asserted through the flag rather than by reaching for the container,
        // because `GlowApp` is a `struct App` whose `init` is the thing under
        // discussion and instantiating one here would run it.
        #expect(GlowSettings.isRunningTests, "the host would otherwise open the app's store")
    }

    @Test("Writing a preference reaches no observer")
    func preferenceWritesArePrivate() {
        // The write path the crashes were attributed to, exercised the way the
        // suite exercises it. If the host ever draws the app again this still
        // passes — it is the runtime-warning count that would move — so the
        // source scan below is the one that guards the property.
        TestPreferences.withWeek(firstWeekday: WeekPreferences.sunday, restDay: 7) {
            #expect(WeekPreferences.restDay == 7)
            #expect(WeekPreferences.firstWeekday == WeekPreferences.sunday)
        }
    }

    @Test("The app's scene is skipped under tests")
    func sceneIsInert() throws {
        // The property that actually matters, and it cannot be observed from
        // inside the process: a SwiftUI `Scene` is not inspectable, and by the
        // time a test runs the hierarchy either exists or does not. So this
        // reads the source, the way #141 and #168 do for claims a test cannot
        // watch.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Glow/App/GlowApp.swift"),
            encoding: .utf8
        )
        #expect(source.contains("GlowSettings.isRunningTests"), "GlowApp no longer checks")
        // The guard has to come before the container branch, or the host draws
        // the app anyway.
        let guardAt = try #require(source.range(of: "if GlowSettings.isRunningTests"))
        let rootView = try #require(source.range(of: "RootTabView()"))
        #expect(guardAt.lowerBound < rootView.lowerBound)
    }

    @Test("A launch does its four things in the one order that is correct")
    func launchWorkIsOrderedAndInert() throws {
        // Four steps, and the order is not arrangement: the middle two each
        // delete rows a widget draws, and the reload is last so that it reloads
        // against the settled answer.
        //
        //  1. The container opens, or nothing else happens.
        //  2. `migrateDailyHabitsOut` (#239) — in `init`, on that container.
        //  3. `purgeRetiredDebugData` (#628) — in `init`, on the same
        //     container, after the sweep. It deletes the rows the removed demo
        //     invented and the keys the removed override wrote.
        //  4. `WidgetRefresh.invalidate()` (#236) — a `.task` on `body`'s
        //     container branch, so strictly after all of the above.
        //
        // The first launch step used to be clearing the debug day override
        // (#204). The override is gone, so there is nothing to clear before the
        // store opens.
        //
        // Steps 2 to 4 must also be unreachable from the test host, which
        // shares `init`. All are, without a second check: the sweep and the
        // purge are behind `if let container = attempt.container` and that
        // binding is `nil` under tests, and the reload is past `body`'s
        // `isRunningTests` guard as well. A migration or a reload running in
        // the test process is the process-wide store leak #105, #168, #175 and
        // #179 closed.
        //
        // Read from source for `sceneIsInert`'s reason: a `Scene` is not
        // inspectable, and by the time a test runs the hierarchy either exists
        // or does not.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Glow/App/GlowApp.swift"),
            encoding: .utf8
        )

        let sweep = try #require(
            source.range(of: "Self.migrateDailyHabitsOut(in: container)"),
            "the launch sweep is gone"
        )
        let purge = try #require(
            source.range(of: "Self.purgeRetiredDebugData(in: container)"),
            "the retired debug data purge is gone"
        )
        let reload = try #require(
            source.range(of: ".task { WidgetRefresh.invalidate() }"),
            "the unconditional launch reload is gone"
        )
        let bodyAt = try #require(source.range(of: "var body: some Scene"))
        let rootView = try #require(source.range(of: "RootTabView()"))

        #expect(sweep.lowerBound < purge.lowerBound)
        // 2 and 3 in `init`, 4 in the container branch of `body`.
        #expect(purge.lowerBound < bodyAt.lowerBound, "the purge left init")
        #expect(bodyAt.lowerBound < reload.lowerBound, "the reload moved into init")
        #expect(rootView.lowerBound < reload.lowerBound, "the reload left the branch")

        // Both are gated on a container that the test host is never given.
        let gate = try #require(source.range(of: "if let container = attempt.container {"))
        #expect(gate.lowerBound < sweep.lowerBound)
        let gateEnd = try #require(source[gate.upperBound...].range(of: "\n        }"))
        #expect(purge.upperBound < gateEnd.lowerBound, "the purge left the container gate")
    }
}
