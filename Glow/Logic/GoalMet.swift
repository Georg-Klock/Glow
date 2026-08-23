import Foundation

/// Whether a write just met a habit's goal.
///
/// **The goal, not each repetition** — this type's own question, which is no
/// longer the same as "when does the Island speak". The twelfth glass of water,
/// not each of the twelve; the week's second run, not both of them.
///
/// This paragraph used to continue: "that is what keeps the moment rare enough
/// to mean anything — firing on every completion would put twenty of these a
/// day on a screen whose whole argument is that it says one thing." **That was
/// overturned in #119**, and it is kept rather than deleted because it is the
/// argument anyone will re-derive from first principles.
///
/// What it got wrong is the screen. A pop is not on the screen whose argument
/// is that it says one thing — it is two seconds over the Dynamic Island, on
/// the home screen, and it leaves nothing behind. How often a person wants to
/// be spoken to there is a preference, and it is a three-way switch now:
/// never, goals, everything. What this type answers is still only *was this
/// the write that got there*, which is what the goal register is chosen by.
///
/// Exactly met, not met-or-past. A fourth completion on a three-a-week habit is
/// past the goal and fires nothing: the goal was already met, and it was met
/// once. That also removes the need to know what the count was before the
/// write — if it equals the target now, this write is the one that got there.
///
/// Pure, per the `WeekGrid` / `SlotLayout` pattern.
enum GoalMet {
    /// The goal a habit is counted against, and over what.
    static func target(of frequency: Frequency) -> Int {
        switch frequency {
        case .daily: Frequency.daysInWeek
        case .timesPerWeek(let n): n
        }
    }

    /// True when this habit's count has just reached its goal exactly.
    ///
    /// Everything counts the week — a daily habit included, whose goal is a
    /// perfect seven. The per-day branch that counted a single day went with the
    /// kind it served (#209), and `today` and `calendar` went with it: they were
    /// only ever read to find *which* day to count, and the week is now the only
    /// window there is. A parameter nothing reads is a parameter a caller can
    /// pass wrong for years without finding out.
    static func justMet(habit: HabitSnapshot, in week: Week) -> Bool {
        guard !habit.isSpacer else { return false }
        let goal = target(of: habit.frequency)
        guard goal > 0 else { return false }

        return habit.completedDays.count { week.contains($0) } == goal
    }
}
