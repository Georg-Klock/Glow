import Foundation

/// How hard the glow pushes, as a user setting.
///
/// Stored in the App Group so the widget reads the same value. The widget
/// cannot render HDR, but it draws a halo in its place, and a halo that ignores
/// the setting would make the two surfaces disagree about how bright this app
/// is meant to be.
enum GlowSettings {
    static let key = "glowPeakHeadroom"

    /// Multiples of SDR white. 1x is no headroom at all, which is a legitimate
    /// "off": the slot renders as a flat capsule and the app stops glowing.
    ///
    /// The top is 12, not the 24 the encoding could carry.
    ///
    /// PQ runs to 10,000 nits — about 40x a 250-nit SDR white — so the encode
    /// was never the limit. `UIScreen.potentialEDRHeadroom` is, and it is a
    /// property of the panel *and the moment*: it moves with ambient light,
    /// display brightness and thermal state. Asking for more than it grants is
    /// not an error, it simply tone-maps back down — which makes the top of
    /// the range a slider position that does nothing, and a control that stops
    /// responding halfway is worse than one with a lower ceiling.
    ///
    /// Settings shows both numbers, so the gap is visible rather than argued
    /// about.
    static let range: ClosedRange<Double> = 1...12

    /// The top of the range. The glow is the product; there is no reason for it
    /// to open at half strength.
    static let defaultValue: Double = 12

    /// The App Group's defaults, so app and widget agree. Falls back to the
    /// app's own when the entitlement is unavailable, exactly as the store does.
    static var store: UserDefaults {
        UserDefaults(suiteName: StoreLocation.appGroupID) ?? .standard
    }

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

    /// How large the halo is relative to its default, given a peak.
    ///
    /// Zero at 1x, one at 6x, and capped above that. Without this the slider
    /// would do nothing visible on a screen with no headroom, and nothing at
    /// all in a screenshot.
    ///
    /// Pinned to 6 rather than to `defaultValue`: the halo is drawn in SDR, so
    /// it stops gaining anything long before the encode does, and tying it to a
    /// default that has since moved to 24 would have shrunk every halo to a
    /// quarter of itself.
    static let haloReference: Double = 6

    static func haloScale(for peak: Double) -> Double {
        let normalised = (clamp(peak) - range.lowerBound) / (haloReference - range.lowerBound)
        return min(max(normalised, 0), 1.7)
    }
}
