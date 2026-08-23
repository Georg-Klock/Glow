import SwiftUI

/// The strip that says the app is not looking at the real day (#204).
///
/// **This cannot be silent.** The override writes real completions dated to the
/// simulated day, so once a tap has landed there is nothing in the store that
/// distinguishes a simulated Friday from a real one. The one thing that has to
/// stay obvious is that it is *on* — on every screen that reads it, for as long
/// as it is set, in the same persistent shape `LowPowerBanner` uses for the
/// other condition that changes what the app is showing.
///
/// Two screens read it: This Week and History. Settings needs no banner,
/// because the row that set it is on the screen. #204 named three, the third
/// being Today, which came out with the per-day kind (#209).
///
/// **One tap clears it**, rather than sending you back to Settings. Leaving the
/// override on should never be more convenient than turning it off.
///
/// Self-observing: it reads `DebugToday` on appear, on every defaults change,
/// and on becoming active, so flipping the switch in the Settings tab makes it
/// appear here without this screen being redrawn for any other reason. The
/// screens it sits on watch the same signal for their own `today`.
struct DebugTodayBanner: View {
    /// The screen's own margin, because the screens it sits on do not share one.
    ///
    /// **Applied inside the `if`, not by the caller.** Padding applied to this
    /// view from outside would still be padding when there is no banner, and a
    /// 10pt gap above every screen whenever the override is off is exactly the
    /// kind of not-inert this change must not be.
    var horizontalPadding: CGFloat = 16

    @Environment(\.scenePhase) private var scenePhase
    @State private var override: Date?

    var body: some View {
        Group {
            if let override {
                Button {
                    DebugToday.set(nil)
                    refresh()
                } label: {
                    label(for: override)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Simulating \(DebugToday.dayName(override)). "
                        + "Today is really \(DebugToday.dayName(WeekCalendar.realToday())). "
                        + "Tap to reset."
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 10)
            }
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // A week boundary crossed while suspended expires the override,
            // and `DebugToday` clears it on the next read — which is this one.
            if phase == .active { refresh() }
        }
    }

    private func label(for override: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(GlowPalette.warning)
            Text(
                "Viewing as \(DebugToday.dayName(override)) — "
                    + "today is \(DebugToday.dayName(WeekCalendar.realToday()))"
            )
            .font(.footnote)
            .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("Reset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlowPalette.warning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(GlowPalette.warning.opacity(0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(GlowPalette.warning.opacity(0.45), lineWidth: 1)
        }
    }

    private func refresh() {
        let current = DebugToday.override()
        if current != override { override = current }
    }
}
