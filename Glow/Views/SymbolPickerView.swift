import SwiftUI

/// Browse or search every SF Symbol, or pick a curated emoji.
///
/// A pushed screen rather than an inline grid: nine thousand symbols is a
/// destination, and `searchable` belongs to a screen that owns its own
/// navigation bar.
struct SymbolPickerView: View {
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .symbols
    @State private var query = ""

    enum Mode: String, CaseIterable, Identifiable {
        case symbols = "Symbols"
        case emoji = "Emoji"
        var id: String { rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Icon kind", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                switch mode {
                case .symbols: symbolContent
                case .emoji: emojiContent
                }
            }
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: mode == .symbols ? "Search symbols" : "Search emoji"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // The two sets are searched separately, so a query left over from the
        // other tab would silently show an empty grid.
        .onChange(of: mode) { _, _ in query = "" }
    }

    // MARK: - Symbols

    @ViewBuilder
    private var symbolContent: some View {
        if query.isEmpty {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(HabitSymbol.groups) { group in
                    Section {
                        symbolGrid(group.symbols)
                    } header: {
                        header(group.title, systemImage: group.icon)
                    }
                }
            }
            .padding(.vertical, 8)
        } else {
            let results = HabitSymbol.search(query)
            if results.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            } else {
                symbolGrid(results).padding(.vertical, 12)
            }
        }
    }

    private func symbolGrid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                tile(isSelected: selection == symbol) { selection = symbol } content: {
                    Image(systemName: symbol).font(.system(size: 22))
                }
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selection == symbol ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Emoji

    @ViewBuilder
    private var emojiContent: some View {
        if query.isEmpty {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(HabitEmoji.groups) { group in
                    Section {
                        emojiGrid(group.icons)
                    } header: {
                        header(group.title, systemImage: nil)
                    }
                }
            }
            .padding(.vertical, 8)
        } else {
            let results = HabitEmoji.search(query)
            if results.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            } else {
                emojiGrid(results).padding(.vertical, 12)
            }
        }
    }

    private func emojiGrid(_ icons: [HabitEmoji.Icon]) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(icons) { icon in
                tile(isSelected: selection == icon.emoji) { selection = icon.emoji } content: {
                    Text(icon.emoji).font(.system(size: 26))
                }
                .accessibilityLabel(icon.name)
                .accessibilityAddTraits(selection == icon.emoji ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Shared

    private func header(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func tile<Content: View>(
        isSelected: Bool,
        select: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            select()
            dismiss()
        } label: {
            content()
                .frame(width: 52, height: 52)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(GlowPalette.color) : AnyShapeStyle(.fill.tertiary))
                }
        }
        .buttonStyle(.plain)
    }
}
