import Foundation
import Testing
@testable import Glow

/// #282: no share sheet over a partial read.
///
/// The export used to build its snapshots through the non-throwing helpers,
/// which flatten a failed completion fetch into empty history — so the file
/// was written, the sheet opened, and the one error it must never paper over
/// had been erased before the `do` block began. `ExportStore.writeHistory`
/// fixes the order: read everything, render everything, and only then let a
/// file exist. These tests hold that order through the seam the order is
/// built from — the throwing snapshots closure.
@Suite("Export is all or nothing")
struct ExportAllOrNothingTests {
    private struct Failed: Error {}

    private func fixtures() -> [HabitSnapshot] {
        let day = TestCalendar.date(2026, 8, 18)
        return [
            HabitSnapshot(
                id: UUID(), name: "Gym", icon: "figure.run",
                frequency: .daily, completionCounts: [day: 1]
            ),
            // A habit never logged still appears in the JSON — that it cannot
            // appear in the CSV is the shape #285 records.
            HabitSnapshot(
                id: UUID(), name: "Read", icon: "book",
                frequency: .timesPerWeek(3), completionCounts: [:]
            ),
        ]
    }

    private func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("export-tests-\(UUID().uuidString)")
    }

    private func files(in store: ExportStore) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: store.directory, includingPropertiesForKeys: nil
        )) ?? []
    }

    @Test("A successful export writes one complete file", arguments: HistoryExport.Format.allCases)
    func successWrites(format: HistoryExport.Format) throws {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ExportStore(base: base)

        let url = try store.writeHistory(
            format: format, exportedAt: TestCalendar.date(2026, 8, 19)
        ) { fixtures() }

        #expect(url.pathExtension == format.fileExtension)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Gym"))
        #expect(files(in: store) == [url])
    }

    @Test("A failed read leaves no file and no share candidate")
    func failedReadLeavesNothing() {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ExportStore(base: base)

        #expect(throws: Failed.self) {
            _ = try store.writeHistory(
                format: .csv, exportedAt: TestCalendar.date(2026, 8, 19)
            ) { throw Failed() }
        }
        #expect(files(in: store).isEmpty, "a failed export left a file behind")
    }

    @Test("A failure after a success does not disturb the earlier export")
    func failureLeavesThePreviousFileAlone() throws {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ExportStore(base: base)

        let first = try store.writeHistory(
            format: .json, exportedAt: TestCalendar.date(2026, 8, 19)
        ) { fixtures() }

        #expect(throws: Failed.self) {
            _ = try store.writeHistory(
                format: .csv, exportedAt: TestCalendar.date(2026, 8, 20)
            ) { throw Failed() }
        }
        // The sweep runs inside `write`, which a failed read never reaches —
        // so the file the share sheet may still be holding is untouched.
        #expect(files(in: store) == [first])
    }

    @Test("The rendered file is the same bytes the pure renderer produces")
    func fileMatchesTheRenderer() throws {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let store = ExportStore(base: base)
        let exportedAt = TestCalendar.date(2026, 8, 19)
        let habits = fixtures()

        let url = try store.writeHistory(format: .csv, exportedAt: exportedAt) { habits }

        #expect(
            try String(contentsOf: url, encoding: .utf8)
                == HistoryExport.csv(habits: habits)
        )
        #expect(
            url.lastPathComponent
                == HistoryExport.filename(on: exportedAt, extension: "csv")
        )
    }
}
