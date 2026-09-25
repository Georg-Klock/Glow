import SwiftUI
import Testing
import UIKit

@testable import Glow

/// The top fade's height follows the window it is in, not whichever window
/// happens to be key, and not a value read once (#636).
///
/// It used to be a static read of the key window's inset with an iPhone
/// fallback of 62pt. Rotation, Stage Manager and Split View all change or
/// split that answer, and none of them re-evaluated it.
@MainActor
struct TopFadeTests {
    @Test(arguments: [0, 24, 47, 59, 62] as [CGFloat])
    func bandIsOpaqueThroughTheInsetThenFalls(inset: CGFloat) {
        #expect(TopFade.height(safeAreaTop: inset) == inset + TopFade.falloff)
    }

    @Test func negativeInsetReservesOnlyTheFalloff() {
        #expect(TopFade.height(safeAreaTop: -10) == TopFade.falloff)
    }

    /// Hosted in a window that is deliberately *not* key, the band is drawn at
    /// that window's inset rather than at the fallback.
    ///
    /// **What this cannot tell apart** is the band's own window from the key
    /// window: every window joined to a scene inherits the device's inset
    /// whatever its frame (#481), and a window with no scene never lays the
    /// reader out, so there is no pair of windows here with two different
    /// answers. What it does hold is the mechanism — the reader runs, reports,
    /// and the band redraws off the fallback — wherever the device's inset is
    /// not 62, which includes both baseline phones (47pt).
    @Test func hostedBandReadsItsOwnWindow() {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let keyWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        keyWindow.windowScene = scene
        keyWindow.rootViewController = UIViewController()

        let host = UIHostingController(rootView: TopFade())
        // Otherwise `sizeThatFits` adds the host's own insets to the band.
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.windowScene = scene
        window.rootViewController = host
        window.isHidden = false
        keyWindow.makeKeyAndVisible()
        #expect(!window.isKeyWindow)

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.view.layoutIfNeeded()

        let measured = host.sizeThatFits(in: CGSize(width: 402, height: 2000)).height
        #expect(measured == window.safeAreaInsets.top + TopFade.falloff)

        window.isHidden = true
        keyWindow.isHidden = true
    }
}

