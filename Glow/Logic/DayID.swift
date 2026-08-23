import Foundation

/// The day a person would name, with no instant in it.
///
/// **A completion belongs to a civil date, not to a moment.** "I read on the
/// 19th" stays true in Berlin, in Los Angeles, and on the morning the clocks
/// change; an instant does not. `Completion.day` used to carry the whole of that
/// meaning as a local midnight, and a local midnight is a different instant in
/// every zone — so the same 19 August compared unequal to itself after a flight,
/// vanished from the grid, and let a second tap write a second row for a day
/// that already had one. That is #130.
///
/// Three numbers rather than a `Date` because the numbers are the fact. There is
/// no zone to get wrong, no arithmetic that can drift by an hour, and the stored
/// spelling — `yyyy-MM-dd` — is legible in the store, in an export, and in a
/// crash report.
///
/// Nothing here calls `Date()` or reads `Calendar.current`: a calendar is always
/// passed in, so the same input gives the same answer on any machine, which is
/// the `WeekGrid` / `WeekSpans` pattern.
struct DayID: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The civil date `date` falls on, read in `calendar`.
    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Parses the stored spelling, and refuses anything else.
    ///
    /// By hand rather than through a `DateFormatter`, which would bring a
    /// locale, a time zone and a calendar to a problem that has none of those:
    /// a formatter set to a Buddhist calendar reads `2026` as a different year,
    /// and one set to a zone reads a date as an instant. Splitting on hyphens
    /// cannot do either.
    ///
    /// Strict, because the alternative to a nil here is a row silently
    /// belonging to the wrong day. A caller that gets nil falls back to the
    /// legacy instant, which is a worse answer but a stated one.
    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `yyyy-MM-dd`. Zero-padded so the text sorts the way the dates do, which
    /// is what makes a stored key usable as a sort key and an export
    /// byte-stable.
    var text: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var description: String { text }

    /// The first moment of this day in `calendar` — what everything
    /// week-shaped still compares by equality.
    ///
    /// **Noon, then back to the start of the day.** Asking a calendar for
    /// midnight directly is the one arithmetic that a DST transition breaks:
    /// where a country moves its clocks forward at midnight, 00:00 does not
    /// exist that morning and `date(from:)` answers with whatever it can.
    /// Midday exists in every zone on every day, and `startOfDay` from there is
    /// the first moment that does exist — 01:00 on that one morning, which is
    /// exactly what `WeekCalendar.day` produces for the same day.
    func date(in calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        guard let midday = calendar.date(from: parts) else { return .distantPast }
        return calendar.startOfDay(for: midday)
    }

    static func < (lhs: DayID, rhs: DayID) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The stretch of civil days two instants span, ends included.
    ///
    /// What a bounded history read is asked for (#135): a surface that draws a
    /// week, a month or a year says which days it draws, and reads only those.
    /// Reversed inputs are put in order rather than trapping — a caller with
    /// two dates and no opinion about which is earlier should not have to know.
    static func range(
        from first: Date, through last: Date, calendar: Calendar
    ) -> ClosedRange<DayID> {
        let a = DayID(first, calendar: calendar)
        let b = DayID(last, calendar: calendar)
        return a <= b ? a...b : b...a
    }

    // MARK: - Reading a legacy instant

    /// What day a pre-`DayID` `Completion.day` was meant to name.
    ///
    /// **The zone it was written in is not recoverable, so this does not guess
    /// one.** A legacy row holds local midnight of some day D in some zone with
    /// offset `o`, which is `utcMidnight(D) - o`. Every real `o` is inside
    /// ±12 hours except for a handful of Pacific zones, so the UTC midnight
    /// *nearest* the stored instant is D — for Berlin (22:00 the day before),
    /// for Los Angeles (07:00 that morning), and for everything between them.
    ///
    /// The point of rounding rather than reading the instant in the device's
    /// current zone is that **this answer does not depend on where the phone
    /// is** when the app happens to open. A zone-dependent backfill would give
    /// two people with the same history two different histories, and would give
    /// one person a different one depending on which airport they landed in.
    ///
    /// **The limit, stated rather than hidden:** a row written at UTC+12:45,
    /// +13 or +14 (Chatham, Apia, Kiritimati) recovers as the day before, and
    /// one written at UTC-12 as the day after. There is no information in the
    /// instant that separates those from a neighbouring day written elsewhere.
    /// `Completion.day` is never rewritten, so a later build that learns the
    /// zone some other way can redo this from the untouched original.
    static func recovered(fromLegacyMidnight instant: Date) -> DayID {
        // Half-up on the epoch day, not `rounded()`: away-from-zero would
        // round the two directions differently either side of 1970.
        let epochDay = ((instant.timeIntervalSince1970 / 86_400) + 0.5).rounded(.down)
        let utcMidnight = Date(timeIntervalSince1970: epochDay * 86_400)
        return DayID(utcMidnight, calendar: utc)
    }

    /// Gregorian and UTC, built once. Only `recovered` uses it, and only to
    /// read the components of an instant that is already a UTC midnight.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

extension DayID: Codable {
    /// Encoded as its own text, so a `DayID` inside a file reads as
    /// `"2026-08-19"` rather than as three numbers in a box.
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DayID(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "not a yyyy-MM-dd day: \(text)")
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
