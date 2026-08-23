import Foundation
import SwiftData

/// One repetition of one habit on one day.
///
/// There is no "completed at" timestamp: the record is the day itself. Storing
/// an instant instead would make two completions on the same day sort and
/// compare as different days, which is the bug that normalization prevents.
///
/// **Which day it is, is `dayKey`, not `day`** (#130). A local midnight is a
/// different instant in every zone, so `day` alone said 19 August in Berlin and
/// 18 August in Los Angeles about the same row. `dayKey` carries the civil date
/// as text and settles it; `day` stays exactly as it was written and is never
/// rewritten, because it is the only evidence a later build would have if this
/// one read a legacy row wrong. See `DayID`.
///
/// **There is no count field either, and that is the deliberate part.** A habit
/// done three times in a day is three of these, not one carrying a 3. Rows merge
/// when two devices sync; a counter is last-writer-wins, so two glasses of water
/// logged on a phone and a watch would come back as one. A weekly-cadence habit
/// simply never reaches two on the same day.
@Model
final class Completion {
    var id: UUID = UUID()

    /// The instant this row was normalized to when it was written: midnight of
    /// `dayKey` in whatever zone the phone was in.
    ///
    /// **Kept, and never rewritten.** It is no longer what identifies the day —
    /// `dayKey` is — but it is the original observation, and the backfill that
    /// gave old rows a `dayKey` had to infer one from exactly this. Rewriting it
    /// would destroy the only thing a better inference could ever run against,
    /// which on a history somebody has kept for a year is not a recoverable
    /// mistake. See `DayID.recovered(fromLegacyMidnight:)` and #130.
    var day: Date = Date.distantPast

    /// The civil day, as `yyyy-MM-dd`. **This is the identity.**
    ///
    /// Text rather than a `Date` so that no zone can be applied to it, and
    /// zero-padded so it sorts and groups as itself. Empty on every row written
    /// before this column existed; `dayID` is what reads it, and it answers for
    /// those rows too rather than making every call site remember.
    ///
    /// Non-optional with a default, like `name` and `timesPerDay`: the schema
    /// stays CloudKit-shaped, and a row that predates the column reads back as
    /// the empty string, which is precisely "this row has not been told yet".
    var dayKey: String = ""

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

    init(
        id: UUID = UUID(),
        day: Date,
        habit: Habit? = nil,
        demoSessionID: UUID? = nil,
        calendar: Calendar = WeekCalendar.calendar
    ) {
        self.id = id
        self.day = day
        self.dayKey = DayID(day, calendar: calendar).text
        self.habit = habit
        self.demoSessionID = demoSessionID
    }

    /// Which day this row belongs to, for every reader.
    ///
    /// Derived on a legacy row rather than left blank, so a store that has not
    /// been through the backfill — or is half-way through one, or is being read
    /// by the widget's read-only container which cannot write at all — answers
    /// exactly the same as one that has. **The backfill is therefore not
    /// load-bearing**: it writes down an answer that is already being given, so
    /// failing it, interrupting it or running it twice all show the same
    /// history. See `StoreMigration.stampDayIdentities`.
    var dayID: DayID {
        DayID(dayKey) ?? DayID.recovered(fromLegacyMidnight: day)
    }
}
