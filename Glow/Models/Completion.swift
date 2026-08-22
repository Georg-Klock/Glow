import Foundation
import SwiftData

/// One repetition of one habit on one day.
///
/// There is no "completed at" timestamp: the record is the day itself, always
/// normalized to midnight in the user's calendar by `WeekCalendar.day(_:)`.
/// Storing an instant instead would make two completions on the same day sort
/// and compare as different days, which is the bug this normalization prevents.
///
/// **There is no count field either, and that is the deliberate part.** A habit
/// done three times in a day is three of these, not one carrying a 3. Rows merge
/// when two devices sync; a counter is last-writer-wins, so two glasses of water
/// logged on a phone and a watch would come back as one. A weekly-cadence habit
/// simply never reaches two on the same day.
@Model
final class Completion {
    var id: UUID = UUID()
    var day: Date = Date.distantPast
    var habit: Habit?

    /// Which demo invented this row, and `nil` for every row a person logged.
    ///
    /// **Provenance lives on the row so it cannot disagree with the row.** The
    /// demo used to record what it had added as a list of ids in the App Group
    /// defaults, written after the completions were saved — two stores, two
    /// writes, and a gap between them in which a crash left durable invented
    /// history that nothing could identify or remove. Here the fact that a
    /// completion is invented is saved in the same transaction as the
    /// completion, so either both landed or neither did. See #140.
    ///
    /// A session id rather than a flag because it says *which* demo: the id is
    /// stable across one seeding, so a future question about a particular run
    /// has an answer. Removal does not need it — `DemoHistory` takes out
    /// everything with any session id — and that is deliberate, because it
    /// makes a half-finished seeding removable too.
    ///
    /// Optional with a `nil` default, like every other property here: the
    /// schema stays CloudKit-shaped, and an install that predates this column
    /// reads back as rows nobody invented, which is what they are.
    var demoSessionID: UUID?

    init(id: UUID = UUID(), day: Date, habit: Habit? = nil, demoSessionID: UUID? = nil) {
        self.id = id
        self.day = day
        self.habit = habit
        self.demoSessionID = demoSessionID
    }
}
