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

    /// Six per row, fixed rather than adaptive, and square.
    ///
    /// Adaptive sizing fits as many as it can and then distributes the slack,
    /// so the cells are never quite square and the count changes with the
    /// screen. A fixed count divides the width exactly, and a 1:1 aspect ratio
    /// makes each cell a square — which is what a grid of pictograms wants to
    /// be when there is no card behind them to define the shape.
    private static let symbolColumnCount = 6
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: symbolColumnCount
    )
    /// Tighter and chrome-free, like the emoji keyboard: glyphs sit next to
    /// each other rather than each in its own tile.
    private let emojiColumns = [GridItem(.adaptive(minimum: 44), spacing: 4)]

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
                symbolTile(symbol)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(
                        selection == symbol ? [.isSelected, .isButton] : .isButton
                    )
            }
        }
        .padding(.horizontal, 16)
    }

    private func symbolTile(_ symbol: String) -> some View {
        Button {
            selection = symbol
            dismiss()
        } label: {
            // A clear square carrying the glyph, rather than the glyph carrying
            // a frame. It is what makes the cell exactly square regardless of
            // how wide or tall the symbol inside it happens to draw.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    let glyph = Image(systemName: symbol).font(.system(size: 24))
                    // Selection is the glow, because the card that used to
                    // carry it is gone — and a glow is what this app says
                    // "chosen" with everywhere else.
                    if selection == symbol {
                        glyph.glowing(halo: GlowPalette.labelHalo)
                    } else {
                        glyph.foregroundStyle(GlowPalette.color)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Emoji

    @ViewBuilder
    private var emojiContent: some View {
        if query.isEmpty {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                // The habit-relevant ones first, since this is a habit tracker
                // and nobody opens this screen looking for a flag.
                Section {
                    emojiGrid(HabitEmoji.suggested.map { ($0.emoji, $0.name) })
                } header: {
                    header("Suggested", systemImage: nil)
                }
                ForEach(HabitEmoji.categories) { category in
                    Section {
                        emojiGrid(category.emoji.map { ($0.glyph, $0.name) })
                    } header: {
                        header(category.title, systemImage: nil)
                    }
                }
            }
            .padding(.vertical, 8)
        } else {
            // Search spans everything, matched on the Unicode name.
            let results = HabitEmoji.searchAll(query).map { ($0.glyph, $0.name) }
            if results.isEmpty {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            } else {
                emojiGrid(results).padding(.vertical, 12)
            }
        }
    }

    private func emojiGrid(_ items: [(glyph: String, name: String)]) -> some View {
        LazyVGrid(columns: emojiColumns, spacing: 4) {
            ForEach(items, id: \.glyph) { item in
                Button {
                    selection = item.glyph
                    dismiss()
                } label: {
                    Text(item.glyph)
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44)
                        .background {
                            // Only the selected glyph gets any chrome at all.
                            if selection == item.glyph {
                                Circle().fill(GlowPalette.color.opacity(0.28))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(selection == item.glyph ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 12)
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
}
