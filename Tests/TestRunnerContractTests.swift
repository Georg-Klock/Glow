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

    /// #181: the read itself is gone, which is what ends the series above.
    ///
    /// The three issues before it each made a process-wide store *harmless* in
    /// one more situation — serialised suites, a private defaults suite, a host
    /// that draws nothing — and every one of them left the read in place. The
    /// rest day is a parameter now, so a grid cannot inherit one from whatever
    /// else the process has been doing.
    ///
    /// A source scan, the way #141, #168 and #179 assert claims a test cannot
    /// watch from inside: the property is *the absence of a call*, and no
    /// runtime assertion can observe an absence — a test that set no rest day
    /// and found nothing resting would pass whether or not the read existed.
    ///
    /// `WeekPreferences.swift` is the one exemption, because that is where the
    /// stored value lives. Everything else in `Glow/Logic/` takes it as an
    /// argument.
    @Test("No decision logic reads the stored rest day")
    func logicTakesTheRestDayAsAParameter() throws {
        let logic = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Glow/Logic")
        let files = try FileManager.default.contentsOfDirectory(
            at: logic, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        // The scan is only worth anything if it found the directory.
        #expect(files.count > 10, "Glow/Logic looks wrong: \(files.count) files")

        for file in files where file.lastPathComponent != "WeekPreferences.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Code only: the doc comments in here name the property constantly,
            // and they should.
            let code = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
                // The *key* is a name, not a read — a view binds `@AppStorage`
                // to it. Removed first so it cannot look like the property.
                .replacingOccurrences(of: "WeekPreferences.restDayKey", with: "")
            #expect(
                !code.contains("WeekPreferences.restDay"),
                "\(file.lastPathComponent) reads the stored rest day"
            )
        }
    }

    /// #204: and no decision logic reads the clock, for the same reason.
    ///
    /// The rule has always been "no views, no store, no `Date()`" — the rest
    /// day was the exception that proved it, and it cost four issues. #204
    /// added a second thing a surface has to be *told*: which day is today.
    /// Its `WeekCalendar.today()` reads the clock and the App Group both, and
    /// it is declared in `Glow/Store/DebugToday.swift` rather than beside the
    /// rest of `WeekCalendar` precisely so that `Glow/Logic/` keeps neither
    /// read. Nothing but a scan can hold that: the extension is in the same
    /// module, so a call to it from inside `Glow/Logic/` compiles.
    ///
    /// A scan for the same reason the one above is one — the property is the
    /// *absence* of a call, and no runtime assertion can watch an absence.
    /// Doc comments are dropped first: the files in here name `Date()`
    /// constantly, saying they do not call it.
    @Test("No decision logic reads the clock")
    func logicDoesNotReadTheClock() throws {
        let logic = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Glow/Logic")
        let files = try FileManager.default.contentsOfDirectory(
            at: logic, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        #expect(files.count > 10, "Glow/Logic looks wrong: \(files.count) files")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(
                !code.contains("Date()"),
                "\(file.lastPathComponent) reads the clock; a day arrives as a parameter"
            )
            #expect(
                !code.contains("DebugToday"),
                "\(file.lastPathComponent) reads the debug override rather than being told a day"
            )
            #expect(
                !code.contains("WeekCalendar.today"),
                "\(file.lastPathComponent) asks what today is; it should be told"
            )
        }
    }
}
