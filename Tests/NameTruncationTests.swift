import CoreGraphics
import Foundation
import Testing
@testable import Glow

/// The one place a habit name's ellipsis is decided (#615).
///
/// The bug these are written against: the editor drew the name at 17pt in a
/// field `nameMaxWidth × 17/12` wide and let `Text` truncate it there, which
/// was supposed to land on the same character as the row's own cut at 12pt in
/// `nameMaxWidth`. It did not, because a line's width is
/// `size × Σ(advances) + (count − 1) × tracking(size)` and SF's tracking is
/// per-size — so the two disagreed on half the names anyone would type.
@Suite("Name truncation")
struct NameTruncationTests {
    /// The row's own geometry on the phone the report came from: 390pt wide,
    /// so the panel is at full scale and the column is the design's 71.75pt of
    /// 12pt type.
    private let row = RowGeometry(totalWidth: 390 - GridMetrics.horizontalPadding * 2)

    /// What the field is given, in the field's own type.
    private var fieldWidth: CGFloat {
        HabitEditorGeometry.nameFieldWidth(
            rowNameWidth: row.nameMaxWidth,
            rowTextSize: row.nameTextSize,
            fieldTextSize: HabitEditorGeometry.nameFieldBaseTextSize
        )
    }

    @Test("The reported name is cut, and cut where the row cuts it")
    func crossbowwwIsCut() {
        // The exact string from #615. 74.63pt at 12pt against 71.75pt: the row
        // cuts it. The editor showed all ten letters, because at 17pt it
        // measures 101.40pt against a 101.65pt field — inside by a quarter of
        // a point.
        #expect(NameTruncation.width("Crossbowww", size: 12) > row.nameMaxWidth)
        #expect(NameTruncation.width("Crossbowww", size: 17) <= fieldWidth)

        // Which is the disagreement, and it is gone: one answer, taken at the
        // row's size, and the field draws that.
        #expect(NameTruncation.isCut("Crossbowww", size: row.nameTextSize, limit: row.nameMaxWidth))
        #expect(
            NameTruncation.visible("Crossbowww", size: row.nameTextSize, limit: row.nameMaxWidth)
                == "Crossbow\u{2026}"
        )
    }

    @Test("A name that fits is returned whole, with no ellipsis")
    func fittingNamesAreUntouched() {
        for name in ["Read", "Workout", "7x Gratitude", "Stretch", "VO2 Max"] {
            let visible = NameTruncation.visible(
                name, size: row.nameTextSize, limit: row.nameMaxWidth
            )
            #expect(visible == name, "\(name) came back as \(visible)")
            #expect(!NameTruncation.isCut(name, size: row.nameTextSize, limit: row.nameMaxWidth))
        }
    }

    /// **The correspondence this type exists to keep is verified on a device,
    /// not here.**
    ///
    /// The obvious unit test — render the name with SwiftUI's own truncation,
    /// render the model's prediction beside it, compare the pixels — was
    /// written and then removed, because the only renderer available to a unit
    /// test is `ImageRenderer`, and this repository already knows not to
    /// believe it about layout (#386): it substitutes its own placeholder for
    /// views it cannot flatten and reports success either way. Asked for
    /// "Crossbowww" in a 71.75pt column it drew "Crossboww…" — a string
    /// measuring 74.11pt, wider than the column it was given — while the
    /// running app, on a simulator, drew "Crossbow…" for the same name in the
    /// same column, which is what this model predicts and what #615 reported
    /// seeing.
    ///
    /// A test that fails when the app is right is worse than no test, so the
    /// claim is made where it can be checked honestly: by typing a boundary
    /// name into the running app and reading the screen. What stays here is
    /// arithmetic — measurements, and the invariants that follow from them.

    /// The invariant the editor's overlay relies on to never re-truncate.
    ///
    /// The field draws the row's visible string at 17pt inside
    /// `nameMaxWidth × 17/12`. That is only safe because 17pt type is
    /// *proportionally narrower* than 12pt type — the same non-linearity that
    /// caused the bug is what makes the quote fit. If SF's tracking table ever
    /// moved the other way, this is what would say so.
    @Test("The row's visible text always fits the field that quotes it")
    func visibleTextFitsTheField() {
        var names: [String] = []
        for stem in ["Crossbow", "Read Book", "Gratitude", "Early night", "Journalling",
                     "Walk the dog", "Piano practice", "Wwwwwwwwww", "iiiiiiiiii"] {
            for prefix in ["", "2x ", "7x ", "10x "] {
                for extra in ["", "w", "ww", "www", "m", "mm", "i", "W"] {
                    names.append(prefix + stem + extra)
                }
            }
        }
        for name in names {
            let visible = NameTruncation.visible(
                name, size: row.nameTextSize, limit: row.nameMaxWidth
            )
            let drawn = NameTruncation.width(
                visible, size: HabitEditorGeometry.nameFieldBaseTextSize
            )
            #expect(
                drawn <= fieldWidth,
                "\"\(visible)\" needs \(drawn)pt in a \(fieldWidth)pt field"
            )
        }
    }

    @Test("Degenerate widths do not produce a glyph with no room for it")
    func zeroWidthColumnsAreEmpty() {
        // `nameMaxWidth` floors at zero on a zero-width proposal (#136), and a
        // sheet's first pass can propose one.
        #expect(NameTruncation.visible("Workout", size: 12, limit: 0) == "")
        #expect(NameTruncation.visible("Workout", size: 12, limit: -5) == "")
        #expect(NameTruncation.visible("", size: 12, limit: 100) == "")
        #expect(NameTruncation.visible("Workout", size: 0, limit: 100) == "")
        #expect(NameTruncation.width("", size: 12) == 0)
    }

    @Test("A name is cut between grapheme clusters, never inside one")
    func emojiSurviveTheCut() {
        // A flag is several scalars and one Character. Cutting inside it would
        // draw a stray regional indicator.
        let name = "🇩🇪🇩🇪🇩🇪🇩🇪🇩🇪🇩🇪🇩🇪🇩🇪"
        let visible = NameTruncation.visible(name, size: 12, limit: 40)
        #expect(visible.hasSuffix("\u{2026}"))
        let kept = String(visible.dropLast())
        #expect(name.hasPrefix(kept))
        #expect(kept.unicodeScalars.count % 2 == 0, "cut inside a flag: \(kept.unicodeScalars.count)")
    }
}
