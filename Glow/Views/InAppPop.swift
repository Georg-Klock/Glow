import SwiftUI

/// The pop, said inside the app.
///
/// **#103 decided the app would stay quiet, and that is reversed here** (PR #275).
/// The Island does not render a Live Activity while its own app is in the
/// foreground — measured, and still true — so a completion logged in the app
/// fired a pop nobody could see. #103's answer was to stop firing it and let
/// the app's own acknowledgement stand: the ring closes, the label dims, the
/// row goes quiet.
///
/// In use that reads as the app saying *less* the moment you are actually
/// looking at it. The pop is wanted every time, so the app draws its own rather
/// than asking the Island for one it will not show.
///
/// It is the Live Activity's Lock Screen presentation, not a new design: the
/// same mark, the same glowing line, the same habit name in grey, at the same
/// metrics. Two surfaces saying one thing the same way — and `GoalPop.lines`
/// and `PopPreferences.allows` are shared with `GoalPopCentre` so they cannot
/// drift on *what* is said, or on whether it is said at all.
struct InAppPop: View {
    let content: PopContent

    /// What one pop says. The Island's `ContentState` in app-side form; kept
    /// separate rather than imported so the app does not depend on ActivityKit
    /// to draw a capsule.
    struct PopContent: Equatable, Identifiable {
        let id: UUID
        let habitName: String
        let line: String
    }

    var body: some View {
        HStack(spacing: 8) {
            // The dot, at the size a completed slot draws — the mark this pop
            // is about, rather than an icon invented for it.
            GlowImageView(size: CGSize(width: mark, height: mark), shape: .dot)
                .frame(width: mark, height: mark)

            Text(content.line)
                .font(.system(size: WidgetMetrics.textSize, weight: .medium))
                .glowing()

            Spacer(minLength: 0)

            // Not `privacySensitive` here, unlike the Lock Screen and Island
            // presentations (#141). Those are readable by anyone holding the
            // phone; this one is inside the app, which is already past the
            // lock, and redacting a name the person is looking at on the row
            // above would be theatre.
            Text(content.habitName)
                .font(.system(size: WidgetMetrics.textSize))
                .foregroundStyle(GlowPalette.grey)
                .lineLimit(1)
        }
        .padding(.horizontal, WidgetMetrics.padLeading)
        .padding(.vertical, 12)
        .background(Capsule().fill(GlowPalette.widgetBackground))
        // The ground is black and so is the pill, so without an edge it reads
        // as text floating over the grid rather than as a thing that arrived.
        .overlay(Capsule().strokeBorder(GlowPalette.grey, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.line). \(content.habitName)")
    }

    private var mark: CGFloat { GlowShape.dotDiameter }
}
