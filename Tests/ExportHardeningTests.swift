import Foundation
import Testing
@testable import Glow

/// #142: a habit name is a person's own text, and it ends up in two places
/// where text is not just text — a spreadsheet cell, and a file on disk.
@Suite("Export hardening")
struct ExportHardeningTests {
    // MARK: - Formulas

    @Test("A name that starts a formula is defused")
    func formulaLeaders() {
        // The four leaders, each a real thing a spreadsheet will run.
        #expect(HistoryExport.defused("=1+1") == "'=1+1")
        #expect(HistoryExport.defused("+1") == "'+1")
        #expect(HistoryExport.defused("-1+1") == "'-1+1")
        #expect(HistoryExport.defused("@SUM(A1)") == "'@SUM(A1)")
    }

    @Test("Leading whitespace does not protect a formula")
    func whitespacePrefixed() {
        // Excel strips these and *then* decides, so a check on the raw first
        // character would pass every one of them through.
        #expect(HistoryExport.defused(" =1+1") == "' =1+1")
        #expect(HistoryExport.defused("\t=1+1") == "'\t=1+1")
        #expect(HistoryExport.defused("\r=1+1") == "'\r=1+1")
        #expect(HistoryExport.defused("  \t =1+1") == "'  \t =1+1")
    }

    @Test("An ordinary name is left exactly alone")
    func ordinaryNames() {
        // The apostrophe is a cost, so it is only paid where it buys something.
        for name in ["Workout", "Read, properly", "3x Water", "café", "🏃 Run", ""] {
            #expect(HistoryExport.defused(name) == name)
        }
        // A formula character that is not leading is not a formula.
        #expect(HistoryExport.defused("1+1") == "1+1")
        #expect(HistoryExport.defused("Rest = good") == "Rest = good")
    }

    @Test("Whitespace alone is not a formula")
    func whitespaceOnly() {
        #expect(HistoryExport.defused("   ") == "   ")
        #expect(HistoryExport.defused("\t") == "\t")
    }

    @Test("The CSV carries the defused name, still correctly escaped")
    func csvCombinesBoth() {
        // The two problems are separate and both have to be handled: the
        // apostrophe stops it computing, the quotes stop it splitting.
        let habit = HabitSnapshot.fixture(
            name: "=HYPERLINK(\"x\"), y",
            frequency: .timesPerWeek(3),
            completedDays: [TestCalendar.date(2026, 8, 17)]
        )
        let csv = HistoryExport.csv(habits: [habit], calendar: TestCalendar.monday)
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\"), y\""))
        // And the row is still five fields, which is the point of the escaping.
        let row = csv.split(separator: "\n")[1]
        #expect(row.hasPrefix("2026-08-17,\"'="))
    }

    @Test("JSON is left alone")
    func jsonIsNotDefused() {
        // A parser has no notion of a formula, so there is nothing to defuse
        // and an apostrophe there would just be a wrong name.
        let habit = HabitSnapshot.fixture(
            name: "=1+1",
            frequency: .timesPerWeek(3),
            completedDays: [TestCalendar.date(2026, 8, 17)]
        )
        let json = try! HistoryExport.json(
            habits: [habit],
            exportedAt: TestCalendar.date(2026, 8, 22),
            calendar: TestCalendar.monday
        )
        #expect(json.contains("\"=1+1\""))
        #expect(!json.contains("'=1+1"))
    }

    // MARK: - The file's lifetime

    /// A disposable directory, so the assertions are about real files.
    private func withStore(_ body: (ExportStore) throws -> Void) rethrows {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try body(ExportStore(base: base))
    }

    @Test("What is written is there, and inside the store's own folder")
    func writeLands() throws {
        try withStore { store in
            let url = try store.write("date,habit\n", named: "glow.csv")
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try String(contentsOf: url, encoding: .utf8) == "date,habit\n")
            #expect(store.owns(url))
        }
    }

    @Test("Discarding takes it away")
    func discardRemoves() throws {
        try withStore { store in
            let url = try store.write("x", named: "glow.csv")
            store.discard(url)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("A second export does not leave the first behind")
    func writeSweepsFirst() throws {
        // The fallback for the one case no dismissal handler can cover: the app
        // being killed while the share sheet is up.
        try withStore { store in
            let first = try store.write("one", named: "a.csv")
            let second = try store.write("two", named: "b.csv")
            #expect(!FileManager.default.fileExists(atPath: first.path))
            #expect(FileManager.default.fileExists(atPath: second.path))
        }
    }

    @Test("Sweeping leaves the folder empty")
    func sweepClears() throws {
        try withStore { store in
            _ = try store.write("one", named: "a.csv")
            store.sweep()
            let left = try? FileManager.default.contentsOfDirectory(
                at: store.directory, includingPropertiesForKeys: nil
            )
            #expect((left ?? []).isEmpty)
        }
    }

    @Test("Discard refuses anything it does not own")
    func discardIsScoped() throws {
        // Sweeping means deleting, so the one thing this type must never do is
        // delete something it did not write.
        try withStore { store in
            let outsider = FileManager.default.temporaryDirectory
                .appendingPathComponent("not-ours-\(UUID().uuidString).csv")
            try "keep me".write(to: outsider, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: outsider) }

            #expect(!store.owns(outsider))
            store.discard(outsider)
            #expect(FileManager.default.fileExists(atPath: outsider.path))

            // Including one dressed up to look like ours.
            let traversal = store.directory
                .appendingPathComponent("..")
                .appendingPathComponent(outsider.lastPathComponent)
            #expect(!store.owns(traversal))
            store.discard(traversal)
            #expect(FileManager.default.fileExists(atPath: outsider.path))
        }
    }

    @Test("Sweeping an empty or absent folder is not an error")
    func sweepIsSafeWhenThereIsNothing() {
        withStore { store in
            store.sweep()
            store.sweep()
        }
    }
}
