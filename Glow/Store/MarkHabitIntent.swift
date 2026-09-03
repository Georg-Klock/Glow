import AppIntents
import Foundation
import UIKit
import SwiftData
import WidgetKit

/// Marks the widget's chosen day done, or undoes it.
///
/// **It sets, it does not toggle, and the name says so** (#272, #292). It was
/// `ToggleHabitIntent` and it flipped whatever the store held. A widget is the
/// wrong surface for a relative operation: its pixels lag the store, and a
/// single tap has been measured performing this intent *twice*, 13ms apart, on
/// an iPhone 14 Pro. Both failures produced the same complaint — checking
/// habits off quickly un-does them — and both are answered by carrying the
/// state the rendered control asked for. See `HabitStore.setCompletion`.
///
/// This is what makes the widget worth having: the whole product claim is that
/// logging a habit is one tap, and a widget you have to open the app from is
/// two taps and a launch.
///
/// **`LiveActivityIntent`, not plain `AppIntent`** (#58). ActivityKit will not
/// start an activity from a widget extension, and this intent has to be able to
/// — logging from the home screen is the *only* case the pop is visible in, for
/// a measured reason: the Dynamic Island does not render an activity while its
/// own app is in the foreground.
///
/// The conformance moves this intent into the app's process. It does **not**
/// bring the app forward, which is the property that had to be measured rather
/// than assumed: the whole point of this intent is that it never leaves the home
/// screen, and that is still true.
struct MarkHabitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Habit"
    static let description = IntentDescription("Marks a widget slot done, or undoes it.")

    /// Deliberately not `openAppWhenRun`. The point is to never leave the home
    /// screen — and `LiveActivityIntent` does not change that: it runs the
    /// intent in the app's process without bringing the app to the foreground.
    static let openAppWhenRun = false

    @Parameter(title: "Habit")
    var habitID: String

    /// The state the tapped mark was *asking for*, not the state the store is
    /// believed to hold.
    ///
    /// The call sites pass the complement of what they drew: a ring means
    /// "make this done", a dot means "make it not done". That is what makes a
    /// second delivery harmless — it asks for the same thing again.
    @Parameter(title: "Done")
    var done: Bool

    /// The civil day the rendered control acts on. Optional so a control
    /// archived by an older build fails closed and asks for a fresh timeline
    /// instead of silently falling back to today (#508).
    @Parameter(title: "Day")
    var day: Date?

    /// What the archived surface believed "today" was. A midnight rollover
    /// makes that surface stale; carrying this separately lets the operation
    /// refuse it rather than writing yesterday after the day has changed.
    @Parameter(title: "Rendered Day")
    var renderedDay: Date?

    /// Whether this archived control lives where the Island can be seen.
    /// Installed widgets pass true; the same control hosted inside Glow's
    /// Widgets tab passes false (#465). The app keeps its own foreground pop.
    @Parameter(title: "Present Island Encouragement")
    var presentsIsland: Bool

    init() {}

    init(
        habitID: UUID,
        done: Bool,
        day: Date,
        renderedDay: Date,
        presentsIsland: Bool = true
    ) {
        self.habitID = habitID.uuidString
        self.done = done
        self.day = day
        self.renderedDay = renderedDay
        self.presentsIsland = presentsIsland
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }

        let container = try GlowStore.makeContainer()
        let context = ModelContext(container)
        try MarkHabitOperation.perform(
            habitID: id,
            done: done,
            day: day,
            renderedDay: renderedDay,
            presentsIsland: presentsIsland,
            context: context
        )
        return .result()
    }
}

