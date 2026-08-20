import Foundation

/// How often a habit is meant to happen. Two cadences only, by design:
/// a fixed-weekday schedule ("every Mon/Wed/Fri") is explicitly out of scope,
/// so a frequency habit counts completions and does not care which days they fell on.
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

    /// How many slots the row draws. A daily row is always the full week.
    var slotCount: Int {
        switch self {
        case .daily: Frequency.daysInWeek
        case .timesPerWeek(let count): count
        }
    }

    /// How many completions in a week count as the goal met.
    var weeklyTarget: Int { slotCount }
}
