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

    /// How long the burst runs. Matches SlotView's completion transition: a
    /// beat at full glow, then the solid fill rising over it.
    static let hold: TimeInterval = 0.06
    static let fade: TimeInterval = 0.4
    static var duration: TimeInterval { hold + fade }

    /// The app's spring, as numbers this file can evaluate.
    ///
    /// `SlotView.close` is `.spring(response: 0.34, dampingFraction: 0.58)`. A
    /// widget cannot run a spring — it is handed still frames — so the curve is
    /// sampled instead of animated, and these are the same two values that
    /// SwiftUI would have used. The overshoot matters: without it the ring eases
    /// politely shut in the widget while it snaps in the app, and the two read
    /// as different gestures.
    static let response: Double = 0.34
    static let damping: Double = 0.58

    /// Sampled at 40fps.
    ///
    /// It was 10, on the reasoning that finer looked no better through a
    /// snapshot pipeline. It does: at 10fps across a second the close reads as a
    /// handful of stills rather than a movement. The cost of more is nothing —
    /// **entries inside a timeline are free, only reloads are budgeted**, and
    /// this whole burst rides inside the reload a tap already paid for.
    static let step: TimeInterval = 0.025

    private static var store: UserDefaults { GlowSettings.store }

    static func record(habitID: UUID, at date: Date = Date()) {
        store.set(habitID.uuidString, forKey: habitKey)
        store.set(date.timeIntervalSince1970, forKey: timeKey)
    }

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

    /// How far the solid fill has risen over the glow, 0 through 1.
    ///
    /// How far through the close this frame is, 0 through 1 and briefly past it.
    ///
    /// Flat at 0 through the hold, then a damped spring — the same one the app
    /// runs, evaluated rather than animated. It **overshoots past 1**, which is
    /// the point: the ring closes past the dot and settles back, and a caller
    /// mapping this onto a diameter gets the snap rather than a fade.
    static func coverage(at elapsed: TimeInterval) -> Double {
        guard elapsed > hold else { return 0 }
        let t = elapsed - hold
        guard t < fade else { return 1 }

        // Standard second-order step response. omega is the undamped frequency
        // SwiftUI derives from `response`; omegaD is what is left after damping.
        let omega = 2 * Double.pi / response
        let zeta = damping
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        return 1 - decay * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
    }
}
