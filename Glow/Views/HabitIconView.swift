import SwiftUI

/// A habit's icon, as a symbol or as whatever text was stored before symbols.
struct HabitIconView: View {
    let icon: String

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
        .font(.body.weight(.regular))
        .frame(width: 24, alignment: .center)
    }
}
