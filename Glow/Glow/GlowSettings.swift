import Foundation

/// How hard the glow pushes, as a user setting.
///
/// Stored in the App Group so the widget reads the same value. Both surfaces
/// encode the same tile from it, and one that ignored the setting would make
/// the two disagree about how bright this app is meant to be.
enum GlowSettings {
    /// Which one object occupies Settings' fixed preview footprint.
    enum PreviewState: Equatable {
        case glow
        case lowPower
    }

    static func previewState(lowPower: Bool) -> PreviewState {
        lowPower ? .lowPower : .glow
    }

    struct Readout: Equatable {
        let text: String
        let isWarning: Bool
        let accessibilityLabel: String
    }

    /// One fixed-height status row beneath the slider (#506).
    ///
    /// At the floor, screen headroom is deliberately absent: it describes
    /// capacity the glow is not asking for and made ordinary white sound lit.
    /// VoiceOver keeps the fuller reassurance that used to live on the inert
    /// preview capsule. Above the floor, the established headroom sentence is
    /// unchanged.
    static func readout(peak: Double, headroomSummary: String) -> Readout {
        guard peak > range.lowerBound else {
            return Readout(
                text: "Glow off — white looks like ordinary white.",
                isWarning: true,
                accessibilityLabel: "Glow off. Today's slot still shows, unlit."
            )
        }
        let text = String(format: "Aiming for %.0f×", peak) + " — " + headroomSummary
        return Readout(text: text, isWarning: false, accessibilityLabel: text)
    }

    static let key = "glowPeakHeadroom"

    /// Multiples of SDR white. 1x is no headroom at all, which is a legitimate
    /// "off": the slot renders as a flat capsule and the app stops glowing.
    ///
    /// The top is 8, not the 24 the encoding could carry — and no longer the 12
    /// it shipped at.
    ///
    /// PQ runs to 10,000 nits — about 40x a 250-nit SDR white — so the encode
    /// was never the limit. `UIScreen.potentialEDRHeadroom` is, and it is a
    /// property of the panel *and the moment*: it moves with ambient light,
    /// display brightness and thermal state. Asking for more than it grants is
    /// not an error, it simply tone-maps back down — which makes the top of
    /// the range a slider position that does nothing, and a control that stops
    /// responding halfway is worse than one with a lower ceiling. 8 is what
    /// `potentialEDRHeadroom` reports on the reference device (docs/glow.md),
    /// so the ceiling now sits where the panel's does instead of a third above
    /// it.
    ///
    /// Settings shows both numbers, so the gap is visible rather than argued
    /// about.
    static let range: ClosedRange<Double> = 1...8

    /// Every value the integer-stepped Settings slider can reach. Kept beside
    /// the range so launch warming cannot silently miss a newly added stop.
    static let sliderStops = (Int(range.lowerBound)...Int(range.upperBound)).map(Double.init)

    /// 2x on an 8x ceiling: the glow opens at a quarter strength, on purpose.
    ///
    /// This reverses the rule the default used to carry — "the glow is the
    /// product; there is no reason for it to open at half strength", which
    /// pinned it to the top of the range and had a test holding it there. The
    /// visuals are being iterated on and full strength turned out to be the
    /// wrong opening statement: the default is now a quiet glow, and the top of
    /// the range is a slider position rather than the first impression. See
    /// docs/decisions.md.
    static let defaultValue: Double = 2

    /// The App Group's defaults, so app and widget agree. Falls back to the
    /// app's own when the entitlement is unavailable, exactly as the store does.
    ///
    /// **Under tests this is a private suite, and that is a correctness fix
    /// rather than tidiness** (#168). `WeekPreferences.restDay` lives here, one
    /// value for the whole store, and it *outlives the process*. A test that
    /// sets one and dies before its `defer` runs — a crash, a cancelled run, or
    /// a hard trap like the SwiftData precondition #145 is about — leaves the
    /// value written into the simulator's App Group defaults. Every later run
    /// on that simulator then inherits it, and a whole weekday quietly
    /// disappears from generated history.
    ///
    /// That is not hypothetical: it was found as `weekRestDay = 7` sitting on
    /// the simulator `Tools/test.sh` picks, turning 42 tests red while the same
    /// commit passed on CI and on a second simulator. `TestPreferences`
    /// restores correctly; restoring is simply not something a dead process
    /// does.
    ///
    /// Keyed by process id, so two test targets running at once cannot share
    /// one either, and cleared on first use so every process starts from
    /// nothing. Production is untouched — no test bundle, no override.
    static var store: UserDefaults {
        if let testStore { return testStore }
        return UserDefaults(suiteName: StoreLocation.appGroupID) ?? .standard
    }

    /// Whether this process is hosting a test bundle.
    ///
    /// Named once and read twice: it decides that tests get a private defaults
    /// suite (#168), and that the test host does not build the app's interface
    /// (#179). Both are the same idea — a test process should not be running
    /// the app.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    /// A private, per-process defaults suite when running under a test bundle.
    ///
    /// `nil` in the app and in the widget, so neither pays for this.
    /// `nonisolated(unsafe)` because `UserDefaults` is not `Sendable` and this
    /// is a `let` initialised once: there is no mutable state to race on, and
    /// `UserDefaults` is itself thread-safe. The same reasoning `store` above
    /// relies on every time it hands one out.
    private nonisolated(unsafe) static let testStore: UserDefaults? = {
        guard isRunningTests else { return nil }

        let suite = "\(StoreLocation.appGroupID).tests.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        // A recycled process id would otherwise hand this run the last one's
        // leftovers, which is the bug wearing a smaller hat.
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()

    /// The stored value, clamped. An out-of-range number could otherwise arrive
    /// from a future build, a synced default, or a hand-edited plist, and a
    /// headroom of 400 is not a brighter glow — it is an encode that no display
    /// can tone-map sensibly.
    static var peakHeadroom: Double {
        let stored = store.object(forKey: key) as? Double
        return clamp(stored ?? defaultValue)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
