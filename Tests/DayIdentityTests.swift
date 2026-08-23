import Foundation
import SwiftData
import Testing
@testable import Glow

/// #130: a completion belongs to a civil day, and stayed put only as long as
/// the phone did.
///
/// **Every zone here is stated, never the machine's.** The bug is about two
/// calendars disagreeing, so a test that used `Calendar.current` for either
/// side would be asserting something about the runner rather than about the
/// code — and would pass or fail depending on which airport CI is in. Each
/// calendar below names its own time zone, which is also why none of this needs
/// the simulator's zone changed.
@Suite("Day identity")
struct DayIdentityTests {
    // MARK: - Calendars

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private let losAngeles = DayIdentityTests.calendar("America/Los_Angeles")
    private let berlin = DayIdentityTests.calendar("Europe/Berlin")

    /// An instant in the middle of a named civil day, in a named zone. Midday
    /// so that no transition can move it onto a neighbouring date.
    private func midday(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts) ?? .distantPast
    }

    private let wednesday = DayID(year: 2026, month: 8, day: 19)

    @MainActor
    private func makeContext() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Habit.self, Completion.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    // MARK: - The value

    @Test("A day spells itself zero-padded, so the text sorts the way the days do")
    func textIsSortable() {
        #expect(DayID(year: 2026, month: 8, day: 9).text == "2026-08-09")
        #expect(DayID(year: 999, month: 12, day: 31).text == "0999-12-31")

        let days = [
            DayID(year: 2026, month: 1, day: 2),
            DayID(year: 2025, month: 12, day: 31),
            DayID(year: 2026, month: 1, day: 10),
        ]
        #expect(days.sorted().map(\.text) == days.map(\.text).sorted())
    }

    @Test("The stored spelling round-trips")
    func parsesItsOwnText() {
        for day in [
            DayID(year: 2026, month: 8, day: 19),
            DayID(year: 2000, month: 2, day: 29),
            DayID(year: 1970, month: 1, day: 1),
        ] {
            #expect(DayID(day.text) == day)
        }
    }

    @Test("What is not a day is refused rather than approximated", arguments: [
        "", "2026", "2026-08", "2026-08-19-01", "2026-08-19T00:00:00Z",
        "yesterday", "2026-13-01", "2026-00-05", "2026-08-32", "2026--08-19",
        // Arabic-Indic digits are `isNumber`, and would parse as an Int. A
        // stored key is our own text, not a locale's, so it is ASCII or it is
        // nothing.
        "٢٠٢٦-٠٨-١٩",
    ])
    func refusesNonDays(text: String) {
        #expect(DayID(text) == nil)
    }

    @Test("A day placed on a calendar is that calendar's first moment of it")
    func placesItselfAtTheStartOfTheDay() {
        for zone in ["America/Los_Angeles", "Europe/Berlin", "Asia/Kolkata", "Pacific/Auckland"] {
            let calendar = Self.calendar(zone)
            let placed = wednesday.date(in: calendar)
            #expect(placed == WeekCalendar.day(midday(2026, 8, 19, in: calendar), calendar: calendar))
            #expect(DayID(placed, calendar: calendar) == wednesday, "\(zone)")
        }
    }

    // MARK: - Travel

    @MainActor
    @Test("Los Angeles to Berlin keeps the completion on the day it was logged")
    func losAngelesToBerlin() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let context = try makeContext()
            let there = HabitStore(context: context, calendar: losAngeles)
            let habit = try there.addHabit(
                name: "Read", icon: "📖", frequency: .daily,
                now: midday(2026, 8, 19, in: losAngeles)
            )
            #expect(
                try there.toggleCompletion(
                    for: habit, on: midday(2026, 8, 19, in: losAngeles)
                ) == .completed
            )

            // The flight. Same store, same row, a calendar seven hours away.
            let row = try #require(try context.fetch(FetchDescriptor<Completion>()).first)
            #expect(row.dayID == wednesday)

            // The regression, stated as the comparison that used to be made:
            // the instant the row was normalized to is *not* Berlin's midnight
            // of the same day, which is why the slot went dark.
            #expect(row.day != wednesday.date(in: berlin))
            #expect(row.day == wednesday.date(in: losAngeles))

            // And what the grid asks for now.
            #expect(habit.completedDays(in: berlin) == [wednesday.date(in: berlin)])

            let week = WeekCalendar.week(
                containing: midday(2026, 8, 20, in: berlin), calendar: berlin
            )
            let slots = WeekGrid.slots(
                for: habit.snapshot(calendar: berlin),
                in: week,
                today: midday(2026, 8, 20, in: berlin),
                editing: .week(allowingFuture: false),
                calendar: berlin
            )
            // Monday-first, so Wednesday is column two, and it is spent.
            #expect(slots[2].state == .filled)
        }
    }

    @MainActor
    @Test("And Berlin to Los Angeles, which is the direction that used to lose a day")
    func berlinToLosAngeles() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let context = try makeContext()
            let there = HabitStore(context: context, calendar: berlin)
            let habit = try there.addHabit(
                name: "Read", icon: "📖", frequency: .daily,
                now: midday(2026, 8, 19, in: berlin)
            )
            try there.toggleCompletion(for: habit, on: midday(2026, 8, 19, in: berlin))

            #expect(habit.completedDays(in: losAngeles) == [wednesday.date(in: losAngeles)])

            let week = WeekCalendar.week(
                containing: midday(2026, 8, 20, in: losAngeles), calendar: losAngeles
            )
            let slots = WeekGrid.slots(
                for: habit.snapshot(calendar: losAngeles),
                in: week,
                today: midday(2026, 8, 20, in: losAngeles),
                editing: .week(allowingFuture: false),
                calendar: losAngeles
            )
            #expect(slots[2].state == .filled)
        }
    }

    @MainActor
    @Test("A second tap on the same civil day un-marks it rather than doubling it")
    func travelCannotDuplicateADay() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let context = try makeContext()
            let habit = try HabitStore(context: context, calendar: losAngeles).addHabit(
                name: "Read", icon: "📖", frequency: .daily,
                now: midday(2026, 8, 19, in: losAngeles)
            )
            let there = HabitStore(context: context, calendar: losAngeles)
            try there.toggleCompletion(for: habit, on: midday(2026, 8, 19, in: losAngeles))
            #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)

            // Same day, other side of the world. Before #130 this found no
            // match and wrote a second row for one day.
            let here = HabitStore(context: context, calendar: berlin)
            #expect(
                try here.toggleCompletion(
                    for: habit, on: midday(2026, 8, 19, in: berlin)
                ) == .uncompleted
            )
            #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
        }
    }

    @MainActor
    @Test("A per-day habit's repetitions land on one day, not on two")
    func repetitionsStayOnOneDay() throws {
        let context = try makeContext()
        let there = HabitStore(context: context, calendar: losAngeles)
        let habit = try there.addHabit(
            name: "Water", icon: "drop", frequency: Frequency(timesPerDay: 3),
            now: midday(2026, 8, 19, in: losAngeles)
        )
        #expect(try there.addCompletion(for: habit, on: midday(2026, 8, 19, in: losAngeles)) == 1)

        let here = HabitStore(context: context, calendar: berlin)
        #expect(here.count(for: habit, on: midday(2026, 8, 19, in: berlin)) == 1)
        #expect(try here.addCompletion(for: habit, on: midday(2026, 8, 19, in: berlin)) == 2)
        #expect(habit.completionDayCounts == [wednesday: 2])

        #expect(try here.clearDay(for: habit, on: midday(2026, 8, 19, in: berlin)) == 2)
        #expect(habit.completionDayCounts.isEmpty)
    }

    @MainActor
    @Test("Two rows a pre-#130 build left on one day both come off on one tap")
    func aDuplicatedDayIsRepairedByUnmarking() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let context = try makeContext()
            let there = HabitStore(context: context, calendar: berlin)
            let habit = try there.addHabit(
                name: "Read", icon: "📖", frequency: .daily,
                now: midday(2026, 8, 19, in: berlin)
            )
            // Exactly the residue the bug leaves: the same civil day written
            // twice, from two zones.
            for zone in [losAngeles, berlin] {
                context.insert(
                    Completion(
                        day: wednesday.date(in: zone), habit: habit, calendar: zone
                    )
                )
            }
            try context.save()
            #expect(habit.completionDayCounts == [wednesday: 2])

            #expect(
                try there.toggleCompletion(
                    for: habit, on: midday(2026, 8, 19, in: berlin)
                ) == .uncompleted
            )
            #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)
        }
    }

    // MARK: - Clocks changing

    @Test("A day keeps its identity across a transition, including one at midnight")
    func daylightSavingKeepsIdentity() {
        // Berlin moves at 02:00 and Santiago at 00:00, which is the case that
        // breaks asking a calendar for midnight: on that morning there is no
        // 00:00 at all.
        let cases: [(String, [(Int, Int, Int)])] = [
            ("Europe/Berlin", [(2026, 3, 28), (2026, 3, 29), (2026, 3, 30),
                               (2026, 10, 24), (2026, 10, 25), (2026, 10, 26)]),
            ("America/Santiago", [(2026, 9, 5), (2026, 9, 6), (2026, 9, 7),
                                  (2026, 4, 4), (2026, 4, 5), (2026, 4, 6)]),
            ("Pacific/Auckland", [(2026, 9, 26), (2026, 9, 27), (2026, 9, 28),
                                  (2026, 4, 4), (2026, 4, 5), (2026, 4, 6)]),
        ]
        for (zone, days) in cases {
            let calendar = Self.calendar(zone)
            for (year, month, day) in days {
                let id = DayID(year: year, month: month, day: day)
                let placed = id.date(in: calendar)
                #expect(placed != .distantPast, "\(zone) \(id)")
                #expect(DayID(placed, calendar: calendar) == id, "\(zone) \(id)")
                // The same value everything week-shaped is built from.
                #expect(
                    placed == WeekCalendar.day(
                        midday(year, month, day, in: calendar), calendar: calendar
                    ),
                    "\(zone) \(id)"
                )
            }
        }
    }

    @MainActor
    @Test("A completion logged on the morning the clocks change stays on that morning")
    func completionSurvivesATransition() throws {
        try TestPreferences.withWeek(firstWeekday: 2) {
            let context = try makeContext()
            let store = HabitStore(context: context, calendar: berlin)
            let spring = DayID(year: 2026, month: 3, day: 29)
            let habit = try store.addHabit(
                name: "Read", icon: "📖", frequency: .daily,
                now: midday(2026, 3, 29, in: berlin)
            )
            try store.toggleCompletion(for: habit, on: midday(2026, 3, 29, in: berlin))

            #expect(habit.completionDayCounts == [spring: 1])
            // A second tap the following week still finds it.
            #expect(
                try store.toggleCompletion(
                    for: habit, on: midday(2026, 3, 29, in: berlin)
                ) == .uncompleted
            )
        }
    }

    // MARK: - Reading a legacy row

    /// Local midnight of 19 August 2026, the way a pre-#130 build wrote it.
    private func legacyMidnight(in zone: String) -> Date {
        wednesday.date(in: Self.calendar(zone))
    }

    @Test("A legacy row recovers the day it was written on, in every ordinary zone", arguments: [
        "Pacific/Midway", "America/Los_Angeles", "America/Sao_Paulo", "UTC",
        "Europe/Berlin", "Africa/Johannesburg", "Asia/Kolkata", "Asia/Kathmandu",
        "Asia/Tokyo", "Australia/Sydney", "Pacific/Auckland",
    ])
    func recoversTheOriginalDay(zone: String) {
        #expect(DayID.recovered(fromLegacyMidnight: legacyMidnight(in: zone)) == wednesday)
    }

    @Test("The limit is the far side of the date line, and it is off by one")
    func recoveryHasAStatedLimit() {
        // UTC+13 and +14 in August. There is nothing in the instant that
        // separates these from a neighbouring day written in Europe, so the
        // rule reads them as the day before rather than guessing a zone. The
        // untouched `Completion.day` is what a better rule would run against.
        for zone in ["Pacific/Kiritimati", "Pacific/Apia", "Pacific/Chatham"] {
            #expect(
                DayID.recovered(fromLegacyMidnight: legacyMidnight(in: zone))
                    == DayID(year: 2026, month: 8, day: 18),
                "\(zone)"
            )
        }
    }

    @Test("Recovery does not consult the calendar it is read with")
    func recoveryIsZoneIndependent() {
        // The whole reason for rounding to the nearest UTC midnight rather than
        // reading the instant where the phone happens to be: the same row must
        // not become a different day because somebody landed somewhere.
        let instant = legacyMidnight(in: "America/Los_Angeles")
        let answers = Set(
            ["Pacific/Midway", "UTC", "Europe/Berlin", "Asia/Tokyo", "Pacific/Auckland"]
                .map { _ in DayID.recovered(fromLegacyMidnight: instant) }
        )
        #expect(answers == [wednesday])
    }

    @MainActor
    @Test("An unstamped row reads as its day before anything has migrated")
    func legacyRowsReadCorrectlyBeforeTheBackfill() throws {
        let context = try makeContext()
        let habit = Habit(
            name: "Read", icon: "📖", frequency: .daily,
            createdAt: midday(2026, 8, 19, in: losAngeles), sortOrder: 0
        )
        context.insert(habit)
        let row = Completion(
            day: wednesday.date(in: losAngeles), habit: habit, calendar: losAngeles
        )
        context.insert(row)
        // What a store written before this column existed holds.
        row.dayKey = ""
        try context.save()

        #expect(row.dayID == wednesday)
        #expect(habit.completionDayCounts == [wednesday: 1])
        #expect(habit.completedDays(in: berlin) == [wednesday.date(in: berlin)])
    }

    // MARK: - The backfill

    /// A store on a real file holding `count` completions with no `dayKey`,
    /// one per day counting back from 19 August 2026 in `zone`.
    ///
    /// `@discardableResult` because two of the three callers plant the rows and
    /// then read them back through the app's own types rather than through the
    /// dates returned here — the return value is a convenience, not the point.
    @MainActor
    @discardableResult
    private func legacyStore(at url: URL, days: Int, zone: Calendar) throws -> [Date] {
        let context = try TestStore.writable(at: url)
        let habit = Habit(
            name: "Read", icon: "📖", frequency: .daily,
            createdAt: midday(2026, 8, 19, in: zone), sortOrder: 0
        )
        context.insert(habit)
        var written: [Date] = []
        for offset in 0..<days {
            let day = DayID(year: 2026, month: 8, day: 19 - offset).date(in: zone)
            let row = Completion(day: day, habit: habit, calendar: zone)
            row.dayKey = ""
            context.insert(row)
            written.append(day)
        }
        try context.save()
        return written
    }

    @MainActor
    @Test("The backfill stamps every legacy row, once, and then has nothing to do")
    func backfillStampsAndStops() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        let written = try legacyStore(at: url, days: 5, zone: losAngeles)

        let context = try TestStore.writable(at: url)
        #expect(StoreMigration.stampDayIdentities(in: context) == .stamped(5))

        let rows = try context.fetch(FetchDescriptor<Completion>()).sorted { $0.day < $1.day }
        #expect(rows.map(\.dayKey) == (0..<5).reversed().map {
            DayID(year: 2026, month: 8, day: 19 - $0).text
        })
        // And the instants are exactly what they were. This is the reversal
        // path: nothing a later, better rule would need has been overwritten.
        #expect(rows.map(\.day) == written.sorted())

        #expect(StoreMigration.stampDayIdentities(in: context) == .notNeeded)
    }

    @MainActor
    @Test("A run cut off half-way leaves the rest for the next one")
    func backfillResumes() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        try legacyStore(at: url, days: 4, zone: berlin)

        let context = try TestStore.writable(at: url)
        // One row stamped by hand is the shape an interrupted run leaves: some
        // keyed, some not. The work is defined by what is missing, not by a
        // cursor, so there is nothing to resume *from*.
        let first = try #require(try context.fetch(FetchDescriptor<Completion>()).first)
        first.dayKey = DayID.recovered(fromLegacyMidnight: first.day).text
        try context.save()

        #expect(StoreMigration.stampDayIdentities(in: context) == .stamped(3))
        #expect(
            try context.fetchCount(
                FetchDescriptor<Completion>(predicate: #Predicate { $0.dayKey == "" })
            ) == 0
        )
    }

    @MainActor
    @Test("A backfill that cannot save changes nothing, and the store still reads")
    func backfillFailureIsSurvivable() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }
        try legacyStore(at: url, days: 3, zone: losAngeles)

        // Every save through this context throws, which is the only honest way
        // to ask what a failed migration leaves behind.
        let blocked = try TestStore.readOnly(at: url)
        let outcome = StoreMigration.stampDayIdentities(in: blocked)
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }

        let reopened = try TestStore.writable(at: url)
        let rows = try reopened.fetch(FetchDescriptor<Completion>())
        #expect(rows.allSatisfy { $0.dayKey.isEmpty })
        // The point of the whole arrangement: an unmigrated store shows the
        // same history as a migrated one.
        #expect(Set(rows.map(\.dayID)) == Set((0..<3).map {
            DayID(year: 2026, month: 8, day: 19 - $0)
        }))
    }

    @MainActor
    @Test("The migration record says the days were established, and format 2 says which")
    func backfillIsRecorded() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "glow-dayid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appending(path: "default.store")
        let destination = root.appending(path: "Glow.store")
        try legacyStore(at: source, days: 2, zone: berlin)
        #expect(StoreMigration.run(from: source, to: destination) == .migrated)

        let before = try #require(StoreMigration.readRecord(for: destination))
        #expect(before.dayFormat == nil)

        let context = try TestStore.writable(at: destination)
        #expect(StoreMigration.stampDayIdentities(in: context, storeAt: destination) == .stamped(2))

        let after = try #require(StoreMigration.readRecord(for: destination))
        #expect(after.format == StoreMigration.Record.currentFormat)
        #expect(after.dayFormat == StoreMigration.Record.currentDayFormat)
        #expect(after.stampedDays == 2)
        // The counts the earlier migration proved are not disturbed by the
        // later one annotating the same file.
        #expect(after.completionCount == before.completionCount)
        #expect(after.generation == before.generation)
    }

    @Test("A record written before day identities existed still reads")
    func formatOneRecordsStillDecode() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "glow-record-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Glow.store")

        // Byte-for-byte what a shipped build wrote. A non-optional addition
        // would make this fail to decode and every migrated install look
        // unmigrated.
        let json = """
        {
          "completionCount" : 12,
          "format" : 1,
          "generation" : "8B1B7A2E-4C5C-4E2E-9A0B-2C7E2C0C1A11",
          "habitCount" : 3,
          "migratedAt" : "2026-08-01T09:00:00Z",
          "source" : "default.store"
        }
        """
        try Data(json.utf8).write(to: StoreMigration.recordURL(for: destination))

        let record = try #require(StoreMigration.readRecord(for: destination))
        #expect(record.format == 1)
        #expect(record.dayFormat == nil)
        #expect(record.completionCount == 12)
    }

    @MainActor
    @Test("A store nothing ever migrated does not gain a record it has not earned")
    func backfillDoesNotInventARecord() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "glow-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appending(path: "Glow.store")
        try legacyStore(at: store, days: 1, zone: berlin)

        let context = try TestStore.writable(at: store)
        #expect(StoreMigration.stampDayIdentities(in: context, storeAt: store) == .stamped(1))
        #expect(StoreMigration.readRecord(for: store) == nil)
    }

    // MARK: - Export

    @MainActor
    @Test("An export names the civil day, whichever zone it is written from")
    func exportNamesTheCivilDay() throws {
        let context = try makeContext()
        let store = HabitStore(context: context, calendar: losAngeles)
        let habit = try store.addHabit(
            name: "Read", icon: "📖", frequency: .daily,
            now: midday(2026, 8, 19, in: losAngeles)
        )
        try TestPreferences.withWeek(firstWeekday: 2) {
            try store.toggleCompletion(for: habit, on: midday(2026, 8, 19, in: losAngeles))
        }

        for calendar in [losAngeles, berlin, Self.calendar("Pacific/Auckland")] {
            let csv = HistoryExport.csv(
                habits: [habit.snapshot(calendar: calendar)], calendar: calendar
            )
            #expect(csv == "date,habit,cadence,target,completions\n2026-08-19,Read,daily,1,1\n")

            let json = try HistoryExport.json(
                habits: [habit.snapshot(calendar: calendar)],
                exportedAt: midday(2026, 8, 20, in: calendar),
                calendar: calendar
            )
            #expect(json.contains("\"day\" : \"2026-08-19\""))
        }
    }
}
