import CoreGraphics
import CoreText
import Foundation

/// Where a habit's name is cut, decided once.
///
/// **Two surfaces draw the same name at two sizes, and only one of them can be
/// right about where it ends** (#615). The row draws it at the grid's 12pt in a
/// 71.75pt column and lets `Text` tail-truncate it. The editor's field draws it
/// at 17pt, because a field you type into should be readable, and it used to
/// truncate it a *second* time against a width scaled by the ratio of the two
/// point sizes — `nameMaxWidth × 17/12` — on the theory that enlarging both
/// sides of the ratio keeps the ellipsis on the same character.
///
/// It does not, because text width is not linear in point size. A line is
/// `size × Σ(unit advances) + (count − 1) × tracking(size)`, and SF's tracking
/// table is per-size: at 12pt it tracks looser than at 17pt, so a name at 17pt
/// is *proportionally narrower* than the ratio predicts. Measured over 1,296
/// names, the shipped formula put the field's cut on a different character
/// from the row's **597 times** — the field consistently showing one character
/// the row would not. "Crossbowww" is the case that surfaced it: 74.63pt at
/// 12pt against a 71.75pt column, so the row cuts it to "Crossbow…", and
/// 101.40pt at 17pt against a 101.65pt field, so the field showed all ten
/// letters while the warning above it said the name would be cut.
///
/// No width formula fixes that. Scaling by the *measured* ratio of the same
/// string at both sizes gets 597 down to 35, and by the ratio with the ellipsis
/// included to 29, but every one of them is a second truncation being asked to
/// agree with the first by arithmetic. So the field stops truncating: this
/// resolves the row's own visible text once, and the field draws that string.
/// The two cannot disagree because there is only one answer.
///
/// **This is a measurement, not a second layout engine.** Nothing here decides
/// what the row draws — the row still hands its name to `Text` and lets SwiftUI
/// truncate it. This measures the same font at the same size to say what
/// SwiftUI will do, so the sheet can show it before the habit is saved.
/// `NameTruncationTests` pins that correspondence.
enum NameTruncation {
    /// The character `Text` ends a tail-truncated line with.
    static let ellipsis = "\u{2026}"

    /// One line of `name` in the system font at `size`, in points.
    ///
    /// `CTFontCreateUIFontForLanguage(.system,…)` rather than `UIFont`, so
    /// `Glow/Logic` stays free of UIKit — it compiles into the widget
    /// extension too. The two are the same font: measured equal to
    /// `systemFont(ofSize:)` to within 1e-4pt at both sizes this app uses.
    static func width(_ name: String, size: CGFloat) -> CGFloat {
        guard !name.isEmpty, size > 0, size.isFinite else { return 0 }
        guard let font = CTFontCreateUIFontForLanguage(.system, size, nil) else {
            return 0
        }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: name, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// What is left of `name` after a tail truncation at `limit`.
    ///
    /// The whole name when it fits, and otherwise the longest prefix that fits
    /// *with the ellipsis after it* — which is what `.truncationMode(.tail)`
    /// leaves on screen, and why this cannot be a simple prefix of whatever
    /// fits: the ellipsis takes room the last kept character was measured
    /// against.
    ///
    /// Walks `Character`s, so a name ending in an emoji or a combining mark is
    /// cut between grapheme clusters rather than inside one.
    ///
    /// A limit too narrow for even the ellipsis returns the empty string. That
    /// is a real state — `nameMaxWidth` floors at zero on a zero-width
    /// proposal (#136) — and the alternative is drawing a glyph in a column
    /// that has no room for it.
    static func visible(_ name: String, size: CGFloat, limit: CGFloat) -> String {
        guard !name.isEmpty, size > 0, size.isFinite, limit.isFinite else { return "" }
        guard limit > 0 else { return "" }
        guard width(name, size: size) > limit else { return name }

        let characters = Array(name)
        var kept = ""
        for count in 1...characters.count {
            let candidate = String(characters.prefix(count)) + ellipsis
            guard width(candidate, size: size) <= limit else { break }
            kept = candidate
        }
        // Nothing fit beside the ellipsis; the ellipsis alone may still.
        if kept.isEmpty, width(ellipsis, size: size) <= limit { return ellipsis }
        return kept
    }

    /// Whether the row will end this name in an ellipsis.
    ///
    /// Derived from `visible` rather than measured separately, so the warning
    /// and the text under it are one decision. They were two — a pair of
    /// `.onGeometryChange` callbacks feeding one comparison — and could be seen
    /// disagreeing for a frame, the warning already showing over a name still
    /// drawn in full.
    static func isCut(_ name: String, size: CGFloat, limit: CGFloat) -> Bool {
        visible(name, size: size, limit: limit) != name
    }
}