/// The absolute-state mark operation shared by WidgetKit's AppIntent adapter
/// and the binding-backed control hosted inside Glow (#477).
///
/// The two surfaces differ only in how SwiftUI delivers a requested state.
/// Both arrive here with that absolute state, then use the same bounded lookup,
/// store contract, reconciliation signal, burst note and widget invalidation.
/// Keeping the already-live app `ModelContext` at the boundary also lets hosted
/// tests exercise the production operation without redirecting the App Group.
@MainActor
enum MarkHabitOperation {
    @discardableResult
    static func perform(
        habitID id: UUID,
        done: Bool,
        day: Date?,
        renderedDay: Date?,
        presentsIsland: Bool,
        actualToday: Date = WeekCalendar.today(),
        calendar: Calendar = WeekCalendar.calendar,
        restDay: Int? = WeekPreferences.restDay,
        context: ModelContext
    ) throws -> HabitStore.ToggleOutcome? {
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })

        // Reconcile even when a once-valid archived control outlives its habit,
        // or when persistence throws. The optimistic face must never become a
        // new source of truth merely because there was no verdict to draw.
        defer {
            NotificationCenter.default.post(name: StoreChange.fromIntent, object: nil)
            WidgetRefresh.invalidate()
        }

        let request = WidgetMarkRequest(day: day, renderedDay: renderedDay)
        guard let actionDay = request.resolvedDay(
            actualToday: actualToday, calendar: calendar
        ) else {
            WidgetBurst.clear(habitID: id)
            let outcome = "tap \(id.uuidString) [\(WidgetTrace.origin)]: refused, stale day; burst skipped"
            GlowLog.widget.notice("\(outcome, privacy: .public)")
            WidgetTrace.record(outcome)
            return nil
        }

        guard let habit = try context.fetch(descriptor).first else { return nil }

        // The ring has already flipped optimistically. Give the Island the
        // same timing: decide from the bounded pre-write snapshot and launch
        // the eligible pop before persistence (#464). An undo or a day this
        // snapshot already holds is silent; a refusal after this point is the
        // accepted rollback cost of optimistic acknowledgement.
        let week = WeekCalendar.week(containing: actionDay, calendar: calendar)
        if presentsIsland {
            GoalPopCentre.popIfRequestedCompletion(
                requestedDone: done,
                habit: habit.snapshot(within: week.dayIDs(in: calendar), calendar: calendar),
                in: week,
                today: actionDay,
                calendar: calendar
            )
        }

        let result = try HabitStore(context: context, calendar: calendar, restDay: restDay)
            .setCompletion(for: habit, on: actionDay, done: done)

        // A tap already costs a timeline reload, so the completion can animate
        // inside the timeline that reload produces. This is the note the
        // provider reads. Only completing animates; un-completing is a
        // correction and a refusal is nothing at all — neither is celebrated.
        //
        // A refusal can genuinely arrive here: this process runs against a
        // surface that may have been rendered before the rest day was set, so
        // a stale widget can offer a button the store will not honour. The
        // store's answer wins, and the reload below replaces the stale surface.
        if result == .completed {
            // Read here, on the main actor, and carried with the note — see
            // `WidgetBurst.record`.
            WidgetBurst.record(
                habitID: id,
                day: actionDay,
                calendar: calendar,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
        } else {
            // Anything that is not a completion drops this habit's note, if it
            // is still holding one (#267). A note now outlives its fade, so an
            // undo landing before the provider has run would otherwise leave a
            // cross-fade queued for a slot the store has just reopened — the
            // widget animating a completion being taken back. Scoped to this
            // habit, so undoing one does not swallow the fade another is owed.
            WidgetBurst.clear(habitID: id)
        }

        let verdict = switch result {
        case .completed: "done"
        case .uncompleted: "undone"
        // The idempotent no-op, and worth its own word in the trace: a
        // duplicate delivery and a stale surface both land here, and neither
        // used to be distinguishable from a real write (#272).
        case .unchanged: "already \(done ? "done" : "undone")"
        case .refused: "refused, rest day"
        }
        // The origin is here and not on every line (#272): a single tap has
        // been seen performing this intent twice, 13ms apart, and what the
        // trace could not say was whether that was one process or two.
        let dayID = DayID(actionDay, calendar: calendar)
        let outcome = "tap \(id.uuidString) on \(dayID.text) [\(WidgetTrace.origin)]: \(verdict), burst \(result == .completed ? "recorded" : "skipped")"
        GlowLog.widget.notice("\(outcome, privacy: .public)")
        WidgetTrace.record(outcome)

        return result
    }
}

/// Resolves an archived control's requested day without trusting stale pixels.
struct WidgetMarkRequest: Equatable, Sendable {
    let day: Date?
    let renderedDay: Date?

    func resolvedDay(
        actualToday: Date,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Date? {
        guard let day, let renderedDay else { return nil }
        let actual = DayID(actualToday, calendar: calendar)
        let surface = DayID(renderedDay, calendar: calendar)
        guard surface == actual else { return nil }

        let requested = DayID(day, calendar: calendar)
        guard requested <= actual else { return nil }

        // The week widget only creates controls for the seven days it drew.
        // Holding this boundary here also makes a manually invoked or corrupt
        // intent fail closed instead of becoming an arbitrary history writer.
        let renderedWeek = WeekCalendar.week(containing: renderedDay, calendar: calendar)
        guard renderedWeek.dayIDs(in: calendar).contains(requested) else { return nil }
        return requested.date(in: calendar)
    }
}
