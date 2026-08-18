import SwiftUI

/// One circle or pill, and the completion animation.
///
/// Layering, bottom to top:
///  1. the empty track, so an inactive slot is a flat grey shape;
///  2. a dim outline, shown while the slot is open;
///  3. the HDR glow image;
///  4. the solid filled shape, which fades **in** over the glow.
///
/// Step 4 is the whole trick of the completion transition. The obvious
/// implementation is to fade the glow out, but animating opacity on an HDR layer
/// invites the compositor to flatten it into an offscreen SDR buffer, and a glow
/// that dies the instant you touch it is exactly the bug that would be hardest
/// to explain. Fading an opaque SDR shape in over a glow that never changes
/// looks identical and never puts the HDR layer through a blend.
struct SlotView: View {
    let slot: Slot
    let accent: HabitAccent
    let size: CGSize
    let habitName: String

    /// Hold the glow at full strength for a beat after the tap, so completion
    /// registers as an event rather than as the glow simply vanishing.
    private static let holdDuration: Duration = .milliseconds(200)
    private static let fadeDuration: TimeInterval = 0.75

    @State private var isGlowing = false
    @State private var fillCoverage: Double = 0

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.slotTrack)

            if slot.state == .open {
                Capsule()
                    .strokeBorder(accent.color.opacity(0.55), lineWidth: 1.5)
            }

            if isGlowing {
                GlowImageView(size: size, accent: accent)
            }

            Capsule()
                .fill(accent.color)
                .opacity(fillCoverage)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Capsule())
        .allowsHitTesting(slot.isTappable)
        .onAppear { applyStateWithoutAnimation() }
        .onChange(of: slot.state) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(slot.isTappable ? .isButton : [])
    }

    private var accessibilityLabel: String {
        let state = switch slot.state {
        case .filled: "done"
        case .open: "due today"
        case .inactive: "not done"
        }
        return "\(habitName), \(state)"
    }

    /// Settle straight into the current state on first layout, so scrolling a
    /// row back into view does not replay the completion animation.
    private func applyStateWithoutAnimation() {
        isGlowing = slot.state == .open
        fillCoverage = slot.state == .filled ? 1 : 0
    }

    private func transition(from previous: SlotState, to next: SlotState) {
        guard previous == .open, next == .filled else {
            // Every other transition is instant, including un-completing today,
            // which puts the slot straight back to open with the glow resumed.
            withAnimation(.easeOut(duration: 0.2)) {
                fillCoverage = next == .filled ? 1 : 0
            }
            isGlowing = next == .open
            return
        }

        // Completion: hold, then let the solid fill rise over the glow.
        isGlowing = true
        fillCoverage = 0
        Task {
            try? await Task.sleep(for: Self.holdDuration)
            guard slot.state == .filled else { return }
            withAnimation(.easeOut(duration: Self.fadeDuration)) {
                fillCoverage = 1
            }
            // Drop the HDR layer once it is fully covered, so a settled week
            // holds no gain-map images alive behind opaque shapes.
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            if slot.state == .filled { isGlowing = false }
        }
    }
}

extension Color {
    /// The empty slot. Dim enough to read as "nothing here" next to a glow.
    static let slotTrack = Color(white: 0.13)
    /// Pure black, because the glow layer is opaque and its corners have to
    /// disappear into the background rather than blend with it.
    static let appBackground = Color.black
}
