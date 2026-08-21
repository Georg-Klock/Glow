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

    init(id: UUID = UUID(), day: Date, habit: Habit? = nil) {
        self.id = id
        self.day = day
        self.habit = habit
    }
}
