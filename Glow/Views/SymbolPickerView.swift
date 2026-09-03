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
    /// One grid for both tabs. Switching between them should change what is in
    /// the cells, not where the cells are.
    private static let columnCount = 6
    private static let gridSpacing: CGFloat = 10
    /// Between one section and the next. Shared, because the two tabs are the
    /// same grid: anything that differs is something that shifts under your
    /// thumb when you switch between them.
    private static let sectionSpacing: CGFloat = 20
    /// An emoji is a picture with its own margins; a symbol is a stroke drawn
    /// to its box. Matching the numbers would leave the emoji looking smaller
    /// than the symbol beside it, so the emoji is set larger to land the same.
    private static let symbolSize: CGFloat = 24
    private static let emojiSize: CGFloat = 30
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: gridSpacing),
        count: columnCount
    )

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
            LazyVStack(alignment: .leading, spacing: Self.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                // The same shortcut the emoji tab opens with, in symbols: one
                // for each suggested emoji, hand-paired. Nobody browsing three
                // hundred pictograms for "the running one" should have to.
                Section {
                    symbolGrid(HabitSymbol.suggested)
                } header: {
                    header("Suggested")
                }
                ForEach(HabitSymbol.groups) { group in
                    Section {
                        symbolGrid(group.symbols)
                    } header: {
                        header(group.title)
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
        LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
            ForEach(symbols, id: \.self) { symbol in
                symbolTile(symbol)
                    .accessibilityLabel(HabitSymbol.spokenName(for: symbol))
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
            squareCell {
                let glyph = Image(systemName: symbol).font(.system(size: Self.symbolSize))
                // Selection is the glow, because the card that used to carry it
                // is gone — and a glow is what this app says "chosen" with
                // everywhere else.
                if selection == symbol {
                    glyph.glowing()
                } else {
                    glyph.foregroundStyle(GlowPalette.color)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Emoji

    @ViewBuilder
    private var emojiContent: some View {
        if query.isEmpty {
            LazyVStack(alignment: .leading, spacing: Self.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                // The habit-relevant ones first, since this is a habit tracker
                // and nobody opens this screen looking for a flag.
                Section {
                    emojiGrid(HabitEmoji.suggested.map { ($0.emoji, $0.name) })
                } header: {
                    header("Suggested")
                }
                ForEach(HabitEmoji.categories) { category in
                    Section {
                        emojiGrid(category.emoji.map { ($0.glyph, $0.name) })
                    } header: {
                        header(category.title)
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
        LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
            ForEach(items, id: \.glyph) { item in
                emojiTile(item)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(
                        selection == item.glyph ? [.isSelected, .isButton] : .isButton
                    )
            }
        }
        .padding(.horizontal, 16)
    }

    private func emojiTile(_ item: (glyph: String, name: String)) -> some View {
        Button {
            selection = item.glyph
            dismiss()
        } label: {
            squareCell {
                Text(item.glyph).font(.system(size: Self.emojiSize))
            }
            // A ring rather than a glow. `glowing` masks the HDR tile to the
            // shape it is given and tints it white, which is exactly right for
            // a line drawing and would strip an emoji of the only thing it has.
            .overlay {
                if selection == item.glyph {
                    Circle()
                        .strokeBorder(GlowPalette.color, lineWidth: 1.5)
                        .glowing()
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// A clear square carrying its content, rather than content carrying a
    /// frame. It is what keeps a cell square whatever is inside it —
    /// `figure.walk.treadmill` and `circle` are very different shapes.
    private func squareCell(@ViewBuilder content: () -> some View) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(content())
            .contentShape(Rectangle())
    }

    // MARK: - Shared

    /// Text only, on both tabs.
    ///
    /// The symbol headers used to carry an icon — the group's own first symbol,
    /// which is arbitrary — and the emoji headers did not. That made the two
    /// headers different heights, so every section below them sat at a
    /// different offset and the whole grid stepped sideways when you switched
    /// tabs. The icon was decoration; the alignment was not.
    private func header(_ title: String) -> some View {
        Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
    }
}
