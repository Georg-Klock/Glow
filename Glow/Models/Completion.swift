import Foundation
import SwiftData

/// One habit done on one day.
///
/// There is no "completed at" timestamp and no count. A habit is done or not
/// done for a given day, so the record is the day itself, always normalized to
/// midnight in the user's calendar by `WeekCalendar.day(_:)`. Storing an instant
/// instead would make two completions on the same day compare unequal, which is
/// the bug this normalization exists to prevent.
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
