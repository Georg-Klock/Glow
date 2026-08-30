import SwiftUI

/// One slot, and the completion animation.
///
/// **One shape, one number, no cross-fade.** The open ring and the completed dot
/// are the same circle at two diameters: hold the stroke at 1.5pt and close the
/// ring, and its hole — diameter minus twice the stroke — reaches zero exactly
/// when the diameter reaches 3. The ring does not become a dot by fading into
/// one, it becomes a dot by closing.
///
/// It grows first. A press pushes it slightly past its resting size, and letting
/// go springs it shut past the dot and back — so a completion feels like
/// something snapping closed rather than a value being set.
///
/// Every other transition is instant. Un-completing especially: it is a
/// correction, and animating a correction dresses a mistake up as an
/// achievement.
struct SlotView: View {
    let slot: Slot
    let size: CGSize
    let habitName: String
    /// The calendar day this column stands for, or nil for a slot that is not
    /// day-pinned. Handed down by the row, which is what knows the week: a
    /// slot carries only the day a tap would *act* on, and six of the seven
    /// have none. See `SlotVoice`.
    var day: Date?
    let onToggle: (Date) -> Void

    /// A completion arriving is the only thing that moves here, and this is
    /// what switches it off. `MotionPolicy` holds the rule; the view holds the
    /// setting. See #137.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far past its resting size a press pushes the ring. Shared with the
    /// spanning rows, which do the same thing at a different shape.
    static let pressScale: CGFloat = 1.32

    /// The closing spring, and how long to hold the animating layer afterwards.
    ///
    /// Not private: the habit's label dims over exactly this, so the row reads
    /// as one movement rather than a mark that animates beside a label that
    /// snaps. Two timings for one event is two events.
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.58)
    static let closeDuration: Duration = .milliseconds(600)

    /// Non-nil only while a completion is closing. When it is nil the slot draws
    /// its resting truth and nothing else.
    @State private var closing: CGFloat?

    var body: some View {
        Group {
            if slot.isTappable {
                // **The hit area is the slot, not the ink** (#116). A `Button`
                // takes its label's drawn shape, and a ✕ is two 1pt bars — so
                // a past day was tappable only within about half a point of
                // the crossing, which reads as a slot that ignores you. It
                // never showed before, because until this change the only
                // tappable marks were the ring and the dot, both of which fill
                // their frame.
                Button { tap() } label: { mark.contentShape(Rectangle()) }
                    .buttonStyle(PressStyle(
                        scale: MotionPolicy.pressScale(Self.pressScale, reduceMotion: reduceMotion)
                    ))
            } else {
                mark
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: slot.state) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(slot.isTappable ? .isButton : [])
    }

    @ViewBuilder
    private var mark: some View {
        if let closing {
            // Mid-flight: the ring at whatever diameter it has reached, with its
            // stroke pinned to the resting width so the hole can close.
            GlowImageView(
                size: CGSize(width: closing, height: closing),
                shape: .ring,
                ringLineWidth: GlowShape.ringWeight
            )
        } else {
            SlotMarkView(mark: slot.mark, size: size, flattensSocket: true)
        }
    }

    /// The habit, the date this column is, and what the mark says — including
    /// the rest day's word, which is the only thing explaining a column that
    /// draws nothing (#72), and the date, which is the only thing saying which
    /// Tuesday a "missed" belongs to (#137). The weekday header carries it on
    /// screen and is hidden from VoiceOver, because seven letters over seven
    /// numbers is a table read aloud.
    private var accessibilityLabel: String {
        guard let day else { return "\(habitName), \(SlotVoice.state(slot.mark))" }
        return SlotVoice.label(habitName: habitName, mark: slot.mark, day: day)
    }

    private var accessibilityHint: String {
        guard slot.isTappable else { return "" }
        return SlotVoice.hint(isDone: slot.state == .filled)
    }

    private func tap() {
        guard let day = slot.actionDay else { return }
        onToggle(day)
    }

    /// Reduce Motion takes the same branch every other state change takes: the
    /// resting mark, immediately, with nothing scheduled behind it. A shorter
    /// spring would still be a spring.
    private func transition(from previous: SlotState, to next: SlotState) {
        guard MotionPolicy.closesCompletion(
            from: previous, to: next, reduceMotion: reduceMotion
        ) else {
            closing = nil
            return
        }

        closing = size.height
        withAnimation(Self.close) { closing = GlowShape.dotDiameter }

        // Hand back to the resting mark once it has settled. That mark is the
        // same glowing dot the animation ends on, so nothing moves at the
        // handover, and no animating layer is left alive behind a still one.
        Task {
            try? await Task.sleep(for: Self.closeDuration)
            if slot.state == .filled { closing = nil }
        }
    }
}

/// Grows on touch-down and springs back on release.
///
/// A `ButtonStyle` rather than a gesture, because this is exactly what the type
/// is for: it is handed `isPressed` and does not have to track touches, and it
/// keeps the button's own hit testing and accessibility intact.
struct PressStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
