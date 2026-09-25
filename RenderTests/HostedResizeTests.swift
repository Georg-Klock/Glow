import CoreGraphics
import Foundation
import Testing
import UIKit

/// This Week survives its window changing width under it (#643).
///
/// There is no foldable iPhone simulator, and its widths are not known. What
/// can be tested now is the property one depends on, and that Stage Manager
/// and Split View already exercise on an iPad: **the layout is a function of
/// the window's width and size class alone**, so a screen resized from one to
/// another draws what a screen opened there would draw. A view that read its
/// width once and kept it — a static, a `@State` captured at first layout, a
/// cached geometry — passes every fixed-size frame in the baseline and fails
/// here.
///
/// **Only the width and the size class change.** Both surfaces keep the
/// reference phone's height and 59pt/34pt safe area, because the hosted
/// harness forces its safe area through `additionalSafeAreaInsets`, and a
/// correction made after the first layout is exactly what #481 measured
/// leaving the navigation layout behind. Moving the safe area here would test
/// that harness trap rather than the app. The widths are the narrowest
/// supported phone's 375pt, compact, and the iPad Air's 820pt, regular: the
/// two sides of `PanelCeiling`.
///
/// Compared by `RenderSignature`, the gate's own statistic, at the gate's own
/// tolerances for a hosted frame: `cellTolerance` on the cell grid and
/// `hostedBlackTolerance` on the ground share, with the size exact. Every step
/// came back signature-identical to its fresh render on iOS 26.5 and on iOS
/// 18.5 once `HostedScreenFrames` warms up; before the warm-up, the fresh
/// 375pt render was the first screen hosted in its process and differed from
/// every later one by a level in a cell. The tolerance stays because iOS 18.5
/// does not render the same picture twice (#431), and each step prints how
/// close it came. A kept width or size class moves whole columns and cells by
/// tens — `wideButCompact` below is the check that this test can see one.
@MainActor
@Suite("Hosted resize")
struct HostedResizeTests {
    typealias Surface = HostedScreenFrames.Surface

    static let narrow = Surface(
        size: CGSize(width: 375, height: 852),
        safeArea: Surface.phone.safeArea,
        horizontalSizeClass: .compact, verticalSizeClass: .regular
    )
    static let wide = Surface(
        size: CGSize(width: 820, height: 852),
        safeArea: Surface.phone.safeArea,
        horizontalSizeClass: .regular, verticalSizeClass: .regular
    )

    @Test("This Week resized 375pt → 820pt → 375pt matches a fresh render at each step")
    func resizedMatchesFresh() throws {
        try RenderBaselineTests.withPinnedScene {
            let freshNarrow = try Self.fresh(Self.narrow)
            let freshWide = try Self.fresh(Self.wide)

            // The test has to be able to fail: at 820pt the size class alone
            // must change the picture, or a host that kept its first size class
            // would pass. Measured, the compact ceiling leaves a 338pt panel
            // where the regular one draws 672pt.
            let wideButCompact = try Self.fresh(Surface(
                size: Self.wide.size, safeArea: Self.wide.safeArea,
                horizontalSizeClass: .compact, verticalSizeClass: .regular
            ))
            #expect(
                wideButCompact.signature.worstCell(against: freshWide.signature).delta
                    > RenderBaselineTests.cellTolerance,
                "at 820pt, compact and regular width draw the same picture; this test could not see a stale size class"
            )

            let host = try HostedScreenFrames.Host(screen: .weeklyGrid, surface: Self.narrow)
            defer { host.close() }

            let steps: [(name: String, surface: Surface, fresh: Rendered)] = [
                ("resize-375pt", Self.narrow, freshNarrow),
                ("resize-820pt", Self.wide, freshWide),
                ("resize-back-to-375pt", Self.narrow, freshNarrow),
            ]
            for (index, step) in steps.enumerated() {
                if index > 0 {
                    try host.resize(to: step.surface)
                }
                let image = try #require(host.capture(), "no capture at \(step.name)")
                let resized = RenderSignature(of: image)
                let worst = resized.worstCell(against: step.fresh.signature)
                let blackDelta = abs(
                    resized.exactBlackPercent - step.fresh.signature.exactBlackPercent
                )
                let sameSize = resized.width == step.fresh.signature.width
                    && resized.height == step.fresh.signature.height
                // The measurement the tolerance rests on, in every run's log.
                print("""
                    hosted-resize: \(step.name) identical=\(resized == step.fresh.signature) \
                    worst-cell=\(worst.delta) black-delta=\(blackDelta)
                    """)
                if !sameSize
                    || worst.delta > RenderBaselineTests.cellTolerance
                    || blackDelta > RenderBaselineTests.hostedBlackTolerance {
                    Self.attach(step.name, resized: image, fresh: step.fresh)
                    Issue.record("""
                        \(step.name): the resized screen does not match a fresh one at \
                        \(step.surface.size.width)pt. It renders \(resized.width)×\(resized.height) \
                        against \(step.fresh.signature.width)×\(step.fresh.signature.height); worst \
                        cell (\(worst.column),\(worst.row)) is \(worst.actual) against \
                        \(worst.expected), tolerance \(RenderBaselineTests.cellTolerance); exact \
                        black differs by \(blackDelta) points, tolerance \
                        \(RenderBaselineTests.hostedBlackTolerance). Something kept state from the \
                        previous width. Both renders and their diff are attached.
                        """)
                }
            }
        }
    }

    struct Rendered {
        let image: CGImage
        let signature: RenderSignature
    }

    private static func fresh(_ surface: Surface) throws -> Rendered {
        let host = try HostedScreenFrames.Host(screen: .weeklyGrid, surface: surface)
        defer { host.close() }
        let image = try #require(host.capture(), "no fresh capture at \(surface.size)")
        return Rendered(image: image, signature: RenderSignature(of: image))
    }

    /// Named the way the render gate names a moved frame, so the validator
    /// reads it as one: what was drawn, what it should have matched, and the
    /// cells between them.
    private static func attach(_ name: String, resized: CGImage, fresh: Rendered) {
        if let data = UIImage(cgImage: resized).pngData() {
            Attachment.record(data, named: "\(name)-actual.png")
        }
        if let data = UIImage(cgImage: fresh.image).pngData() {
            Attachment.record(data, named: "\(name)-expected.png")
        }
        if let data = RenderSignature(of: resized).diffImage(
            against: fresh.signature, tolerance: RenderBaselineTests.cellTolerance
        ) {
            Attachment.record(data, named: "\(name)-diff.png")
        }
    }
}
