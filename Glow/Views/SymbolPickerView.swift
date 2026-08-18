import SwiftUI

/// Browse or search every SF Symbol.
///
/// A pushed screen rather than an inline grid: nine thousand icons is a
/// destination, and `searchable` belongs to a screen that owns its own
/// navigation bar.
struct SymbolPickerView: View {
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    var body: some View {
        ScrollView {
            if query.isEmpty {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(HabitSymbol.groups) { group in
                        Section {
                            grid(group.symbols)
                        } header: {
                            Label(group.title, systemImage: group.icon)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(.bar)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                let results = HabitSymbol.search(query)
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                } else {
                    grid(results)
                        .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search symbols")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private func grid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                    dismiss()
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(selection == symbol ? Color.black : Color.primary)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == symbol
                                      ? AnyShapeStyle(GlowPalette.color)
                                      : AnyShapeStyle(.fill.tertiary))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selection == symbol ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 16)
    }
}
