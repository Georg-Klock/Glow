import Foundation
import Testing
@testable import Glow

/// #366: the picker's cap and the widget's capacity are two numbers that have
/// to be one.
///
/// `IntentCollectionSize(min:max:)` takes `_const Int`, so the cap the system
/// enforces must be a compile-time constant — it cannot be
/// `WidgetMetrics.largeRowCapacity`, which is derived from the frame. The
/// duplication is forced by the language, so this is the seam that keeps it
/// honest: if the geometry moves and the capacity with it, this fails and names
/// the number that did not follow.
///
/// Without it the failure is silent and specific: a picker that accepts five
/// rows on a widget that draws four, which is the shape of #366 itself.
@Suite("The picker's cap is the widget's capacity")
struct WidgetRowLimitTests {
    /// The large family's own derivation, the same one `WidgetMetricsTests`
    /// asserts is ten.
    @Test("Large accepts exactly what a large widget draws")
    func largeMatches() {
        #expect(WidgetRowLimit.large == WidgetMetrics.largeRowCapacity)
    }

    /// Medium has no `WidgetMetrics` accessor of its own — it is measured from
    /// the family's size the way `WidgetMetricsTests` measures it, so this
    /// recomputes it from the same inputs rather than restating four.
    @Test("Medium accepts exactly what a medium widget draws")
    func mediumMatches() {
        let size = WidgetMetrics.size(of: .systemMedium)
        let track = WidgetMetrics.largeWidth
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        let capacity = WidgetMetrics.rowCapacity(
            height: size.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
            slot: SlotLayout.slotHeight(trackWidth: track),
            hasHeader: false
        )
        #expect(WidgetRowLimit.medium == capacity)
    }

    /// The cap is useless if it is not the smaller claim: a limit above the
    /// capacity would let the view go back to cutting rows silently.
    @Test("Neither cap exceeds what the family can draw")
    func capsNeverExceedCapacity() {
        #expect(WidgetRowLimit.large <= WidgetMetrics.largeRowCapacity)
        #expect(WidgetRowLimit.medium < WidgetRowLimit.large)
    }

    /// **The literals in the intent are the ones the system enforces**, and
    /// nothing in Swift can tie them to `WidgetRowLimit`: `_const` rejects a
    /// `static let`, so `max: 4` has to be written out. That makes the source
    /// the only place the real cap exists, and a scan the only way to check it
    /// — the same shape as `WidgetPlacementTests`' scan for #254's
    /// interpolated literal.
    @Test("The size: literals in the intent are the documented caps")
    func sourceLiteralsMatchTheLimits() throws {
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Glow/Store/WeekWidgetConfig.swift")
        let source = try String(contentsOf: config, encoding: .utf8)

        // The scan is only worth anything if it found the file and the
        // declaration in it.
        #expect(source.contains("@Parameter(title: \"Habits\", size: ["),
                "the per-family size: declaration is not where the scan looks")

        for (family, limit) in [
            ("systemMedium", WidgetRowLimit.medium),
            ("systemLarge", WidgetRowLimit.large),
        ] {
            let expected = ".\(family): IntentCollectionSize(min: 0, max: \(limit))"
            #expect(source.contains(expected),
                    "the intent does not cap .\(family) at \(limit): expected \(expected)")
        }
    }
}
