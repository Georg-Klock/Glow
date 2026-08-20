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

    var body: some View {
        switch mark {
        case .openToday:
            GlowImageView(size: size, shape: .ring, fillsWidth: fillsWidth)
        case .doneToday:
            GlowImageView(size: size, shape: .checkmark, fillsWidth: fillsWidth)
        case .donePast:
            glyph("checkmark", tint: GlowPalette.markPast)
        case .missed:
            glyph("xmark", tint: GlowPalette.markFaint)
        case .upcoming:
            // Hollow, not filled: a day still to come has nothing in it yet, and
            // a solid dot reads as a quiet completion.
            glyph("circle", tint: GlowPalette.markFaint, scale: 0.45)
        }
    }

    /// Past and future marks are flat SDR glyphs. Only today gets headroom —
    /// that is the entire hierarchy, and spending HDR anywhere else would flatten
    /// it.
    @ViewBuilder
    private func glyph(_ name: String, tint: Color, scale: CGFloat = 0.72) -> some View {
        let icon = Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(height: size.height * scale)
            .foregroundStyle(tint)

        if fillsWidth {
            icon.frame(maxWidth: .infinity).frame(height: size.height)
        } else {
            icon.frame(width: size.width, height: size.height)
        }
    }
}
