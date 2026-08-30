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
        let met = GoalMet.justMet(habit: habit, in: week)
        // One rule, shared with the app's own pop — see `PopPreferences.allows`.
        guard PopPreferences.allows(justMetGoal: met) else { return }

        // **One pop, and this is the whole of "never fires twice"** (#420).
        // A goal-completing tap used to pop the routine line here and then
        // replace it with the goal's after `GoalPop.handover`, sharing the two
        // seconds. There is one pool now, so there is one line, and the second
        // request that made this the only double-fire in the app is gone.
        pop(habitID: habit.id, name: habit.name, on: today, calendar: calendar)
    }

    /// The number of the most recent pop. See `PopWindow`.
    private static var latest = 0

    private static func pop(
        habitID: UUID, name: String, on day: Date, calendar: Calendar
    ) {
        // Live Activities can be switched off system-wide, per app, and are
        // unavailable on some devices. All three arrive here as the same
        // answer, and the answer is to do nothing.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(
            state: GoalPopAttributes.ContentState(
                habitName: name,
                line: GoalPop.line(habitID: habitID, on: day, calendar: calendar)
            ),
            staleDate: nil
        )
        latest += 1
        let mine = latest

        // **One activity, whose words change.** Two goals met inside the pop's
        // two seconds is not an edge case — the medium Today widget puts three
        // rings side by side precisely so they can be tapped in a flurry.
        //
        // Requesting a second activity was measured (#102): ActivityKit allows
        // it, both run, and the Island renders only the newest. So the first
        // habit's line was drawn, immediately hidden, and ended on a timer
        // nobody saw start. Updating says the same thing on screen with one
        // session and one timer, and it makes the outcome this app's decision
        // rather than a side effect of how the Island stacks.
        if let running = Activity<GoalPopAttributes>.activities.first {
            let id = running.id
            Task { @MainActor in
                for live in Activity<GoalPopAttributes>.activities where live.id == id {
                    await live.update(content)
                }
            }
            GlowLog.widget.notice("pop: \(content.state.line, privacy: .public) (replacing)")
        } else {
            do {
                _ = try Activity.request(
                    attributes: GoalPopAttributes(), content: content
                )
                GlowLog.widget.notice("pop: \(content.state.line, privacy: .public)")
            } catch {
                // Nothing to report and nothing to retry.
                GlowLog.widget.notice("pop: refused by ActivityKit")
                return
            }
        }

        // A session that ends almost immediately, which is what a pop is.
        // Dismissed rather than left to the system's own timeout, or it would
        // sit on the Lock Screen as a notification-shaped thing.
        //
        // Guarded by `PopWindow`: with one shared activity, the first tap's end
        // would otherwise land two seconds after *its* tap and cut short a pop
        // the second goal had just refreshed.
        Task { @MainActor in
            try? await Task.sleep(for: GoalPop.duration)
            guard PopWindow.shouldEnd(scheduled: mine, latest: latest) else { return }
            for live in Activity<GoalPopAttributes>.activities {
                await live.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
