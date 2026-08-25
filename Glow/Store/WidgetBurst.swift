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

    /// How late a reload may be and still animate.
    ///
    /// **This used to be `duration`, and that was one number doing two jobs**
    /// (#267). The fade's length and the note's lifetime are different
    /// questions and were only equal by accident, so reload latency came out
    /// of the animation: at 0.3s for both, a provider called 150ms after the
    /// tap played the back half of the fade, and one called later played none
    /// of it. Measured on an iPhone 14 Pro against real taps on a placed week
    /// widget, the week provider ran 431ms and 3.17s after the taps that
    /// asked for it — so at 0.3s *neither* recorded burst animated at all.
    ///
    /// Two seconds is chosen against that measurement rather than to cover it.
    /// It clears the fast path — the 133–180ms the simulator measures, and the
    /// 431ms the phone did — by more than 4x, so a fade that is lost now is
    /// lost to something worth calling a bug. It deliberately does **not**
    /// cover the multi-second case: that is #121, and a cross-fade played
    /// three seconds after the thumb left the glass is not a report of what
    /// just happened. The still frame is the honest render there.
    ///
    /// What `WidgetBurstTests.burstExpires` protects is untouched by the
    /// change. The guard exists so a midnight rollover or an edit made in the
    /// app cannot replay somebody's tap hours later, and two seconds is as
    /// unable to do that as 0.3 was. The number that must stay small is
    /// `duration`; this one only has to stay far below "later".
    static let maximumLag: TimeInterval = 2.0

    /// The cross-fade, as the still frames a timeline carries: evenly spaced,
    /// linear, done. Offset is from the *start of the fade*; progress is 0
    /// through 1, the dot's opacity and the ring's complement.
    ///
    /// Where the fade starts is `timeline(renderedAt:)`'s business, and since
    /// #267 it is the moment the provider ran rather than the moment of the
    /// tap.
    static var frames: [(offset: TimeInterval, progress: Double)] {
        let count = 3
        return (0..<count).map { i in
            let fraction = Double(i) / Double(count - 1)
            return (duration * fraction, fraction)
        }
    }


    /// The frames a provider should hand back, dated — the fade, then the
    /// settle.
    ///
    /// **Dated from `now`, not from the tap** (#267). The provider used to
    /// offset each frame from the moment the tap was recorded and skip the
    /// ones already spent, so reload latency was subtracted from the
    /// animation rather than merely delaying it: a provider called 150ms into
    /// a 300ms fade played its back half, and one called after 300ms played
    /// none of it. Latency is a property of WidgetKit's scheduling (#121) and
    /// nothing this app can shorten; what it can stop doing is charging the
    /// animation for it. Whether the fade is worth playing *at all* by then is
    /// `maximumLag`'s question, asked once in `pending(now:)`.
    ///
    /// A nil progress is the settled frame: no burst, nothing animating.
    /// Pure, and here rather than in the provider, because it is the decision
    /// and the provider is not testable — see docs/ARCHITECTURE.md.
    static func timeline(renderedAt now: Date) -> [(date: Date, progress: Double?)] {
        frames.map { (now.addingTimeInterval($0.offset), Optional($0.progress)) }
            + [(now.addingTimeInterval(duration), nil)]
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
    /// render time. For a note that survives at most `maximumLag` that is a
    /// distinction without a difference — and if anything the more honest of
    /// the two, since the tap is what the animation is about.
    static func record(habitID: UUID, at date: Date = Date(), reduceMotion: Bool) {
        store.set(habitID.uuidString, forKey: habitKey)
        store.set(date.timeIntervalSince1970, forKey: timeKey)
        store.set(reduceMotion, forKey: motionKey)
    }

    /// Whether the tap that left the note asked for less movement.
    static var reduceMotion: Bool { store.bool(forKey: motionKey) }

    /// Drops the note if it names this habit.
    ///
    /// **A note now outlives the fade it describes** (#267), and a note that
    /// outlives the state it describes is a widget animating a lie: tap to
    /// complete, tap again to undo before the provider has run, and the
    /// pending note would still cross-fade a ring into a dot for a slot the
    /// store has just reopened. At 0.3s that window was too short to reach;
    /// at `maximumLag` it is not.
    ///
    /// Only when the id matches, so undoing one habit does not swallow the
    /// fade another habit is owed.
    static func clear(habitID: UUID) {
        guard store.string(forKey: habitKey) == habitID.uuidString else { return }
        store.removeObject(forKey: habitKey)
        store.removeObject(forKey: timeKey)
        store.removeObject(forKey: motionKey)
    }

    /// The habit tapped within the last `maximumLag`, if there is one.
    ///
    /// Returns nil once the note has outlived `maximumLag`, so an ordinary
    /// reload — a midnight rollover, an edit in the app — renders a still
    /// widget rather than replaying somebody's last tap.
    static func pending(now: Date = Date()) -> (habitID: UUID, startedAt: Date)? {
        guard let raw = store.string(forKey: habitKey),
              let id = UUID(uuidString: raw)
        else { return nil }
        let stamp = store.double(forKey: timeKey)
        guard stamp > 0 else { return nil }
        let started = Date(timeIntervalSince1970: stamp)
        guard now.timeIntervalSince(started) < maximumLag else { return nil }
        return (id, started)
    }
}
