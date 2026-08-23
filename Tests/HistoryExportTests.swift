import Foundation
import Testing
@testable import Glow

/// The export is a file somebody else's tool will read, so these assert the
/// bytes rather than the shape of the bytes.
@Suite("History export")
struct HistoryExportTests {
    private let calendar = TestCalendar.monday
    private func day(_ d: Int) -> Date { TestCalendar.date(2026, 8, d) }

    private func habit(
        _ name: String, _ frequency: Frequency, _ counts: [Int: Int]
    ) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(), name: name, icon: "book", frequency: frequency,
            completionCounts: Dictionary(
                uniqueKeysWithValues: counts.map { (day($0.key), $0.value) }
            )
        )
    }

    @Test("One row per habit per logged day, with the count beside it")
    func csvShape() {
        let csv = HistoryExport.csv(
            habits: [
                habit("Read", .daily, [17: 1, 19: 1]),
                // Two completions on one civil day. The per-day kind is what
                // made that ordinary and it is gone (#209); a store written
                // before day identities can still hold one (#130), and the
                // count is what the file says either way.
                habit("Water", .timesPerWeek(3), [17: 2]),
            ],
            calendar: calendar
        )
        #expect(csv == """
        date,habit,cadence,target,completions
        2026-08-17,Read,daily,1,1
        2026-08-17,Water,times-per-week,3,2
        2026-08-19,Read,daily,1,1

        """)
    }

    @Test("Sorted by day and then habit, so two exports of one history match")
    func csvIsStable() {
        // `completionCounts` is a dictionary and dictionaries have no order.
        // Without the sort, exporting the same history twice could produce two
        // different files, which is the kind of thing nobody notices until a
        // diff of two backups is unreadable.
        let habits = [
            habit("Zebra", .daily, [19: 1, 17: 1, 18: 1]),
            habit("Apple", .daily, [18: 1, 17: 1]),
        ]
        let first = HistoryExport.csv(habits: habits, calendar: calendar)
        for _ in 0..<20 {
            #expect(HistoryExport.csv(habits: habits, calendar: calendar) == first)
        }
        let days = first.split(separator: "\n").dropFirst().map { $0.prefix(10) }
        #expect(days == days.sorted())
        // Same day, habits alphabetical.
        #expect(first.contains("2026-08-17,Apple") )
        #expect(first.range(of: "2026-08-17,Apple")!.lowerBound
            < first.range(of: "2026-08-17,Zebra")!.lowerBound)
    }

    @Test("A comma in a habit's name does not become a column")
    func csvEscapes() {
        let csv = HistoryExport.csv(
            habits: [habit("Read, properly", .daily, [17: 1])], calendar: calendar
        )
        #expect(csv.contains("2026-08-17,\"Read, properly\",daily,1,1"))

        // And a quote inside the name doubles, per RFC 4180.
        let quoted = HistoryExport.csv(
            habits: [habit("Say \"yes\"", .daily, [17: 1])], calendar: calendar
        )
        #expect(quoted.contains("\"Say \"\"yes\"\"\""))
    }

    @Test("A blank row is not history and is not exported")
    func spacersAreSkipped() throws {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completionCounts: [day(17): 1], isSpacer: true
        )
        #expect(HistoryExport.csv(habits: [spacer], calendar: calendar)
            == "date,habit,cadence,target,completions\n")
        let json = try HistoryExport.json(
            habits: [spacer], exportedAt: day(20), calendar: calendar
        )
        #expect(json.contains("\"habits\" : [\n\n  ]") || json.contains("\"habits\" : []"))
    }

    @Test("A habit with nothing logged still appears in the JSON")
    func emptyHabitIsStillAHabit() throws {
        // The CSV is a list of days and has nothing to say about a habit with
        // none; the JSON is a list of habits and would be lying by omission.
        let json = try HistoryExport.json(
            habits: [habit("Read", .timesPerWeek(3), [:])],
            exportedAt: day(20), calendar: calendar
        )
        #expect(json.contains("\"name\" : \"Read\""))
        #expect(json.contains("\"cadence\" : \"times-per-week\""))
        #expect(json.contains("\"target\" : 3"))
    }

    @Test("The JSON carries the day, the count and when it was exported")
    func jsonShape() throws {
        let json = try HistoryExport.json(
            habits: [habit("Water", .timesPerWeek(3), [17: 2, 18: 3])],
            exportedAt: day(20), calendar: calendar
        )
        #expect(json.contains("\"exportedAt\""))
        #expect(json.contains("\"day\" : \"2026-08-17\""))
        #expect(json.contains("\"count\" : 2"))
        #expect(json.contains("\"day\" : \"2026-08-18\""))
        #expect(json.contains("\"count\" : 3"))
        // Days sorted, for the same reason the CSV's rows are.
        #expect(json.range(of: "2026-08-17")!.lowerBound
            < json.range(of: "2026-08-18")!.lowerBound)
    }

    @Test("Every cadence has a wire spelling, and it is not the case name")
    func cadenceSpellings() {
        // Kept separate from `Frequency`'s cases on purpose: renaming a case
        // must not silently change a file somebody is already parsing.
        #expect(HistoryExport.cadence(of: .daily) == "daily")
        #expect(HistoryExport.cadence(of: .timesPerWeek(3)) == "times-per-week")
        #expect(HistoryExport.target(of: .daily) == 1)
        #expect(HistoryExport.target(of: .timesPerWeek(4)) == 4)
    }

    @Test("The filename carries the day, so two exports do not collide")
    func filename() {
        #expect(HistoryExport.filename(on: day(20), extension: "csv", calendar: calendar)
            == "Glow Up history 2026-08-20.csv")
        #expect(HistoryExport.filename(on: day(3), extension: "json", calendar: calendar)
            == "Glow Up history 2026-08-03.json")
    }
}
