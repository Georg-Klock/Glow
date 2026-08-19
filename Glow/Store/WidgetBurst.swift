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
    static let hold: TimeInterval = 0.2
    static let fade: TimeInterval = 0.8
    static var duration: TimeInterval { hold + fade }

    /// Sampled at 10fps. Finer looks no better through a widget's snapshot
    /// pipeline and only makes the timeline longer.
    static let step: TimeInterval = 0.1

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
    /// Flat at 0 through the hold, then eased, so the glow is held for a beat
    /// before it is covered — the completion reads as an event rather than as
    /// the light simply going out.
    static func coverage(at elapsed: TimeInterval) -> Double {
        guard elapsed > hold else { return 0 }
        let t = min(max((elapsed - hold) / fade, 0), 1)
        // easeOut, matching the app's .easeOut on the same transition.
        return 1 - pow(1 - t, 2)
    }
}
