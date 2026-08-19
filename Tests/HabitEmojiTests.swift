import Foundation
import Testing
@testable import Glow

@Suite("Emoji catalogue")
struct HabitEmojiTests {
    @Test("Every emoji's paired symbol is one the app can actually draw")
    func pairedSymbolsExist() {
        // The pairing is hand-written, which is the only honest way to pick a
        // "closest" symbol — and exactly why it needs checking. A name that
        // never existed, or that a future OS drops, would otherwise render as
        // literal text on someone's phone.
        for icon in HabitEmoji.all {
            #expect(HabitSymbol.isSymbol(icon.symbol), "\(icon.emoji) \(icon.name) -> \(icon.symbol) is not a known symbol")
        }
    }

    @Test("No emoji appears twice")
    func noDuplicateEmoji() {
        let all = HabitEmoji.all.map(\.emoji)
        #expect(Set(all).count == all.count)
    }

    @Test("Every entry is searchable by its own name")
    func searchFindsEachByName() {
        for icon in HabitEmoji.all {
            let hits = HabitEmoji.search(icon.name)
            #expect(hits.contains(where: { $0.emoji == icon.emoji }), "searching \"\(icon.name)\" did not find \(icon.emoji)")
        }
    }

    @Test("Search matches keywords and the paired symbol, not just the name")
    func searchMatchesKeywordsAndSymbol() {
        #expect(HabitEmoji.search("hydrate").contains { $0.emoji == "💧" })
        #expect(HabitEmoji.search("figure.run").contains { $0.emoji == "🏃" })
        #expect(HabitEmoji.search("cardio").contains { $0.emoji == "🏃" })
    }

    @Test("A stored emoji resolves to its nearest symbol")
    func nearestSymbolLookup() {
        #expect(HabitEmoji.nearestSymbol(for: "📖") == "book")
        #expect(HabitEmoji.nearestSymbol(for: "🏃") == "figure.run")
        // Anything outside the curated set has no opinion attached to it.
        #expect(HabitEmoji.nearestSymbol(for: "🫥") == nil)
    }

    @Test("Emoji are not mistaken for symbols")
    func emojiAreNotSymbols() {
        // HabitIconView draws anything outside the symbol catalogue as text,
        // which is how emoji habits render at all.
        for icon in HabitEmoji.all {
            #expect(!HabitSymbol.isSymbol(icon.emoji))
        }
    }

    @Test("The set is grouped and reasonably broad")
    func catalogueShape() {
        #expect(HabitEmoji.groups.count >= 6)
        #expect(HabitEmoji.all.count >= 90)
        for group in HabitEmoji.groups {
            #expect(!group.icons.isEmpty, "\(group.title) is empty")
        }
    }
}
