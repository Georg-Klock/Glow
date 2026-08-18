import Foundation

/// How often a habit is meant to happen. Two cadences only, by design:
/// a fixed-weekday schedule ("every Mon/Wed/Fri") is explicitly out of scope,
/// so a frequency habit counts completions and does not care which days they fell on.
enum Frequency: Equatable, Hashable, Sendable, Codable {
    case daily
    case timesPerWeek(Int)

    /// What the frequency picker offers. 7x a week is `daily` wearing a
    /// different hat, and 1x a week is a single-pill row that reads as broken,
    /// so neither is selectable. See docs/decisions.md.
    static let selectableCounts = 2...6

    /// Normalizing initializer, so no caller can construct a degenerate case.
    /// Anything at or above 7 collapses to `.daily`; anything below 2 clamps up.
    init(timesPerWeek count: Int) {
        let clamped = min(max(count, Frequency.selectableCounts.lowerBound), 7)
        self = clamped >= 7 ? .daily : .timesPerWeek(clamped)
    }

    /// How many slots the row draws. A daily row is always the full week.
    var slotCount: Int {
        switch self {
        case .daily: 7
        case .timesPerWeek(let count): count
        }
    }

    /// How many completions in a week count as the goal met.
    var weeklyTarget: Int { slotCount }
}
