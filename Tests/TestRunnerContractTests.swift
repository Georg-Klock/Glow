import Foundation
import Testing
@testable import Glow

/// #168: a test must not be able to poison the machine it ran on.
///
/// `WeekPreferences.restDay` lives in `UserDefaults`, one value for the whole
/// store — and a `UserDefaults` suite **outlives the process**. `TestPreferences`
/// restores it correctly on the way out; a process that dies does not get a way
/// out. A crash, a cancelled run, or a hard trap like the SwiftData
/// precondition #145 is about leaves the value written to disk, and every later
/// run on that simulator inherits it.
///
/// Found as `weekRestDay = 7` on the simulator `Tools/test.sh` picks: 42 tests
/// red locally while the same commit was green on CI and on a second simulator.
@Suite("Test isolation")
struct TestIsolationTests {
    @Test("Tests do not read or write the app's real defaults")
    func storeIsPrivate() {
        // The whole guarantee, in one assertion: if this suite name is ever the
        // App Group's own again, a dying test can poison the next run.
        let group = UserDefaults(suiteName: StoreLocation.appGroupID)
        #expect(GlowSettings.store !== group, "tests are using the App Group's real defaults")
    }

    @Test("Writing a preference does not reach the App Group")
    func writesStayPrivate() throws {
        // The behaviour rather than the wiring, because the wiring is a
        // `guard` somebody could rearrange.
        let key = "islandPop"
        let group = try #require(UserDefaults(suiteName: StoreLocation.appGroupID))
        let before = group.object(forKey: key)
        defer { GlowSettings.store.removeObject(forKey: key) }

        GlowSettings.store.set(41_168, forKey: key)

        #expect(GlowSettings.store.object(forKey: key) as? Int == 41_168)
        let after = group.object(forKey: key)
        #expect(
            (after as? Int) != 41_168,
            "the write reached the App Group's defaults, where it will outlive this process"
        )
        #expect(String(describing: before) == String(describing: after))
    }

    @Test("The rest day a test sets cannot survive this process")
    func restDayIsNotPersisted() {
        // The exact value that caused #168, through the exact type that reads
        // it. `withWeek` restores; this asserts the blast radius if it did not.
        //
        // Compared before against after, never against the literal 7: the App
        // Group may legitimately already hold any value — a real one the app
        // wrote, or a poisoned one this fix exists to survive — and asserting
        // `!= 7` would fail on the very machine the bug was found on. That is
        // not a hypothetical; it is what the first version of this test did.
        let group = UserDefaults(suiteName: StoreLocation.appGroupID)
        let before = group?.object(forKey: WeekPreferences.restDayKey) as? Int

        TestPreferences.withWeek(restDay: 7) {
            #expect(WeekPreferences.restDay == 7)
            let during = group?.object(forKey: WeekPreferences.restDayKey) as? Int
            #expect(
                during == before,
                "a rest day set by a test reached the App Group, where the next run will read it"
            )
        }

        #expect(group?.object(forKey: WeekPreferences.restDayKey) as? Int == before)
    }
}
