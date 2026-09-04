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
/// archived AppIntent controls, and #508 once multiplied those controls from
/// today alone to every nonfuture day. The minimum-OS gate consequently reached
/// the workflow's one-hour ceiling after every logic test had passed. #543 made
/// widgets today-only again, but `ImageRenderer` is still not the installed
/// host and the adapter remains the deterministic pixel-test boundary. No tap
/// is delivered here; source/placement tests cover the production AppIntent
/// path, and the rendered marks remain the shipping style.
extension View {
    func widgetPixelHarness() -> some View {
        environment(\.isInAppWidgetPreview, true)
            .environment(
                \.inAppWidgetMarkAction,
                InAppWidgetMarkAction { _, _, _, _ in }
            )
    }
}
