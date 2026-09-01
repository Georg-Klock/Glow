import Foundation

/// Whether a requested widget completion deserves an optimistic pop (#464).
///
/// This is deliberately answered from the snapshot *before* the intent writes.
/// The ring has already acknowledged the requested state through its AppIntent
/// toggle; putting the Island behind persistence would split one tap into a fast
/// acknowledgement and a late one.
enum OptimisticPop {
    static func shouldPresent(
        requestedDone: Bool,
        habit: HabitSnapshot,
        in week: Week,
        today: Date,
        level: PopPreferences.Level,
        calendar: Calendar = WeekCalendar.calendar
    ) -> Bool {
        // An undo is a correction, and a stale/duplicate request for a day the
        // snapshot already holds is not a new completion to celebrate.
        let day = WeekCalendar.day(today, calendar: calendar)
        guard requestedDone,
              !habit.isSpacer,
              week.contains(day),
              habit.count(on: day) == 0 else { return false }

        // Goals-only needs the answer the requested completion would produce,
        // not the pre-write total and not a persistence acknowledgement. Build
        // that one hypothetical row in a value snapshot; the store is untouched.
        var after = habit
        after.completionCounts[day] = 1
        let wouldMeetGoal = GoalMet.justMet(habit: after, in: week)
        return PopPreferences.allows(justMetGoal: wouldMeetGoal, at: level)
    }
}

/// Runs every newly submitted delivery immediately while guaranteeing that a
/// slower old delivery cannot leave old content behind (#464).
///
/// ActivityKit updates are asynchronous and do not promise to finish in call
/// order. Serialising them would make a rapid tap wait behind the slow update it
/// is replacing; merely launching tasks lets the older one finish last and win.
/// Each delivery therefore checks the latest generation after it returns. If it
/// became stale while suspended, it applies the newest operation and checks
/// again. The newest work is never queued behind the old task, and every old
/// task converges to it before exiting.
@MainActor
final class LatestPopDelivery {
    typealias Operation = @MainActor () async -> Void

    private struct Delivery {
        let generation: Int
        let operation: Operation
    }

    private var generation = 0
    private var latest: Delivery?
    private var inFlight = 0

    @discardableResult
    func submit(_ operation: @escaping Operation) -> Task<Void, Never> {
        generation &+= 1
        let delivery = Delivery(generation: generation, operation: operation)
        latest = delivery
        inFlight += 1

        return Task { @MainActor in
            await self.deliver(startingWith: delivery)
        }
    }

    private func deliver(startingWith first: Delivery) async {
        defer {
            inFlight -= 1
            // Keep the latest operation while any older delivery may still
            // need to repair itself to it. Release ActivityKit and content as
            // soon as the last in-flight delivery has converged.
            if inFlight == 0 { latest = nil }
        }

        var delivery = first
        while true {
            await delivery.operation()
            guard let latest, latest.generation != delivery.generation else { return }
            delivery = latest
        }
    }
}
