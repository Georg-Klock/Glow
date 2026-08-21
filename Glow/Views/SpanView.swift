import SwiftUI

/// A run of days, and the same completion animation the single slots use.
///
/// The open span and the completed bar are one capsule at two sizes, exactly as
/// the ring and the dot are one circle at two diameters. Hold the stroke at
/// 1.5pt and close the height: the hole is height minus twice the stroke, so it
/// reaches zero at 3 and the outline becomes solid. The width closes too, by the
/// dot's own inset at each end, because a completed run starts where the first
/// day's dot would start rather than at the column's edge.
///
/// Not merged with `SlotView` despite the shared idea. That view animates one
/// number and this one animates two, and folding them together would mean a
/// size-shaped parameter and a branch at every use — more machinery than the
/// eight lines it would save.
struct SpanView: View {
    let span: SlotSpan
    let size: CGSize
    let habitName: String
    /// The rest day's column inside this span, in the span's own coordinates,
    /// or nil when the span does not cross one. Computed by the row from the
    /// track — see `RestWindow` — because the row is what knows the track.
    var restWindow: ClosedRange<CGFloat>?
    let onToggle: (Date) -> Void

    /// Non-nil only while a completion is closing.
    @State private var closing: CGSize?

    /// Where a bar sits inside its span: the dot's margin, at each end.
    private var inset: CGFloat { (size.height - GlowShape.dotDiameter) / 2 }

    var body: some View {
        Group {
            if span.isTappable {
                Button { tap() } label: { mark }
                    .buttonStyle(PressStyle(scale: SlotView.pressScale))
            } else {
                mark
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: span.state) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel("\(habitName), \(label)")
        .accessibilityAddTraits(span.isTappable ? .isButton : [])
    }

    @ViewBuilder
    private var mark: some View {
        if let closing {
            GlowImageView(
                size: closing,
                shape: .ring,
                ringLineWidth: size.height * GlowShape.ringWeight,
                // The window does not go away for the 600ms — a bar flashing
                // across the cut and then being taken back is worse than never
                // cutting it. It is re-expressed, though: the closing shape is
                // centred in the span's frame and narrower than it, so the
                // window has to be measured from *its* leading edge.
                restWindow: restWindow.map { window in
                    let shift = (size.width - closing.width) / 2
                    return (window.lowerBound - shift)...(window.upperBound - shift)
                }
            )
        } else {
            SlotMarkView(
                mark: span.mark,
                size: size,
                spansDays: span.dayCount > 1,
                restWindow: restWindow
            )
        }
    }

    private var label: String {
        switch span.state {
        case .filled: "done"
        case .open: "due today"
        case .missed, .inactive: "still to come"
        }
    }

    private func tap() {
        guard let day = span.actionDay else { return }
        onToggle(day)
    }

    private func transition(from previous: SlotState, to next: SlotState) {
        guard previous == .open, next == .filled else {
            closing = nil
            return
        }

        closing = size
        withAnimation(SlotView.close) {
            closing = CGSize(
                width: max(0, size.width - inset * 2),
                height: GlowShape.barThickness
            )
        }

        Task {
            try? await Task.sleep(for: SlotView.closeDuration)
            if span.state == .filled { closing = nil }
        }
    }
}
