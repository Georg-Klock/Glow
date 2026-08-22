import ActivityKit
import SwiftUI
import WidgetKit

/// The Dynamic Island's two seconds.
///
/// **This is ActivityKit, not a notification.** There is no API for "show
/// something in the Island" — the Island renders a Live Activity — so the pop
/// is a session that is requested and ended almost immediately.
///
/// All four presentations have to be drawn and the system picks; there is no
/// choosing which one appears. The compact pair is the common case and gets the
/// line itself; `minimal` has room for a glyph and nothing else.
///
/// It glows, in the sense that everything lit in this app does — the same
/// `glowing` modifier and the same HDR tile. **Whether that survives the
/// Island's rendering is unmeasured.** This project already wrote the widget
/// off as unable to glow on exactly this reasoning — a separate process that
/// archives its render — and that was wrong when it was finally measured, so
/// the assumption is not being made in either direction here. It needs a
/// device, and the answer belongs in docs/glow.md whichever way it goes.
struct GoalPopActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoalPopAttributes.self) { context in
            // The Lock Screen / banner presentation. Reachable even though the
            // pop is aimed at the Island, so it is drawn rather than left to
            // whatever the system makes of an empty view.
            HStack(spacing: 8) {
                mark
                Text(context.state.line)
                    .font(.system(size: WidgetMetrics.textSize, weight: .medium))
                    .glowing(halo: GlowPalette.labelHalo)
                Spacer(minLength: 0)
                Text(context.state.habitName)
                    .font(.system(size: WidgetMetrics.textSize))
                    .foregroundStyle(GlowPalette.labelResting)
                    .lineLimit(1)
            }
            .padding(.horizontal, WidgetMetrics.padLeading)
            .padding(.vertical, 12)
            .activityBackgroundTint(GlowPalette.widgetBackground)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.line)
                            .font(.system(size: WidgetMetrics.textSize + 4, weight: .medium))
                            .glowing(halo: GlowPalette.labelHalo)
                        Text(context.state.habitName)
                            .font(.system(size: WidgetMetrics.textSize))
                            .foregroundStyle(GlowPalette.labelResting)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                mark
            } compactTrailing: {
                // The line, and the reason it is short: the system truncates
                // what does not fit here rather than wrapping it.
                Text(context.state.line)
                    .font(.system(size: WidgetMetrics.textSize))
                    .glowing(halo: GlowPalette.labelHalo)
                    .lineLimit(1)
            } minimal: {
                mark
            }
        }
    }

    /// The app's own mark, at the size the Island has room for: a completion.
    private var mark: some View {
        GlowImageView(
            size: CGSize(width: WidgetMetrics.headerHeight, height: WidgetMetrics.headerHeight),
            shape: .dot
        )
    }
}
