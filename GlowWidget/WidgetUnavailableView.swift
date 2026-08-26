import SwiftUI

/// What a widget draws when the store did not answer (#282).
///
/// **Deliberately not the empty state.** "No habits yet" is a claim about the
/// record — the store was read and holds nothing — and a failed container or
/// fetch cannot make it. This is the other sentence: the data is there, this
/// process could not read it, and the app is where that gets fixed. Both
/// widgets already open the app on any non-mark tap (`widgetURL`), so the
/// whole surface is the recovery action; a launch that hits the same failure
/// lands on `StoreUnavailableView`, which is the app's own recovery screen.
///
/// Says nothing about *why* — a widget cannot diagnose or repair a store, and
/// an error's own text can carry a path or a name (#282's rule). One glyph,
/// two short lines, the palette's grey: quiet, because the failure is almost
/// always transient and the widget will be asked again.
struct WidgetUnavailableView: View {
    var body: some View {
        VStack(spacing: 6) {
            // The same glyph as `StoreUnavailableView`, because the widget's
            // deep link lands there when the app hits the same failure: two
            // surfaces, one problem, one drawing of it.
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.title2)
            Text("Data unavailable")
                .font(.system(size: WidgetMetrics.textSize))
            Text("Open Glow")
                .font(.system(size: WidgetMetrics.textSize).weight(.semibold))
        }
        .foregroundStyle(GlowPalette.grey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One element, one announcement: the state and the recovery action,
        // once, with no developer diagnostics to read out.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Glow's data is unavailable. Open Glow to fix this.")
    }
}
