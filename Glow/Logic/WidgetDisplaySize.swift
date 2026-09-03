import Foundation
import WidgetKit

/// The point frames WidgetKit has actually rendered on this device.
///
/// `WidgetMetrics` remains the authored design coordinate system: render
/// baselines and row-count intent need one stable reference. A Home Screen
/// frame is environmental, though, and `TimelineProviderContext.displaySize`
/// is the only public exact answer. The extension records that answer in the
/// App Group; the app's catalog uses it for the preview's outer frame.
enum WidgetDisplaySize {
    struct Snapshot: Equatable, Sendable {
        fileprivate let small: CGSize?
        fileprivate let medium: CGSize?
        fileprivate let large: CGSize?

        /// Exact when WidgetKit has rendered this family on this device;
        /// otherwise the stable design frame is the honest fallback.
        func referenceSize(of family: WidgetFamily) -> CGSize {
            measuredSize(of: family) ?? WidgetMetrics.size(of: family)
        }

        func measuredSize(of family: WidgetFamily) -> CGSize? {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .systemLarge: large
            default: nil
            }
        }

        /// Two Small widgets share a Medium widget's Home Screen footprint.
        /// Use the measured space between them only when both ends of that
        /// subtraction came from WidgetKit; mixing one measured frame with one
        /// fallback would invent a gutter no device reported.
        var smallGutter: CGFloat {
            guard let small, let medium else {
                return WidgetMetrics.largeWidth - WidgetMetrics.smallSide * 2
            }
            return max(0, medium.width - small.width * 2)
        }
    }

    static func record(
        _ size: CGSize,
        for family: WidgetFamily,
        store: UserDefaults = GlowSettings.store
    ) {
        guard let key = key(for: family), isPlausible(size) else { return }
        // One property-list write keeps width and height from ever belonging
        // to two different provider calls after a crash.
        store.set(
            ["width": Double(size.width), "height": Double(size.height)],
            forKey: key
        )
    }

    static func snapshot(store: UserDefaults = GlowSettings.store) -> Snapshot {
        Snapshot(
            small: read(.systemSmall, store: store),
            medium: read(.systemMedium, store: store),
            large: read(.systemLarge, store: store)
        )
    }

    private static func read(_ family: WidgetFamily, store: UserDefaults) -> CGSize? {
        guard
            let key = key(for: family),
            let value = store.dictionary(forKey: key),
            let width = value["width"] as? NSNumber,
            let height = value["height"] as? NSNumber
        else { return nil }
        let size = CGSize(width: width.doubleValue, height: height.doubleValue)
        return isPlausible(size) ? size : nil
    }

    private static func key(for family: WidgetFamily) -> String? {
        switch family {
        case .systemSmall: "widgetDisplaySize.small"
        case .systemMedium: "widgetDisplaySize.medium"
        case .systemLarge: "widgetDisplaySize.large"
        default: nil
        }
    }

    /// Refuse zero from an unsettled layout and corrupt/defaults-edited values.
    /// Every iPhone widget family is comfortably inside this broad envelope.
    private static func isPlausible(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && (100...600).contains(size.width)
            && (100...600).contains(size.height)
    }
}
