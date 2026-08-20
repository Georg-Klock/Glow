import SwiftUI

/// Draws one slot's mark, in the app and in the widget both.
///
/// Kept out of `SlotView` because the widget cannot use that type — it owns a
/// completion animation driven by `@State`, and a widget is a snapshot with no
/// state to drive. What the two must agree on is what a mark *looks like*, so
/// that is what lives here and nothing else.
struct SlotMarkView: View {
    let mark: SlotMark
    let size: CGSize
    /// Widget slots are distributed by their `HStack` and must not be pinned to
    /// a width; the app's are measured by `SlotLayout` and want one.
    var fillsWidth = false
    /// A span covering several days draws its completion as a bar rather than a
    /// dot — the mark has width to carry, so it does not need weight.
    var spansDays = false

    var body: some View {
        switch mark {
        case .openToday:
            glow(.ring)
        case .doneToday, .donePast:
            // The same mark either way. A completion does not fade with age:
            // the row is a record of what happened, and Monday happened.
            glow(spansDays ? .bar : .dot)
        case .missed:
            glyph("xmark", tint: GlowPalette.missed, scale: 0.42)
        case .upcoming:
            // Solid, not hollow. It reads as an empty socket waiting to be
            // filled, which is what keeps a nearly-empty row legible as a week.
            shape(GlowPalette.upcoming)
        }
    }

    private func glow(_ shape: GlowShape) -> some View {
        GlowImageView(size: size, shape: shape, fillsWidth: fillsWidth)
    }

    /// A flat filled slot, at the full size of its column or span.
    private func shape(_ tint: Color) -> some View {
        sized(Capsule(style: .continuous).fill(tint))
    }

    /// The only mark drawn as a glyph. Past and future marks are flat SDR —
    /// headroom is spent on things that happened, and nothing else.
    private func glyph(_ name: String, tint: Color, scale: CGFloat) -> some View {
        sized(
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .frame(width: size.height * scale, height: size.height * scale)
                .foregroundStyle(tint)
        )
    }

    @ViewBuilder
    private func sized(_ content: some View) -> some View {
        if fillsWidth {
            content.frame(maxWidth: .infinity).frame(height: size.height)
        } else {
            content.frame(width: size.width, height: size.height)
        }
    }
}
