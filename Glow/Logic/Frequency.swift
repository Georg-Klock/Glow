import Foundation

/// How often a habit is meant to happen.
///
/// **A habit is counted across a week, and only across a week** (#209). There
/// used to be a second kind — `timesPerDay`, several repetitions inside one day,
/// drawn as the Today ring — and it is out of the shipped app: it is 2.0 scope,
/// preserved whole on `feature/daily-habits-2.0`. What that leaves is one
/// question for one screen, which This Week answers.
///
/// **`daily` is not that kind and never was.** It is a weekly cadence due all
/// seven days — seven columns on the week grid — and it is untouched. The two
/// senses of the word cost this file a paragraph of warning while both existed;
/// only one exists now.
///
/// Within the weekly kind there are two cadences only: a fixed-weekday schedule
/// ("every Mon/Wed/Fri") is explicitly out of scope, so a frequency habit counts
/// completions and does not care which days they fell on.
enum Frequency: Equatable, Hashable, Sendable, Codable {
    case daily
    case timesPerWeek(Int)

    static let daysInWeek = 7

    /// What the frequency stepper offers. Seven is included and *is* daily:
    /// the editor counts days and this type decides what that means, so there
    /// is no mode to keep in step with the number. See docs/decisions.md.
    static let selectableCounts = 1...daysInWeek

    /// Normalizing initializer, so no caller can construct a degenerate case.
    /// Anything at or above 7 collapses to `.daily`; anything below 1 clamps up.
    init(timesPerWeek count: Int) {
        let clamped = min(max(count, Frequency.selectableCounts.lowerBound), Frequency.daysInWeek)
        self = clamped >= Frequency.daysInWeek ? .daily : .timesPerWeek(clamped)
    }

    /// How many slots the week row draws. A daily row is always the full week.
    ///
    /// **Still optional, with no case that answers nil** (#209). The per-day
    /// kind was the nil, and a caller reaching for a week had to say what it
    /// meant when there wasn't one. Flattening it to `Int` now would rewrite
    /// every one of those call sites in the same change that removed the
    /// feature, and would have to be undone to put the feature back. It stays
    /// optional until 2.0 is decided either way.
    var slotCount: Int? {
        switch self {
        case .daily: Frequency.daysInWeek
        case .timesPerWeek(let count): count
        }
    }

    /// How many completions in a week count as the goal met.
    var weeklyTarget: Int? { slotCount }
}
