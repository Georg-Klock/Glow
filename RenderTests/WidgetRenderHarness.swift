import SwiftUI

/// Keeps widget pixel tests about pixels rather than AppIntent archiving.
///
/// `SlotToggle` deliberately has two adapters around one toggle style: the
/// installed widget uses an AppIntent-backed `Toggle`, while the app's Widgets
/// tab uses an ordinary binding and hands the resulting absolute-state request
/// to `InAppWidgetMarkAction`. Both adapters render the exact same
/// `SlotMarkToggleStyle` faces.
///
/// `ImageRenderer` is neither host. On iOS 18 it spends minutes flattening the
/// archived AppIntent controls, and #508 multiplied those controls from today
/// alone to every nonfuture day. The minimum-OS gate consequently reached the
/// workflow's one-hour ceiling after every logic test had passed. Pixel tests
/// use the ordinary adapter with a no-op action: no tap is delivered here, the
/// production AppIntent path remains covered by source/placement tests, and
/// the rendered marks remain the shipping style.
extension View {
    func widgetPixelHarness() -> some View {
        environment(\.isInAppWidgetPreview, true)
            .environment(
                \.inAppWidgetMarkAction,
                InAppWidgetMarkAction { _, _, _, _ in }
            )
    }
}
