import Foundation

/// Every habit and every day it was logged, as a file.
///
/// **The file leaves the device only when a person makes it leave.** Nothing
/// here uploads, syncs or phones anywhere; it turns what is already on the
/// device into text, and the only way that text goes anywhere is the share
/// sheet, on a tap. That is a privacy claim true by construction rather than by
/// policy, and it is the reason this is a file rather than an account.
///
/// Pure, per the `WeekGrid` / `SlotLayout` pattern: no store, no views, and no
/// `Date()` — the export's own timestamp is passed in, so a test can assert the
/// bytes rather than the shape of the bytes.
enum HistoryExport {
    /// The cadence, as one word that means the same thing in both formats.
    ///
    /// `Frequency`'s own cases are the source; this is the wire spelling, kept
    /// separate so renaming a case cannot silently change a file somebody has
    /// already exported and is parsing.
    static func cadence(of frequency: Frequency) -> String {
        switch frequency {
        case .daily: "daily"
        case .timesPerWeek: "times-per-week"
        case .timesPerDay: "times-per-day"
        }
    }

    /// How many times a day, or a week, the habit asks for. One for daily.
    static func target(of frequency: Frequency) -> Int {
        switch frequency {
        case .daily: 1
        case .timesPerWeek(let n): n
        case .timesPerDay(let n): n
        }
    }

    /// One row per habit per day that has anything on it.
    ///
    /// A day rather than a repetition, with the count beside it. One row per
    /// repetition would be the more atomic record and would put four identical
    /// lines in a spreadsheet for four glasses of water; the count says the same
    /// thing and stays readable in the tool people will actually open this in.
    static func csv(
        habits: [HabitSnapshot],
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        var lines = ["date,habit,cadence,target,completions"]
        for row in rows(habits: habits, calendar: calendar) {
            lines.append([
                row.day,
                escape(row.name),
                row.cadence,
                String(row.target),
                String(row.count),
            ].joined(separator: ","))
        }
        // A trailing newline: a text file without one is a text file some tools
        // read as missing its last line.
        return lines.joined(separator: "\n") + "\n"
    }

    /// The same record, nested by habit, for anything that would rather parse
    /// than tabulate.
    static func json(
        habits: [HabitSnapshot],
        exportedAt: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) throws -> String {
        let payload = Export(
            exportedAt: ISO8601DateFormatter().string(from: exportedAt),
            habits: habits
                .filter { !$0.isSpacer }
                .map { habit in
                    ExportHabit(
                        name: habit.name,
                        icon: habit.icon,
                        cadence: cadence(of: habit.frequency),
                        target: target(of: habit.frequency),
                        days: habit.completionCounts
                            .map { ExportDay(day: day($0.key, calendar), count: $0.value) }
                            // Sorted, so two exports of the same history are the
                            // same bytes. A dictionary's order is not.
                            .sorted { $0.day < $1.day }
                    )
                }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    /// A filename with the day in it, so two exports do not overwrite each
    /// other in whatever folder they land in.
    static func filename(
        on date: Date,
        extension ext: String,
        calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        "Glow Up history \(day(date, calendar)).\(ext)"
    }

    // MARK: - Shared shape

    private struct Row {
        let day: String
        let name: String
        let cadence: String
        let target: Int
        let count: Int
    }

    /// Sorted by day and then by habit, so the file reads as a history rather
    /// than as whatever order the store happened to hand over — and so the same
    /// history exports byte-for-byte the same twice.
    private static func rows(habits: [HabitSnapshot], calendar: Calendar) -> [Row] {
        habits
            .filter { !$0.isSpacer }
            .flatMap { habit in
                habit.completionCounts.map { entry in
                    Row(
                        day: day(entry.key, calendar),
                        name: habit.name,
                        cadence: cadence(of: habit.frequency),
                        target: target(of: habit.frequency),
                        count: entry.value
                    )
                }
            }
            .sorted { ($0.day, $0.name) < ($1.day, $1.name) }
    }

    /// `yyyy-MM-dd` in the user's own calendar, which is the calendar the day
    /// was normalized to when it was stored.
    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// RFC 4180: quote anything containing a comma, a quote or a newline, and
    /// double the quotes inside it. A habit called `Read, properly` is a real
    /// name and must not become two columns.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private struct Export: Encodable {
        let exportedAt: String
        let habits: [ExportHabit]
    }

    private struct ExportHabit: Encodable {
        let name: String
        let icon: String
        let cadence: String
        let target: Int
        let days: [ExportDay]
    }

    private struct ExportDay: Encodable {
        let day: String
        let count: Int
    }
}
