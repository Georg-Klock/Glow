import Foundation

/// The gate in front of Reset to Default Habits: what counts as having typed
/// the word (#193).
///
/// Four lines, in `Logic/` rather than in the view, because of what it guards.
/// Every other rule that decides whether a write may happen — the rest day, the
/// day still to come, the blank row — is a pure function with a test on it, and
/// this one stands in front of the only action in the app that deletes
/// everything at once. A rule that lives inside a `.disabled(…)` is a rule
/// nothing can assert.
enum ResetConfirmation {
    /// The word the person has to type.
    ///
    /// Shown in the field's placeholder and named in the Settings footer, so it
    /// is declared once and read by all three.
    static let word = "RESET"

    /// Whether `typed` is that word.
    ///
    /// **Trimmed, and case-insensitive.** #193 wrote the check as
    /// `text != "RESET"` and this is deliberately looser in the one dimension
    /// that carries no intent: typing `reset` is exactly as deliberate an act
    /// as typing `RESET`, and a confirm button that stays dead over a shift key
    /// — with nothing on screen saying why — is a worse outcome than the one the
    /// strictness was guarding against. The field asks for capitals with
    /// `.textInputAutocapitalization(.characters)`, so most people never meet
    /// the difference; this is for the person who does.
    ///
    /// Whitespace goes for the same reason: a trailing space from a keyboard's
    /// autocomplete is not a change of mind.
    ///
    /// Everything the gate is for survives. The word still has to be that word,
    /// in full, and it still has to be **typed** rather than tapped — which is
    /// the whole difference between this and an alert one stray tap dismisses.
    /// Nothing here accepts a prefix, a substring or an empty field.
    static func isConfirmed(_ typed: String) -> Bool {
        typed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(word) == .orderedSame
    }
}
