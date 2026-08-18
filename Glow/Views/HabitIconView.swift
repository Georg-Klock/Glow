import SwiftUI

/// A habit's icon, as a symbol or as whatever text was stored before symbols.
struct HabitIconView: View {
    let icon: String

    var body: some View {
        Group {
            if HabitSymbol.isSymbol(icon) {
                Image(systemName: icon)
            } else {
                Text(icon)
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: 24, alignment: .center)
    }
}
