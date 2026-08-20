import SwiftUI

/// One slot, and the completion animation.
///
/// Completing runs in three beats: the ring holds for a moment, fills solid, and
/// collapses to the dot. The hold is what makes it read as an event rather than
/// as the light going out, and the fill is the payoff — for that one moment the
/// slot is the brightest thing the screen will show all day.
///
/// Every other transition is instant. Un-completing especially: it is a
/// correction, and animating a correction dresses a mistake up as an
/// achievement.
///
/// All three beats are the same HDR tile under different masks, cross-faded. The
/// codebase avoided that for a long time on the belief that animating an HDR
/// layer's opacity would flatten it into an SDR buffer. Measured on device, it
/// does not — which is what makes this shape possible at all.
struct SlotView: View {
    let slot: Slot
    let size: CGSize
    let habitName: String

    /// Hold the ring at full strength for a beat after the tap.
    private static let hold: Duration = .milliseconds(200)
    private static let fill: TimeInterval = 0.35
    private static let settle: TimeInterval = 0.25

    /// Non-nil only while a completion is playing. When it is nil the slot draws
    /// its resting truth and nothing else.
    @State private var beats: Beats?

    /// The opacity of each of the three layers.
    private struct Beats: Equatable {
        var ring: Double = 1
        var capsule: Double = 0
        var dot: Double = 0
    }

    var body: some View {
        ZStack {
            if let beats {
                GlowImageView(size: size, shape: .ring).opacity(beats.ring)
                GlowImageView(size: size, shape: .capsule).opacity(beats.capsule)
                GlowImageView(size: size, shape: .dot).opacity(beats.dot)
            } else {
                SlotMarkView(mark: slot.mark, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Capsule(style: .continuous))
        .allowsHitTesting(slot.isTappable)
        .onChange(of: slot.state) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(slot.isTappable ? .isButton : [])
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

    private func transition(from previous: SlotState, to next: SlotState) {
        guard previous == .open, next == .filled else {
            beats = nil
            return
        }

        beats = Beats()
        Task {
            try? await Task.sleep(for: Self.hold)
            guard slot.state == .filled else { return beats = nil }
            withAnimation(.easeOut(duration: Self.fill)) {
                beats = Beats(ring: 0, capsule: 1, dot: 0)
            }

            try? await Task.sleep(for: .seconds(Self.fill))
            guard slot.state == .filled else { return beats = nil }
            withAnimation(.easeInOut(duration: Self.settle)) {
                beats = Beats(ring: 0, capsule: 0, dot: 1)
            }

            // Hand back to the resting mark, which is the same glowing dot —
            // so a row scrolled away and back does not replay any of this, and
            // no HDR layers are left alive at zero opacity.
            try? await Task.sleep(for: .seconds(Self.settle))
            if slot.state == .filled { beats = nil }
        }
    }
}
