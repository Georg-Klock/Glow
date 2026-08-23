import Foundation
import WidgetKit

/// What is actually on the Home Screen, asked of WidgetKit.
///
/// The whole implementation is one call and a map, and that is the point: the
/// diff it feeds is in `WidgetCatalog`, pure and tested, while this side owns
/// the part no test can arrange — a live system service answering for a
/// particular device's Home Screen. See `WidgetPlacementQuerying`.
///
/// **A snapshot, not a subscription.** `currentConfigurations()` answers for
/// the moment it is called; nothing tells the app when a widget is placed or
/// removed, because placing one happens while the app is not frontmost. The
/// Widgets tab asks again on `scenePhase == .active`, which is the same shape
/// of staleness `WeeklyGridView` handles for the day rolling over.
///
/// `currentConfigurations()` rather than the `getCurrentConfigurations`
/// callback: the same query, and iOS 18 is this app's floor, so there is
/// nothing to bridge.
struct WidgetCenterPlacements: WidgetPlacementQuerying {
    func placedWidgets() async throws -> [PlacedWidget] {
        try await WidgetCenter.shared.currentConfigurations().map {
            // `kind` and `family` are what the diff needs; `configuration` is
            // the month widget's chosen habit, which does not change whether
            // the widget is there.
            PlacedWidget(kind: $0.kind, family: $0.family)
        }
    }
}
