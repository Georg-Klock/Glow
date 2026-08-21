import Foundation

/// How often a habit is meant to happen.
///
/// A habit is counted **across a week** or **within a day**, never both. That
/// either/or is what lets each screen ask one question: This Week shows the
/// weekly cadences, Today shows the per-day counts, and neither has to explain
/// a habit that is partly the other. See docs/vision.md.
///
/// Within the weekly kind there are two cadences only: a fixed-weekday schedule
/// ("every Mon/Wed/Fri") is explicitly out of scope, so a frequency habit counts
/// completions and does not care which days they fell on.
enum Frequency: Equatable, Hashable, Sendable, Codable {
    case daily
    case timesPerWeek(Int)
    /// Several times in a single day — water, a short walk, a sitting practice.
    /// The count resets with the day; nothing carries over.
    case timesPerDay(Int)

    static let daysInWeek = 7

    /// What the frequency stepper offers. Seven is included and *is* daily:
    /// the editor counts days and this type decides what that means, so there
    /// is no mode to keep in step with the number. See docs/decisions.md.
    static let selectableCounts = 1...daysInWeek

    /// What a per-day count can be. Twelve is the ceiling because the ring is
    /// drawn as one arc per repetition, and past a dozen the arcs stop being
    /// countable at a glance — which is the only reason to draw arcs at all.
    static let selectableDailyCounts = 1...12

    /// Normalizing initializer, so no caller can construct a degenerate case.
    /// Anything at or above 7 collapses to `.daily`; anything below 1 clamps up.
    init(timesPerWeek count: Int) {
        let clamped = min(max(count, Frequency.selectableCounts.lowerBound), Frequency.daysInWeek)
        self = clamped >= Frequency.daysInWeek ? .daily : .timesPerWeek(clamped)
    }

    /// The same guarantee for the per-day kind: clamped into `selectableDailyCounts`.
    ///
    /// Unlike the weekly initializer there is no value that collapses to another
    /// case. One a day is a real cadence with a real drawing — a single unbroken
    /// ring — rather than a degenerate one.
    init(timesPerDay count: Int) {
        self = .timesPerDay(
            min(
                max(count, Frequency.selectableDailyCounts.lowerBound),
                Frequency.selectableDailyCounts.upperBound
            )
        )
    }

    /// How many times a day, or nil when the habit is counted across a week.
    var dailyTarget: Int? {
        if case .timesPerDay(let count) = self { count } else { nil }
    }

    /// Counted within a day rather than across a week.
    var isCountedPerDay: Bool { dailyTarget != nil }

    /// How many slots the week row draws. A daily row is always the full week.
    ///
    /// **Nil for a per-day habit**, which has no week row at all — it is drawn
    /// as one ring on Today. Optional rather than a fallback number so that a
    /// caller reaching for a week has to say what it means when there isn't one,
    /// instead of quietly drawing seven of something.
    var slotCount: Int? {
        switch self {
        case .daily: Frequency.daysInWeek
        case .timesPerWeek(let count): count
        case .timesPerDay: nil
        }
    }

    /// How many completions in a week count as the goal met. Nil for a per-day
    /// habit, whose goal is met and reset within a single day.
    var weeklyTarget: Int? { slotCount }
}
