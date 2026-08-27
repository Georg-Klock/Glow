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
/// The Island presentations keep the `glowing` modifier, though the Island
/// itself was measured not to honour it — chronod re-renders the content and
/// the headroom does not survive (docs/glow.md, 2026-08-25). The modifier
/// stays because it is also this app's spelling for "lit white", and costs
/// nothing where the compositor flattens it.
///
/// **The Lock Screen banner is inverted: white ground, black type** (#311).
/// The decided scope is exactly what the app controls, and the SDK draws that
/// line clearly. Checked against the iOS 26.5 SDK's `WidgetKit.swiftinterface`,
/// not against memory: `DynamicIsland` exposes `widgetURL`, `keylineTint` and
/// `contentMargins` and nothing else — no API recolors the island surface, so
/// the compact and minimal pill *and the expanded presentation's background*
/// are system-owned chrome and stay as they are. `activityBackgroundTint`
/// (WidgetKit's one background API, a plain `View` modifier) reaches the Lock
/// Screen / banner presentation, which is therefore the one surface that can
/// invert, and does.
///
/// **The type is as large and bold as each presentation carries** (#310):
/// `PopType` below, one named size per presentation, measured rather than
/// shared — the compact trailing region truncates, the expanded region wraps,
/// and the banner has the most room of the three.
struct GoalPopActivity: Widget {
    /// Per-presentation sizes for `context.state.line` (#310). The bounds are
    /// different in kind: compact truncates what does not fit, expanded wraps
    /// it, the banner shares its row with the habit's name. Measured in the
    /// simulator (iPhone 17 Pro, iOS 26.5) against the longest line the app
    /// writes — "that's the week", `GoalPop` — and the device look is the
    /// final word:
    ///
    ///  - compact: 16 and bold truncated ("that's the…"), 12 clipped its first
    ///    glyph — the region cannot carry fifteen characters at any pushed
    ///    size, so the line *scales to fit* from 16: short lines render the
    ///    full size, the longest shrinks and survives whole.
    ///  - expanded: 32 fills the width unwrapped; the scale factor below is
    ///    the guard for narrower islands, not the plan.
    ///  - banner: 20 sits beside the name without crowding it.
    private enum PopType {
        static let lockScreen: CGFloat = 20
        static let expanded: CGFloat = 32
        static let compact: CGFloat = 16
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoalPopAttributes.self) { context in
            // The Lock Screen / banner presentation. Reachable even though the
            // pop is aimed at the Island, so it is drawn rather than left to
            // whatever the system makes of an empty view.
            HStack(spacing: 8) {
                // Black on the inverted ground, drawn plainly: `GlowImageView`
                // exists to draw a *lit* mark, and on a white banner the mark
                // is ink, not light. Same dot, same box, no glow to lose —
                // the banner's glow was never measured and the inversion makes
                // the question moot on this surface.
                invertedMark
                Text(context.state.line)
                    .font(.system(size: PopType.lockScreen, weight: .bold))
                    .foregroundStyle(.black)
                Spacer(minLength: 0)
                // Redacted on a locked phone. This presentation is the Lock
                // Screen one, so the habit's name — which is whatever a person
                // typed, and can be a great deal more revealing than "Workout"
                // — would otherwise be readable by anyone holding the device.
                // The line beside it is ours and says nothing personal, so the
                // pop still reads as an acknowledgement while locked; it just
                // does not say what of. See #141.
                Text(context.state.habitName)
                    .font(.system(size: WidgetMetrics.textSize))
                    .foregroundStyle(.black.opacity(0.45))
                    .lineLimit(1)
                    .privacySensitive()
            }
            .padding(.horizontal, WidgetMetrics.padLeading)
            .padding(.vertical, 12)
            // The one surface `activityBackgroundTint` reaches — see the type
            // comment. White, so the banner is the app's palette inverted
            // rather than a third colour scheme.
            .activityBackgroundTint(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.line)
                            .font(.system(size: PopType.expanded, weight: .bold))
                            // The guard, not the plan: 32 fits the longest
                            // line on the widest island unwrapped, and a
                            // narrower device shrinks the line instead of
                            // wrapping it into the region below.
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .glowing(halo: GlowPalette.labelHalo)
                        // The Island is visible on a locked phone too, so the
                        // name is redacted here for the same reason. See #141.
                        Text(context.state.habitName)
                            .font(.system(size: WidgetMetrics.textSize))
                            .foregroundStyle(GlowPalette.grey)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
            } compactLeading: {
                mark
            } compactTrailing: {
                // The line, and the reason it is short: the system truncates
                // what does not fit here rather than wrapping it.
                Text(context.state.line)
                    .font(.system(size: PopType.compact, weight: .bold))
                    .minimumScaleFactor(0.6)
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

    /// The same dot in the same box, as ink for the inverted banner (#311).
    private var invertedMark: some View {
        Circle()
            .fill(.black)
            .frame(width: GlowShape.dotDiameter, height: GlowShape.dotDiameter)
            .frame(width: WidgetMetrics.headerHeight, height: WidgetMetrics.headerHeight)
    }
}
