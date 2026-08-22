import ActivityKit
import Foundation

/// Requests the Dynamic Island's pop, and ends it.
///
/// One place, so no two callers can disagree about when it fires or how long it
/// lasts.
///
/// **Called from the intents only, never from the app's own taps** (#103). The
/// Island does not render a Live Activity while its own app is in the
/// foreground — measured: `Activity.request` succeeds, `chronod` subscribes an
/// Island renderer with the right metrics, and the Island stays a plain pill
/// until the app is backgrounded. So a goal met on Today or This Week used to
/// request an activity nobody could see and end it two seconds later, having
/// drawn its Lock Screen presentation for the bin.
///
/// Not harmful, but a feature whose entire content is two seconds on screen
/// should not have a path that spends them on nothing. The app has its own
/// acknowledgement and it is the right one: the ring closes, the label dims,
/// the row goes quiet. Putting something *else* on that screen would be a new
/// question, and one §3 was amended once already to allow this much.
///
/// The intents run in the app's process but not in its foreground — a widget
/// tap happens on the home screen, which is exactly where the pop is visible.
/// That is why the rule reads as "the intents" rather than as "the widget".
///
/// Every path in here fails quietly. A pop is the least important thing the app
/// does — a habit is logged whether or not the Island says so — and an error
/// path that surfaced would be a worse bug than the missing two seconds.
@MainActor
enum GoalPopCentre {
    /// Fire, if the goal was just met and the switch is on.
    ///
    /// Takes the verdict rather than computing it: `GoalMet` is pure and
    /// testable, and the callers already know what they just wrote.
    ///
    /// Both callers are intents. See the note on the type before adding a
    /// third from a view.
    static func popIfMet(
        habit: HabitSnapshot,
        in week: Week,
        today: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) {
        guard PopPreferences.isEnabled,
              GoalMet.justMet(habit: habit, in: week, today: today, calendar: calendar)
        else { return }
        pop(habitID: habit.id, name: habit.name, on: today, calendar: calendar)
    }

    private static func pop(
        habitID: UUID, name: String, on day: Date, calendar: Calendar
    ) {
        // Live Activities can be switched off system-wide, per app, and are
        // unavailable on some devices. All three arrive here as the same
        // answer, and the answer is to do nothing.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = GoalPopAttributes.ContentState(
            habitName: name,
            line: GoalPop.line(habitID: habitID, on: day, calendar: calendar)
        )
        do {
            let activity = try Activity.request(
                attributes: GoalPopAttributes(habitID: habitID.uuidString),
                content: ActivityContent(state: state, staleDate: nil)
            )
            GlowLog.widget.notice("pop: \(state.line, privacy: .public)")
            // A session that ends almost immediately, which is what a pop is.
            // Dismissed rather than left to the system's own timeout, or it
            // would sit on the Lock Screen as a notification-shaped thing.
            //
            // Ended by id rather than by holding the activity across the await:
            // `Activity` is not `Sendable`, and sending one into a detached
            // task is a data race the compiler is right about.
            let id = activity.id
            Task { @MainActor in
                try? await Task.sleep(for: GoalPop.duration)
                for live in Activity<GoalPopAttributes>.activities where live.id == id {
                    await live.end(nil, dismissalPolicy: .immediate)
                }
            }
        } catch {
            // Nothing to report and nothing to retry.
            GlowLog.widget.notice("pop: refused by ActivityKit")
        }
    }
}
