import SwiftUI
import UIKit

/// Black at the top of the screen, fading out below it.
///
/// A property of the top of the screen rather than of any one thing under it:
/// whatever scrolls up there dissolves rather than being cut at the list's clip
/// boundary. Measured at rest on Settings, scrolled 200pt: the preview capsule
/// sat at 100–143pt reading 249,249,248 with the inline title printed on top of
/// it — so the navigation bar's own background is not the opaque black
/// `.toolbarBackground(.visible, for:)` was read as granting, and a hard cut is
/// what was holding the light back. See #195.
///
/// Its own type because three screens need it (#210, #454): Settings scrolls a
/// lit preview under the bar, the Widgets tab scrolls four of them, and This
/// Week now moves its panel with its rows. A copied gradient whose every number
/// was measured is a copy that drifts.
///
/// Opaque through the safe area, so nothing is ever lit beside the Dynamic
/// Island, and the falloff resolves below the bar rather than at it: reserve
/// past the falloff, do not clip at it.
///
/// **`ignoresSafeArea` is load-bearing, and it is not about the status bar.**
/// Without it the overlay's top edge is the *content's* top edge, which a
/// `NavigationStack` puts below the whole navigation bar: coloured red and
/// green and screenshotted, the band started at 167pt — under the large title,
/// over the preview, nowhere near the screen's top. With it the band starts
/// at 0.
///
/// It draws over the content and under the bar, which is what makes it safe
/// where a `Color` on `.toolbarBackground` was not: screenshotted scrolled, the
/// inline title renders at full white on top of the band. The system status bar
/// and the Dynamic Island are above it too.
struct TopFade: View {
    var body: some View {
        let solid = Self.safeAreaTop
        let height = solid + Self.falloff
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: solid / height),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// How far below the safe area the fade takes to reach nothing.
    ///
    /// Past the navigation bar's own height (44pt), so the falloff finishes in
    /// open content rather than at the bar's lower edge, where the handover
    /// would read as the seam this replaced.
    private static let falloff: CGFloat = 64

    /// Where the safe area ends, from the window rather than from a
    /// `GeometryReader`.
    ///
    /// **A `GeometryReader` here reports zero.** The first build of this fade
    /// read `proxy.safeAreaInsets.top` inside the overlay, with
    /// `.ignoresSafeArea(edges: .top)` on it, and got 0 — so the gradient came
    /// out 64pt tall, ended above everything it was meant to cover, and
    /// measured pixel-for-pixel identical to the screen without it. Colouring
    /// the two stops red and green showed the band starting at y=0 and ending
    /// at 57pt: the overlay is already full-screen, so there is no inset left
    /// for a proxy to report. The window still knows.
    ///
    /// The fallback is the largest inset a current iPhone has, because
    /// over-reserving here costs black on black and under-reserving is the bug.
    private static var safeAreaTop: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window?.safeAreaInsets.top ?? 62
    }
}
