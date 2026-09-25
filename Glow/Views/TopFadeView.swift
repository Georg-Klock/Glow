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
    /// The top inset of the window this fade is in, as last reported by
    /// `WindowSafeAreaReader`. `nil` until the fade has a window at all.
    @State private var windowSafeAreaTop: CGFloat?

    var body: some View {
        let solid = windowSafeAreaTop ?? Self.fallbackSafeAreaTop
        let height = Self.height(safeAreaTop: solid)
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
        .background {
            WindowSafeAreaReader { top in
                if windowSafeAreaTop != top { windowSafeAreaTop = top }
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// The band's full height: opaque through the safe area, then the falloff.
    static func height(safeAreaTop: CGFloat) -> CGFloat {
        max(0, safeAreaTop) + falloff
    }

    /// How far below the safe area the fade takes to reach nothing.
    ///
    /// Past the navigation bar's own height (44pt), so the falloff finishes in
    /// open content rather than at the bar's lower edge, where the handover
    /// would read as the seam this replaced.
    static let falloff: CGFloat = 64

    /// What the band reserves before its window has reported (#636).
    ///
    /// The largest inset a current iPhone has, because over-reserving here
    /// costs black on black and under-reserving is the bug. It is only ever
    /// the first frame's answer: the reader replaces it as soon as the fade is
    /// in a window, on every device, so an iPad's 24pt is not drawn at 62.
    static let fallbackSafeAreaTop: CGFloat = 62
}

/// Reports the top safe-area inset of **its own** window, and reports it
/// again whenever that changes (#636).
///
/// **A `GeometryReader` here reports zero.** The first build of this fade
/// read `proxy.safeAreaInsets.top` inside the overlay, with
/// `.ignoresSafeArea(edges: .top)` on it, and got 0 — so the gradient came
/// out 64pt tall, ended above everything it was meant to cover, and measured
/// pixel-for-pixel identical to the screen without it. Colouring the two stops
/// red and green showed the band starting at y=0 and ending at 57pt: the
/// overlay is already full-screen, so there is no inset left for a proxy to
/// report. The window still knows.
///
/// What replaced that was a static read of *whichever window was key*, taken
/// once. Right on a portrait iPhone, where there is one window and its inset
/// never moves, and wrong everywhere else: rotation and Stage Manager change
/// the inset without re-evaluating a static, and in Split View or with a
/// second scene the key window need not be this one. A view in the hierarchy
/// asks its own window, and UIKit tells it when to ask again — on entering a
/// window, on every layout pass (a rotation resizes it), and when its own
/// safe area moves.
private struct WindowSafeAreaReader: UIViewRepresentable {
    let report: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.report = report
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.report = report
    }

    final class ProbeView: UIView {
        var report: (@MainActor (CGFloat) -> Void)?
        private var reported: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publish()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publish()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            publish()
        }

        private func publish() {
            guard let top = window?.safeAreaInsets.top, top != reported else { return }
            reported = top
            // Out of the layout pass that noticed it: writing SwiftUI state
            // from inside a view update is undefined, and the one frame of
            // delay is drawn at the fallback, which over-reserves.
            //
            // The run loop rather than the main queue: a caller already
            // running on the main queue — a Swift Testing test on the main
            // actor, which is where the hosted render frames are drawn —
            // spins the run loop to settle, and main-queue work submitted
            // inside it waits until that caller returns. The band was drawn
            // at the fallback for the whole capture.
            RunLoop.main.perform(inModes: [.common]) { [report] in
                MainActor.assumeIsolated { report?(top) }
            }
        }
    }
}
