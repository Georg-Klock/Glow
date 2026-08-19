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
    static let range: ClosedRange<Double> = 1...12
    static let defaultValue: Double = 6

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
    /// Zero at 1x, one at the default, and capped above it. Without this the
    /// slider would do nothing visible on a screen with no headroom, and
    /// nothing at all in a screenshot.
    static func haloScale(for peak: Double) -> Double {
        let normalised = (clamp(peak) - range.lowerBound) / (defaultValue - range.lowerBound)
        return min(max(normalised, 0), 1.7)
    }
}
