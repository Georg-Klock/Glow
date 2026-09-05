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

    /// How a mark changes state: a quick cross-fade between the old drawing and
    /// the new one, both ways (2026-09-05). It was a 0.34s spring that shrank
    /// the ring into the dot, and the undo was a cut; see
    /// `MotionPolicy.crossfadesMark`.
    ///
    /// Not private: the habit's label dims over exactly this, so the row reads
    /// as one movement rather than a mark that fades beside a label that
    /// snaps. Two timings for one event is two events.
    static let close = Animation.easeOut(duration: 0.12)

    /// How long the previous drawing stays on top while it fades.
    static let closeDuration: Duration = .milliseconds(120)

    /// The drawing the mark had before its last change of state, kept only
    /// while it fades out over the new one. Nil at rest, so the resting render
    /// is exactly `SlotMarkView` and nothing composites it — an opacity
    /// transition on the mark itself renders through a group and dims the
    /// lit white (measured: 2698 → 2535 level-255 pixels on the grid rows
    /// frame), which on a device would also flatten the HDR tile.
    @State private var previousMark: SlotMark?
    @State private var previousOpacity: Double = 1

    var body: some View {
        Group {
            if slot.isTappable {
                // **The hit area is the slot, not the ink** (#116). A `Button`
                // otherwise takes its label's drawn shape; today's ring or dot
                // must keep the whole day-sized target even when the ink is
                // smaller than its frame (#543 later made today the only live
                // cadence cell again).
                Button { tap() } label: { mark.contentShape(Rectangle()) }
                    .buttonStyle(PressStyle(
                        scale: MotionPolicy.pressScale(Self.pressScale, reduceMotion: reduceMotion)
                    ))
            } else {
                mark
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: slot.mark) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(slot.isTappable ? .isButton : [])
    }

    /// The current drawing, with the previous one fading out on top of it
    /// when the state has just changed (`MotionPolicy.crossfadesMark`).
    private var mark: some View {
        ZStack {
            SlotMarkView(mark: slot.mark, size: size, flattensSocket: true)
            if let previousMark {
                SlotMarkView(mark: previousMark, size: size, flattensSocket: true)
                    .opacity(previousOpacity)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The habit, the date this column is, and what the mark says — including
    /// the rest day's word, which is the only thing explaining a column that
    /// draws nothing (#72), and the date, which is the only thing saying which
    /// Tuesday a "missed" belongs to (#137). The weekday header carries it on
    /// screen and is hidden from VoiceOver, because seven letters over seven
    /// numbers is a table read aloud.
    private func transition(from previous: SlotMark, to next: SlotMark) {
        guard MotionPolicy.crossfadesMark(
            from: previous, to: next, reduceMotion: reduceMotion
        ) else {
            previousMark = nil
            return
        }
        previousMark = previous
        previousOpacity = 1
        withAnimation(Self.close) { previousOpacity = 0 }
        Task {
            try? await Task.sleep(for: Self.closeDuration)
            if previousMark == previous { previousMark = nil }
        }
    }

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
