import AppIntents
import SwiftUI

/// A widget mark that draws the state it just asked for (#292).
///
/// This is the other half of `MarkHabitIntent` carrying `done`. The intent made
/// a tap idempotent, but the pixels still waited on WidgetKit: the tap wrote
/// the store in tens of milliseconds and the mark held its old shape until the
/// provider ran and the new timeline was composited — measured at 431ms and
/// 3.17s on an iPhone 14 Pro (#121). A person who taps and sees nothing taps
/// again, which is the flurry #272 traced.
///
/// The one mechanism WidgetKit offers for pixels that do not wait is an
/// AppIntent-backed `Toggle`: the system updates its appearance *optimistically*
/// while `perform()` is still running, provided the style renders
/// `configuration.isOn` rather than anything captured from the entry. So the
/// mark is a `Toggle`, its two faces are the two marks this control can be, and
/// the system flips between them at the tap. The guaranteed reload then
/// reconciles to the store's answer — which, on a refusal (a stale surface
/// offering a rest day, a deleted habit), is how an optimistic flip is taken
/// back.
///
/// **`isOn` is the rendered state, so the intent asks for its complement** —
/// exactly the contract `MarkHabitIntent.done` was built around: a ring means
/// "make this done", a dot means "make it not done", and a duplicate delivery
/// asks for the same thing twice.
///
/// The two faces arrive as views rather than as `SlotMark`s because the three
/// call sites disagree about what a face is: a week slot's completed face
/// carries the burst cross-fade, a span's faces carry its width and its rest
/// window, and the month's are plain marks. What this type owns is the part
/// they must not each reinvent: the toggle, the style that makes it optimistic,
/// and a spoken label and hint that follow `configuration.isOn` — so VoiceOver
/// agrees with the optimistic pixels, not with the snapshot they outran.
struct SlotToggle<OnMark: View, OffMark: View>: View {
    private let habitID: UUID
    private let isDone: Bool
    private let onLabel: String
    private let offLabel: String
    private let onMark: OnMark
    private let offMark: OffMark

    init(
        habitID: UUID,
        isDone: Bool,
        onLabel: String,
        offLabel: String,
        @ViewBuilder onMark: () -> OnMark,
        @ViewBuilder offMark: () -> OffMark
    ) {
        self.habitID = habitID
        self.isDone = isDone
        self.onLabel = onLabel
        self.offLabel = offLabel
        self.onMark = onMark()
        self.offMark = offMark()
    }

    var body: some View {
        Toggle(isOn: isDone, intent: MarkHabitIntent(habitID: habitID, done: !isDone)) {
            // Never drawn: the style below draws the mark and ignores its
            // label, and what VoiceOver reads is the style's own
            // `accessibilityLabel`, which is the one that can follow `isOn`.
            EmptyView()
        }
        .toggleStyle(SlotMarkToggleStyle(
            onMark: onMark, offMark: offMark, onLabel: onLabel, offLabel: offLabel
        ))
    }
}

/// Renders `configuration.isOn` and nothing captured beside it.
///
/// That property is load-bearing, not stylistic: WidgetKit's optimistic update
/// works by flipping `isOn` under the style before the intent has run, so a
/// style that keys off the entry's own state — the way the old `Button` label
/// did — draws the stale mark either way and the optimism buys nothing. Both
/// faces must therefore be resolvable from the archived view, which they are:
/// they are built from the entry and chosen by `isOn`.
private struct SlotMarkToggleStyle<OnMark: View, OffMark: View>: ToggleStyle {
    let onMark: OnMark
    let offMark: OffMark
    let onLabel: String
    let offLabel: String

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if configuration.isOn {
                onMark
            } else {
                offMark
            }
        }
        // Spoken from `isOn`, same as drawn from it, so the announcement and
        // the pixels cannot disagree during the optimistic window. The system
        // adds the toggle's own on/off value from the same bit. Reduce Motion
        // changes none of this: the flip is a state change, not motion, so the
        // acknowledgement survives it — the burst is what Reduce Motion skips,
        // and that is the provider's business (`WidgetBurst`).
        .accessibilityLabel(configuration.isOn ? onLabel : offLabel)
        .accessibilityHint(SlotVoice.hint(isDone: configuration.isOn))
    }
}
