import SwiftUI

/// A habit's icon, as a symbol or as whatever text was stored before symbols.
struct HabitIconView: View {
    let icon: String
    /// The widget draws its glyphs two points under the name beside them —
    /// 10 against 12 since #404, where it was 14 and read as larger than the
    /// text it labels. The 24pt column below is what holds the layout, not the
    /// glyph, so the icon can shrink inside it without anything after it
    /// moving. The app has no frame in the design and keeps the body size.
    var size: CGFloat?

    /// The icon does not change with its row's state.
    ///
    /// It sits inside the label, which switches weight when a habit is still
    /// due — and an SF Symbol inherits font weight, so the glyph was thickening
    /// and thinning along with the text. The row's state is carried by
    /// brightness and by the marks; the icon should be the same drawing all
    /// week. Pinned here rather than at each call site so it cannot drift back.
    var body: some View {
        Group {
            if HabitSymbol.isSymbol(icon) {
                Image(systemName: icon)
            } else {
                Text(icon)
            }
        }
        .font(size.map { .system(size: $0, weight: .regular) } ?? .body.weight(.regular))
        .frame(width: 24, alignment: .center)
    }
}

/// The icon-and-name half of a habit row, shared by the app and the widget.
///
/// A symbol is type: it takes the same resting, lit or emitting treatment as
/// the name beside it. An emoji is already a full-colour picture. Sending it
/// through `glowing()` would use only its alpha as a mask and replace those
/// colours with the glow tile, so emoji stay in the base layer while only the
/// name enters the emitting layer (#457).
///
/// `baseTier` is optional because a widget's emitting label has no crossfade
/// underneath it. The app supplies a base on every non-editing frame so its
/// existing due-to-handled transition can fade the emitting copy away. When
/// there is no base, an emoji still gets an icon-only base of its own; a symbol
/// needs none because it is present in the emitting copy.
struct HabitLabelView: View {
    let icon: String
    let name: String
    let iconSize: CGFloat?
    let iconWidth: CGFloat
    let iconGap: CGFloat
    let textSize: CGFloat
    let nameMaxWidth: CGFloat
    let baseTier: TypeTier?
    let emittingOpacity: Double
    var keepsTrailingSpacer = true
    var isPlain = false

    private var isSymbol: Bool { HabitSymbol.isSymbol(icon) }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPlain {
                content(iconOpacity: 1, nameOpacity: 1)
                    .foregroundStyle(GlowPalette.color)
            } else {
                if let baseTier {
                    base(content(iconOpacity: 1, nameOpacity: 1), tier: baseTier)
                } else if !isSymbol {
                    // The widget's emitting state has no ordinary label under
                    // it. Emoji are the exception because their colour cannot
                    // live in the mask: draw only the icon underneath and let
                    // the emitting layer provide the name.
                    content(iconOpacity: 1, nameOpacity: 0)
                        .foregroundStyle(GlowPalette.color)
                        .accessibilityHidden(true)
                }

                content(iconOpacity: isSymbol ? 1 : 0, nameOpacity: 1)
                    .glowing()
                    .opacity(emittingOpacity)
                    .accessibilityHidden(emittingOpacity <= 0)
            }
        }
    }

    @ViewBuilder
    private func base<Content: View>(_ content: Content, tier: TypeTier) -> some View {
        switch tier {
        case .lit:
            content.foregroundStyle(GlowPalette.lit)
        case .resting:
            content.foregroundStyle(GlowPalette.grey)
        case .emitting:
            // Callers express emission with `emittingOpacity`; accepting this
            // case defensively keeps a future misuse visible rather than
            // silently turning it grey.
            content.foregroundStyle(GlowPalette.color)
        }
    }

    private func content(iconOpacity: Double, nameOpacity: Double) -> some View {
        // The gap belongs between the icon and the name. Giving it to the
        // HStack also inserts the same gap before the trailing Spacer, which
        // spends width on nothing and cuts the name early (#475).
        HStack(spacing: 0) {
            HabitIconView(icon: icon, size: iconSize)
                .frame(width: iconWidth)
                .padding(.trailing, iconGap)
                .opacity(iconOpacity)

            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: nameMaxWidth, alignment: .leading)
                .opacity(nameOpacity)

            if keepsTrailingSpacer { Spacer(minLength: 0) }
        }
        .font(.system(size: textSize))
    }
}
