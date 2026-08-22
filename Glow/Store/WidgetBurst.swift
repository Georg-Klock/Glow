import Foundation

/// The handshake that lets the widget animate a tap without spending anything.
///
/// A widget cannot run a continuous animation, and paying for one out of the
/// daily reload allowance is not worth it (see docs/glow.md). But a tap already
/// costs a reload: `ToggleHabitIntent` writes to the store and asks WidgetKit
/// for a new timeline. That timeline can carry a second's worth of entries
/// before it settles, so the completion animates for free.
///
/// This type is the note the intent leaves for the provider: which habit was
/// tapped, and when.
enum WidgetBurst {
    private static let habitKey = "burstHabitID"
    private static let timeKey = "burstAt"
    private static let motionKey = "burstReduceMotion"

    /// How long the cross-fade runs.
    ///
    /// This used to sample the app's closing spring — `response: 0.34,
    /// dampingFraction: 0.58`, evaluated as a second-order step response at
    /// 40fps, roughly seventeen entries — so the widget would read as the
    /// app's snap. On a real home screen it did not: timeline entries do not
    /// arrive at the rate they were sampled at, and a curve played back at
    /// the wrong rate is not the curve — it is a stutter. Sampling a spring
    /// assumes the render clock is ours to spend, and it is not.
    ///
    /// So the widget's completion is now the honest version of what a widget
    /// is — a few stills: the ring fades out as the dot fades in, then it is
    /// over. The app's `SlotView` keeps its spring, so the two surfaces read
    /// as different gestures for the same act, which is accepted: a gesture
    /// that reads wrong is worse than one that reads different. See
    /// docs/glow.md.
    static let duration: TimeInterval = 0.3

    /// The cross-fade, as the still frames a timeline carries: evenly spaced,
    /// linear, done. Offset is from the tap; progress is 0 through 1, the dot's
    /// opacity and the ring's complement.
    static var frames: [(offset: TimeInterval, progress: Double)] {
        let count = 3
        return (0..<count).map { i in
            let fraction = Double(i) / Double(count - 1)
            return (duration * fraction, fraction)
        }
    }

    private static var store: UserDefaults { GlowSettings.store }

    /// Leaves the note, and with it whether the person has asked for less
    /// movement.
    ///
    /// **Reduce Motion is captured here rather than read by the provider**, and
    /// the reason is isolation rather than convenience.
    /// `UIAccessibility.isReduceMotionEnabled` is main-actor isolated;
    /// `TimelineProvider` is not, and reading it there is a strict-concurrency
    /// warning the compiler is right about. The intent that calls this *is*
    /// `@MainActor`, so the value is read where it is genuinely safe to read
    /// and travels with the note.
    ///
    /// It also samples the setting at the moment of the tap rather than at
    /// render time, which for a note that expires in 0.3s is a distinction
    /// without a difference — and if anything the more honest of the two.
    static func record(habitID: UUID, at date: Date = Date(), reduceMotion: Bool) {
        store.set(habitID.uuidString, forKey: habitKey)
        store.set(date.timeIntervalSince1970, forKey: timeKey)
        store.set(reduceMotion, forKey: motionKey)
    }

    /// Whether the tap that left the note asked for less movement.
    static var reduceMotion: Bool { store.bool(forKey: motionKey) }

    /// The habit tapped within the last `duration`, if there is one.
    ///
    /// Returns nil once the burst has expired, so an ordinary reload — a
    /// midnight rollover, an edit in the app — renders a still widget rather
    /// than replaying somebody's last tap.
    static func pending(now: Date = Date()) -> (habitID: UUID, startedAt: Date)? {
        guard let raw = store.string(forKey: habitKey),
              let id = UUID(uuidString: raw)
        else { return nil }
        let stamp = store.double(forKey: timeKey)
        guard stamp > 0 else { return nil }
        let started = Date(timeIntervalSince1970: stamp)
        guard now.timeIntervalSince(started) < duration else { return nil }
        return (id, started)
    }
}
