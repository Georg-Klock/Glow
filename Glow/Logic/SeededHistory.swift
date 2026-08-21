import Foundation

/// The invented past behind the demo-history toggle in Settings.
///
/// **This is invented history, and that is a real cost.** A tracker that opens
/// showing a streak you did not earn is lying to you on the first screen. It
/// exists because an empty grid shows none of what the app is for — no streak,
/// no run of light, no shape to a week — and judging the design against a
/// blank slate is judging a different app.
///
/// So it is asked for, never assumed: no install seeds it on first launch, and
/// `DemoHistory` puts it in and takes exactly it back out when the toggle
/// moves. See docs/decisions.md.
///
/// Deterministic on purpose. Each habit's past is generated from a fixed
/// per-habit seed, so toggling the demo off and on rebuilds the same days and
/// the tests can assert against it.
enum SeededHistory {
    /// How far back the invented past runs.
    static let weeks = 10

    /// A tiny linear congruential generator.
    ///
    /// `SystemRandomNumberGenerator` would make the seed different on every
    /// install, which defeats the point — this is demo content and it should be
    /// the same demo every time. The constants are Numerical Recipes'.
    struct Generator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    /// The shape of a habit's past, by its position in the list.
    ///
    /// The first habit is perfect, because a full streak is the thing the demo
    /// most needs on screen; the rest cycle down to patchy so a missed day is
    /// on screen too. Position rather than anything about the habit itself, so
    /// the variety survives renames and edits.
    static func form(at position: Int) -> Form {
        let cycle: [Form] = [.perfect, .strong, .steady, .uneven]
        return cycle[((position % cycle.count) + cycle.count) % cycle.count]
    }

    /// A stable per-habit seed, from the habit's own id, so switching the demo
    /// off and on rebuilds the same past for the same habit.
    static func seed(for id: UUID) -> UInt64 {
        let b = id.uuid
        return UInt64(b.0) << 56 | UInt64(b.1) << 48 | UInt64(b.2) << 40
            | UInt64(b.3) << 32 | UInt64(b.4) << 24 | UInt64(b.5) << 16
            | UInt64(b.6) << 8 | UInt64(b.7)
    }

    /// How a habit has been going.
    enum Form {
        /// Never missed. One of these is what makes a full streak visible.
        case perfect
        /// Nearly always, the odd day off.
        case strong
        /// More often than not.
        case steady
        /// Patchy, but not a write-off.
        case uneven

        /// The chance a given expected day was completed.
        var rate: Double {
            switch self {
            case .perfect: 1.0
            case .strong: 0.9
            case .steady: 0.78
            case .uneven: 0.62
            }
        }
    }

    /// The days to mark complete for one habit, newest week last.
    ///
    /// Today is left alone. The open slot is the one thing the app is *for*, and
    /// a seed that filled it would hide the feature on first launch.
    static func completions(
        for frequency: Frequency,
        form: Form,
        seed: UInt64,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [Date] {
        var generator = Generator(seed: seed)
        var days: [Date] = []

        // Whole weeks back from the start of this one, then this week up to
        // yesterday — so the current week is partially filled, which is what a
        // real Thursday looks like.
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -7 * weeks,
            to: WeekCalendar.startOfWeek(containing: today, calendar: calendar)
        ) else { return [] }

        switch frequency {
        case .daily:
            var day = firstDay
            while day < today {
                let isRest = WeekPreferences.isRestDay(day, calendar: calendar)
                if !isRest, Double.random(in: 0..<1, using: &generator) < form.rate {
                    days.append(day)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

        case .timesPerWeek(let target):
            // Filled per week rather than per day: the goal is a count, so the
            // history has to be a count too or a "3 times a week" habit ends up
            // with six completions in one week and none in the next.
            var weekStart = firstDay
            while weekStart < today {
                let week = WeekCalendar.week(containing: weekStart, calendar: calendar)
                let hit = Double.random(in: 0..<1, using: &generator) < form.rate
                let wanted = hit ? target : max(0, target - 1)

                // Shuffle the week's days with the same generator, so which days
                // a completion landed on is arbitrary but reproducible.
                for day in week.days.shuffled(using: &generator).prefix(wanted) where day < today {
                    days.append(day)
                }
                guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
                weekStart = next
            }

        case .timesPerDay(let target):
            // The one kind that returns a day more than once: a habit done four
            // times on Tuesday is four entries for Tuesday, because that is how
            // it is stored. A day that fell short gets fewer, never more — an
            // overshoot would draw a ring past full.
            var day = firstDay
            while day < today {
                let hit = Double.random(in: 0..<1, using: &generator) < form.rate
                let count = hit ? target : Int.random(in: 0...target, using: &generator)
                days.append(contentsOf: repeatElement(day, count: count))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return days
    }
}
