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
    let onToggle: (Date) -> Void

    /// How far past its resting size a press pushes the ring.
    private static let pressScale: CGFloat = 1.32

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
                Button { tap() } label: { mark }
                    .buttonStyle(PressStyle(scale: Self.pressScale))
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
                ringLineWidth: size.height * GlowShape.ringWeight
            )
        } else {
            SlotMarkView(mark: slot.mark, size: size)
        }
    }

    private var accessibilityLabel: String {
        let state = switch slot.mark {
        case .doneToday, .donePast: "done"
        case .openToday: "due today"
        case .missed: "missed"
        case .upcoming: "upcoming"
        }
        return "\(habitName), \(state)"
    }

    /// The glow is the only thing marking a slot as actionable, and it is
    /// invisible to VoiceOver, so the hint has to carry what a sighted user
    /// reads off the screen.
    private var accessibilityHint: String {
        guard slot.isTappable else { return "" }
        return slot.state == .filled ? "Mark as not done" : "Mark as done"
    }

    private func tap() {
        guard let day = slot.actionDay else { return }
        onToggle(day)
    }

    private func transition(from previous: SlotState, to next: SlotState) {
        guard previous == .open, next == .filled else {
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
private struct PressStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
