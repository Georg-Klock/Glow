import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

/// A committed, reviewed picture of what every widget family looks like — and,
/// since #386, of the rows and the weekday header the app draws for itself —
/// and a gate that goes red when one of them changes without anyone approving
/// it.
///
/// #138. The render tests next door already sample pixels, and they already
/// print numbers: `bg-audit: week small exact-black 97.3%`. Printing is not a
/// gate. A layout that moves a whole column, a mark that stops being drawn, a
/// row pitch that shifts by four points — none of those breaks an invariant
/// any of those tests names, so all of them pass while the widget is wrong.
///
/// ## What a baseline is here
///
/// Not a PNG diff. The design export the neighbouring suite waits on is a flat
/// mockup of an HDR app and disagrees with the render by 90% of its pixels on
/// purpose; adopting it as a baseline would be adopting a number nobody
/// derived. See `DesignReference/README.md` and #138.
///
/// The baseline is a **16 × 16 grid of mean brightness** per family, plus the
/// share of the frame that is exactly black. Each cell averages roughly 450
/// pixels, so antialiasing along an edge moves a cell by well under one level
/// while a mark that moves a column moves several cells by tens. That is the
/// whole reason for the coarse grid: it is deliberately blind to the noise and
/// deliberately loud about the change.
///
/// ## And a tone census, because the grid is a geometry gate (#199)
///
/// A mean dilutes by however much of a cell is unaffected. #194 moved
/// `GlowPalette.greyOpaque` thirteen levels — every unlit mark in the app —
/// and the worst cell in any family moved **+3** against a tolerance of 3. The
/// marks that carry the grey are thin: hairlines, a 1pt ✕, weekday letters. A
/// whole-palette move averaged down to two or three levels per cell and came
/// one level short of being invisible here.
///
/// So the signature carries a second statistic that thinness cannot dilute.
/// The app palette paints exactly two colours and no ramp between them (#111),
/// apart from content-owned emoji (#457). Every mark therefore deposits its
/// interior pixels at *one exact level* while its antialiased edge deposits a
/// smooth gradient. That shows in a histogram as a spike standing on a ramp,
/// and the height of the spike above the ramp —
/// `RenderSignature.toneExcess` — is a count of pixels, not an average, so it
/// does not care how thin the mark is.
///
/// Measured across the six families that existed before #209, before and after
/// #194: the excess at the
/// grey's own level is **680 to 4132** pixels where the grey is painted, and
/// **−2 to 42** at that same level where it is not. Two orders of magnitude,
/// against three levels of slack in the grid. A one-level palette move is
/// enough to collapse it, because the spike lands on the neighbouring level
/// instead.
///
/// ## The determinism contract
///
/// A baseline is only as good as the scene being reproducible, so the scene is
/// pinned rather than sampled:
///
/// * **The date.** `WidgetRenderDiffTests` anchors on `Date()`, which is fine
///   for invariants and fatal for a baseline — the month family redraws its
///   whole grid every month. Every frame here is rendered for a fixed day:
///   `Fixture.anchor`, a Tuesday, and — since #384 — `Fixture.sundayAnchor`,
///   the Sunday of the same week. Two days rather than one because the shape
///   of a missed mark is a function of how much of the week is already behind
///   today, and one Tuesday can only ever draw the narrowest case.
/// * **The glow.** Pinned to `GlowSettings.defaultValue` with the render cache
///   cleared, because the tile's encoded headroom changes what a mark renders
///   as even in SDR, and another suite is allowed to have turned it down.
/// * **The rest day.** Pinned to none, because `HabitRowView` reads it out of
///   the App Group rather than taking it as a parameter (#386). No widget
///   frame depends on it; the app's row does.
/// * **Size, scale, colour space and appearance.** 2x, sRGB, dark, over
///   `GlowPalette.widgetBackground`, exactly as the widget configurations do.
///
/// Locale still reaches the weekday initials. It is the simulator's own, en_US
/// on every machine this runs on; a machine with another one is a legitimate
/// failure of this gate and its message says so.
///
/// **What the scene cannot pin: iOS 18.5 does not render the same picture
/// twice** (#431). One unchanged commit rendered 48 times across eight
/// processes on iOS 26.5 came back bit-identical every time. The same commit
/// rendered 60 times on two iOS 18.5 devices differed by up to 601 pixels,
/// every one of them by a single level, and most of them in the
/// `.ultraThinMaterial` the surface is drawn on: the same scene rendered over
/// plain black instead holds `week medium` and `week large` bit-identical and
/// takes `grid rows` from ~450 differing pixels to ~85, so the material is the
/// larger source and not the only one. The magnitude tracks how much of the
/// frame it covers — the two smallest frames were identical in all 132.
///
/// The tolerances below already absorb it: no cell mean moved in any of those
/// 132 renders, and neither did the ground share. The one statistic it reaches
/// is `tones`, because that is a *count* of pixels at one exact level — the
/// property that makes it blind to a mark's thinness (#199) is the property
/// that makes one pixel move it. It moves by exactly one, in both directions:
/// `week large` at 255 is 4097 or 4098, `grid rows` at 124 is 230 or 231.
/// `week large` is the clearest reading of the mechanism — the count *at* 255
/// was 4106 in all 132 renders, and what oscillates is the neighbour
/// `toneExcess` subtracts.
///
/// So a one-pixel disagreement on that lane is the renderer, not an
/// unapproved change, and it is not a reason to approve anything:
/// `Tools/compare-signatures.py` reports it and refuses to write it. See
/// `docs/decisions.md`.
///
/// ## Approving a change
///
/// The manifest of what was actually rendered is attached to every run, passing
/// or failing, as `render-signatures-actual.json`. Approving a deliberate
/// visual change is copying it over the committed file — `render-signatures.json`
/// for the current runtime, `render-signatures-ios<major>.json` for an OS major
/// that carries its own (see `committedBaseline()`) — and saying in the pull
/// request what moved. `Tools/test.sh` prints that command with the run's own
/// path and the right destination in it.
@MainActor
@Suite("Render baseline")
struct RenderBaselineTests {

    // MARK: - The gate

    @Test("Every family matches its committed signature")
    func framesMatchBaseline() throws {
        let actual = try Self.currentSignatures()

        // Recorded before anything is compared, and whether this passes or
        // fails. A run that only leaves evidence behind when it is happy cannot
        // be used to approve a change, and a run that cannot read the committed
        // file at all is exactly when the rendered manifest is worth having.
        Attachment.record(
            try JSONEncoder.baseline.encode(RenderBaseline(frames: actual)),
            named: "render-signatures-actual.json"
        )

        let baseline = try Self.committedBaseline()

        for (name, signature) in actual.sorted(by: { $0.key < $1.key }) {
            guard let expected = baseline.frames[name] else {
                // **An addition attaches its render and nothing else** (#385).
                // There is no expected and no diff — that is what "new" means —
                // and what a reviewer needs to look at is the frame itself.
                // Without this the run failed with no image at all, and
                // `visualFailureAttachments` then refused the whole run, so the
                // deliberate change this message describes could not be
                // approved by `Tools/approve-baseline.sh`.
                attachActual(name: name)
                Issue.record("""
                    \(name) has no committed signature. A new family is a \
                    deliberate change: approve it into \
                    RenderTests/Baselines/render-signatures.json. Its render is \
                    attached as \(name.replacingOccurrences(of: " ", with: "-"))-actual.png.
                    """)
                continue
            }

            guard expected.width == signature.width, expected.height == signature.height else {
                Issue.record("""
                    \(name) renders at \(signature.width)×\(signature.height); the baseline is \
                    \(expected.width)×\(expected.height). Size equality is a prerequisite for \
                    comparing anything else.
                    """)
                continue
            }

            // One set of images per frame however many ways it disagrees:
            // rendering the frame again for each is slow, and two attachments
            // under one name is not evidence twice over.
            var attached = false
            func attachFailureOnce() {
                guard !attached else { return }
                attached = true
                attachFailure(name: name, expected: expected, actual: signature)
            }

            let worst = signature.worstCell(against: expected)
            if worst.delta > Self.cellTolerance {
                attachFailureOnce()
                Issue.record("""
                    \(name) moved: cell (\(worst.column),\(worst.row)) is \(worst.actual), the \
                    baseline says \(worst.expected) — a delta of \(worst.delta), tolerance \
                    \(Self.cellTolerance). Expected, actual and diff images are attached.
                    """)
            }

            let blackDelta = abs(signature.exactBlackPercent - expected.exactBlackPercent)
            if blackDelta > Self.blackTolerance {
                Issue.record("""
                    \(name) is \(String(format: "%.1f", signature.exactBlackPercent))% pure black; \
                    the baseline says \(String(format: "%.1f", expected.exactBlackPercent))%. \
                    A gradient, a tint or a material lifts this number off the floor.
                    """)
            }

            // The half the cell grid cannot do (#199). Each declared tone is
            // checked in both directions: one the baseline says this family
            // paints has to still be painted, and one it says the family does
            // not paint must not appear.
            for tone in Self.flatTones {
                let expectedCount = expected.tones[tone] ?? 0
                let actualCount = signature.tones[tone] ?? 0

                if expectedCount >= Self.toneFloor {
                    let least = Int(Double(expectedCount) * Self.toneRetention)
                    if actualCount < least {
                        attachFailureOnce()
                        Issue.record("""
                            \(name) has \(actualCount) pixels painted flat at level \(tone); the \
                            baseline says \(expectedCount), and this gate wants at least \
                            \(least). A tone that collapses like this has moved to another \
                            level or stopped being drawn — the cell grid dilutes both, which is \
                            why this number exists. See #199.
                            """)
                    }
                } else if actualCount >= Self.toneFloor {
                    attachFailureOnce()
                    Issue.record("""
                        \(name) now paints \(actualCount) pixels flat at level \(tone), where the \
                        baseline recorded \(expectedCount) — near enough to none. A family that \
                        starts painting a tone it did not is a deliberate change; approve it.
                        """)
                }
            }
        }
    }

    @Test("Every flat tone the gate names is painted somewhere")
    func flatTonesAreReal() throws {
        // The loop-closer, and the reason `flatTones` can be a literal at all.
        //
        // Move the palette and re-approve the baseline without touching that
        // list, and every family records ~0 at the old level — the check above
        // is then comparing zero against zero in six places and gating on
        // nothing, silently. This is what goes red instead. It renders rather
        // than reading the committed file on purpose: the claim is about what
        // the app draws today, not about what was approved.
        let actual = try Self.currentSignatures()
        for tone in Self.flatTones {
            let best = actual.map { ($0.key, $0.value.tones[tone] ?? 0) }.max { $0.1 < $1.1 }
            #expect((best?.1 ?? 0) >= Self.toneFloor, """
                no family paints anything flat at level \(tone) — the most any of them has is \
                \(best?.1 ?? 0), in \(best?.0 ?? "none"). `flatTones` names the levels this app \
                paints; a level nothing is painted at gates nothing. If the palette moved, move \
                this list with it. See #199.
                """)
        }
    }

    @Test("The baseline covers every family and nothing else")
    func baselineIsComplete() throws {
        // A baseline file that has quietly lost a family passes the test above
        // for every family it still has. This is the half that notices.
        let baseline = try Self.committedBaseline()
        let rendered = Set(Self.frames.map(\.name))
        let committed = Set(baseline.frames.keys)

        #expect(committed == rendered, """
            the committed baseline covers \(committed.sorted()) but this build renders \
            \(rendered.sorted()). A family added or removed is a deliberate change; approve it.
            """)
    }

    // MARK: - Thresholds

    /// Mean-brightness levels a 16 × 16 cell may move before this is a
    /// regression rather than a rounding difference.
    ///
    /// Measured rather than guessed: the same commit rendered on two simulator
    /// models moved no cell at all, so the honest floor is 0 and this is
    /// headroom for a renderer that rounds differently after an Xcode bump. A
    /// mark that moves one column moves its cells by tens.
    static let cellTolerance = 3

    /// Percentage points of "exactly 0,0,0" the frame may move by. The claim
    /// #87 makes is that the ground is pure black; this notices it drifting.
    static let blackTolerance = 0.5

    /// The levels the app paints flat. Declared on `RenderSignature`, which is
    /// what measures them.
    static var flatTones: [Int] { RenderSignature.flatTones }

    /// The share of a committed tone's pixel count that has to survive.
    ///
    /// Generous on purpose, and it can afford to be. Measured across the six
    /// families that existed before #209, before and after #194: a tone that is
    /// still painted holds 680
    /// to 4132 pixels of excess, and the same level with the tone moved away
    /// holds −2 to 42 — about 1% of the number the baseline recorded. Half is
    /// far outside anything antialiasing can do and far inside the collapse.
    static let toneRetention = 0.5

    /// Pixels of excess below which a level is not a tone this frame paints.
    ///
    /// It had a second job while the two Today families rendered: they sat
    /// under it at level 36 — their only unlit surface was a habit name in the
    /// handled state, and the pinned fixture's one habit was open, so those
    /// frames held no `greyOpaque` pixel at all — and the *other* branch above
    /// was what held them there. Those families are gone (#209), and with them
    /// #213's claim. The floor still separates a tone from a rounding
    /// artefact, which is the job it was written for — but "every frame left
    /// paints both levels well above this", which this note used to add, has
    /// not been true since #404 measured level 124 and found both frames that
    /// carry it in quantity sitting under 200. See below.
    ///
    /// **120 since #404, and the reason is worth more than the number.** The
    /// icon went from 14pt to 10pt, which is less ink in the label column, and
    /// level 124 — the resting step — is painted there, in `Sunset`'s icon and
    /// name. The best family on the current runtime fell from 223 to 194 and
    /// `flatTonesAreReal` went red; on iOS 18 the same change measures 412 and
    /// it never did. Two facts follow from that pair, and only the second is
    /// about #404:
    ///
    /// - **The two runtimes disagree about this level by a factor of two, and
    ///   a second pinned day did not close it.** Level 124 after the change:
    ///   `week large` 194, `week large sunday` 169, `month small` 90, both
    ///   medium frames about zero, against 412, 399, 90 and about zero on
    ///   iOS 18. 223 against a floor of 200 was a 10% margin before anything
    ///   moved. #384's second pinned day landed as #413 while this branch was
    ///   open, and it is *not* the repair this needed: the Sunday reading of
    ///   the same week is lower than the Tuesday's, not higher, because the
    ///   handled row it turns on is unchanged and the marks it adds are drawn
    ///   at other levels. What would lift this level is a fixture with more
    ///   than one habit in the handled state.
    /// - **194 is still a tone, not an artefact.** The calibration above
    ///   measured a level with its tone moved away at −2 to 42. 194 is four
    ///   and a half times the worst of those, and 120 is close to three times
    ///   it, so the separation this constant exists to make is intact. What
    ///   the old 200 additionally asserted — that a painted level holds
    ///   hundreds of pixels — was never true of level 124 on this fixture.
    ///
    /// Lowering it is not only a loosening. At 200 the newly measured
    /// `week large sunday` — 169 — would fall to the "must not appear" branch,
    /// which asks that frame to keep *not* painting a level it plainly does;
    /// at 120 its 124 is a tone the frame has to go on painting. What genuinely
    /// narrows is the other side: `month small` paints 90 there and now clears
    /// the line by 30 rather than by 110.
    static let toneFloor = 120

    // MARK: - The scene

    /// Every family, at the sizes a 6.1" phone gives them, rendered for one
    /// pinned day.
    struct Frame {
        let name: String
        let size: CGSize
        let view: AnyView
        /// The content inset `render` lays the view inside.
        ///
        /// The widget's own, for every widget frame. The app's grid is the same
        /// four numbers at the screen's scale, so it carries its own rather
        /// than borrowing unscaled ones (#386).
        let insets: EdgeInsets

        init(name: String, size: CGSize, view: AnyView, insets: EdgeInsets = Frame.widgetInsets) {
            self.name = name
            self.size = size
            self.view = view
            self.insets = insets
        }

        static let widgetInsets = EdgeInsets(
            top: WidgetMetrics.padTop, leading: WidgetMetrics.padLeading,
            bottom: WidgetMetrics.padBottom, trailing: WidgetMetrics.padTrailing
        )
    }

    static var frames: [Frame] {
        let week = Fixture.week()
        let month = Fixture.month()
        return [
            Frame(name: "week medium", size: WidgetMetrics.size(of: .systemMedium),
                  view: AnyView(WeekWidgetView(entry: week, familyOverride: .systemMedium))),
            Frame(name: "week large", size: WidgetMetrics.size(of: .systemLarge),
                  view: AnyView(WeekWidgetView(entry: week, familyOverride: .systemLarge))),
            // A widget somebody configured (#188), and the only committed
            // frame with a blank row in it — nothing rendered a spacer before
            // this landed. It also pins the ordering decision: the choice was
            // made in a different order and the render is in the app's.
            Frame(name: "week medium configured", size: WidgetMetrics.size(of: .systemMedium),
                  view: AnyView(WeekWidgetView(
                      entry: Fixture.configuredWeek(), familyOverride: .systemMedium
                  ))),
            // The second pinned day (#384). Same week, same nine rows, read
            // from the Sunday instead of the Tuesday — which is the only way
            // this fixture can draw a missed span wider than one column, more
            // than one missed span in a row, or a completion and a ✕ in
            // reading order. `Fixture.sundayAnchor` has the derivation.
            //
            // Large, because it is the family that shows all nine rows; medium
            // shows four and would hold the wide ✕ but neither of the other
            // two.
            Frame(name: "week large sunday", size: WidgetMetrics.size(of: .systemLarge),
                  view: AnyView(WeekWidgetView(
                      entry: Fixture.week(today: Fixture.sundayAnchor),
                      familyOverride: .systemLarge
                  ))),
            // **A frame a phone actually gives, and the only one** (#410).
            //
            // Every other widget frame here is `WidgetMetrics.size(of:)` —
            // 338 × 354, the design file's own frame, and a size no device was
            // ever measured handing out. That is why nothing caught the large
            // family losing a row: ten rows fit the design frame with zero
            // slack, every phone measured is proportionally wider than it, and
            // the harness rendered only the one aspect ratio where the fit
            // holds. A baseline of a widget that exists on no device cannot
            // fail for a reason a device would.
            //
            // 349.67 × 365 is the iPhone 17 Pro's, read out of WidgetKit's own
            // snapshot-cache archive path and confirmed by pixel-counting a
            // placed widget at 3x. It is the widest of the three measured, so
            // it is the frame the height has to overrule hardest — 1.97pt of
            // overrun out of ~320 before the fix.
            //
            // **Pinning one phone is pinning one phone**, and that objection
            // is real (#367). It is answered rather than dodged: the arithmetic
            // for all three measured frames is asserted in
            // `WidgetMetricsTests`, where it costs nothing and needs no
            // renderer, and this frame is here so that *some* committed picture
            // is of the widget a person actually looks at.
            //
            // Ten rows, because nine is the number this bug produced and a
            // nine-row scene would have passed straight through it. The tenth
            // is a habit rather than a blank row: a spacer draws nothing, and
            // a row that draws nothing cannot show that it was drawn.
            Frame(name: "week large device", size: Fixture.deviceFrame,
                  view: AnyView(WeekWidgetView(
                      entry: Fixture.deviceWeek(), familyOverride: .systemLarge
                  ))),
            Frame(name: "month small", size: WidgetMetrics.size(of: .systemSmall),
                  view: AnyView(MonthWidgetView(entry: month))),
            // **The app, not the widget** (#386). See `GridRows`.
            Frame(name: "grid rows", size: GridRows.size,
                  view: AnyView(GridRows(entry: week)),
                  insets: GridRows.insets),
            // **The same nine rows with the list fanned open** (#386).
            //
            // Edit mode is the row's third rendering and it was drawn by
            // nothing. `EditModeTests` reads `WeeklyGridView.swift` and
            // `HabitRowView.swift` as *text* — it scans for where
            // `@Environment(\.editMode)` may be declared, which is a real
            // check about where a declaration sits and is not a picture of
            // anything. So what #206 settled had no gate at all: while editing,
            // the marks go, the track's width returns to the label, the name
            // sits between the system's own controls, and both light steps
            // stand aside for a flat `GlowPalette.color` — a title's white,
            // which says legible rather than lit. Every one of those could
            // move without a signature moving.
            //
            // **What it does not hold is the controls the room is being made
            // for.** The delete circle and the reorder handle are the `List`'s,
            // laid out against the `List`'s own bounds (#400), and there is no
            // `List` here — see `GridRows` for why. This frame is the row's
            // half of edit mode and only that.
            Frame(name: "grid rows editing", size: GridRows.size,
                  view: AnyView(GridRows(entry: week, mode: .active)),
                  insets: GridRows.insets),
            // **The app's weekday header, and the emitting tier** (#386).
            //
            // `WeekdayHeader` is a real app view — extracted to its own file so
            // this target can compile it without `WeeklyGridView` — and it was
            // named by no test at all beyond a doc comment. It carries the one
            // rule CLAUDE.md opens with that no committed picture held: today's
            // letter *emits* while any habit is still open, and the other six
            // rest. Both branches are in this frame; the third is below.
            Frame(name: "weekday header", size: WeekdayHeaderFrame.size,
                  view: AnyView(WeekdayHeaderFrame(entry: week)),
                  insets: GridRows.insets),
            // **The middle step of the same rule** (#334, #335 §8.5).
            //
            // `TypeTier.weekday` answers `.emitting` for today with something
            // open and `.lit` for today with everything handled — a day that is
            // still plainly today and has stopped asking. One frame cannot hold
            // both, and with only the frame above, moving `.lit` to `.emitting`
            // — or deleting the distinction — would move no committed pixel.
            // The two frames differ in exactly one letter's tone, which is the
            // whole of what this pair claims.
            Frame(name: "weekday header handled", size: WeekdayHeaderFrame.size,
                  view: AnyView(WeekdayHeaderFrame(entry: Fixture.handledWeek())),
                  insets: GridRows.insets),
        ]
    }

    // MARK: - The app's own weekday header (#386)

    /// The seven letters as **the app** draws them, at the app's own width.
    ///
    /// **What this commits to.** The real `WeekdayHeader`, over the real
    /// `RowGeometry`, for the pinned week: the letters' type size, the column
    /// arithmetic that stands each one over its slot, and which of `TypeTier`'s
    /// three steps each letter takes.
    ///
    /// **What it does not.** The header's place on the screen. In
    /// `WeeklyGridView` it is an ordinary `List` row (#398) with its own top,
    /// leading, trailing and bottom padding, and none of that is here — the
    /// surround below is the widget's insets, the same frame `GridRows` holds
    /// its rows still with, and a claim about the letters rather than about
    /// where the list puts them.
    struct WeekdayHeaderFrame: View {
        let entry: WeekEntry

        /// Derived, like `GridRows.size`: the header's own height inside the
        /// insets `render` lays it in.
        static var size: CGSize {
            let geometry = GridRows.geometry
            let height = GridRows.insets.top + geometry.headerHeight
                + GridRows.insets.bottom
            return CGSize(width: GridRows.panelWidth, height: height.rounded(.up))
        }

        var body: some View {
            let geometry = GridRows.geometry
            WeekdayHeader(
                geometry: geometry,
                week: entry.week,
                today: entry.date,
                snapshots: entry.habits.value ?? []
            )
            // Not editing, for `GridRows`' reason and stated the same way: the
            // header fades to nothing while the list is fanned open, so a
            // default that moved would empty this frame rather than change it.
            .environment(\.editMode, .constant(.inactive))
        }
    }

    // MARK: - The app's own rows (#386)

    /// The nine rows of the pinned week as **the app** draws them.
    ///
    /// Every other frame here is a widget. `WeeklyGridView` and `WidgetsView`
    /// had no pixel gate of any kind, which made the app's grid the least
    /// gated surface in the project and the one the visual pass changed most —
    /// and `HabitRowView.spans` is the frame in all six of #381's crash logs.
    /// The widget draws the same `WeekSpans` output through a different view,
    /// and the widget was the half with baselines.
    ///
    /// **What this commits to, and what it does not.** This is
    /// `HabitRowView` — the real one, compiled into this target from
    /// `Glow/Views` — over the real `RowGeometry`, for every habit in the
    /// pinned fixture. So the label column, the icon, the track, the marks and
    /// their arithmetic at the *screen's* scale are gated, where before they
    /// were gated only at the widget's.
    ///
    /// It is **not** `WeeklyGridView`. The `List` around these rows — its row
    /// insets, the panel and its rounded ends, the pager, the widget-boundary
    /// hairline, and the delete and reorder controls edit mode brings — is
    /// rendered by nothing. Nor is `WidgetsView`.
    ///
    /// **Neither screen can go through this harness at all, and that is
    /// measured rather than assumed** (#386). Both build a `NavigationStack`,
    /// which SwiftUI implements as a UIKit container:
    /// `ImageRenderer` cannot flatten it, and rather than failing it
    /// substitutes SwiftUI's own invalid-configuration placeholder — a plain
    /// yellow field with a red no-entry sign. `WeeklyGridView` and
    /// `WidgetsView`, each rendered at 393 × 852 over a seeded in-memory
    /// container, came back as **byte-identical** copies of that placeholder,
    /// with the console line
    /// `Unable to render flattened version of`
    /// `PlatformViewControllerRepresentableAdaptor<NavigationStackRepresentable>`
    /// beside them. A signature taken from that render is a committed picture
    /// of an error icon, and it would pass forever.
    ///
    /// So the screens are covered here by the app views they are built from —
    /// this one, and `WeekdayHeaderFrame` below — and the rest waits on a
    /// second rendering path. That path is hosting in a `UIWindow` and
    /// snapshotting the layer, which `EmptyStateAccessibilityTests` already
    /// does half of, and it is a bigger decision than it looks: a hosted render
    /// inherits the scene's safe area and the device's own scale, so a baseline
    /// taken that way is a picture of one simulator model rather than of one
    /// runtime. `WeeklyGridView` also has no seam for "today" — it reads
    /// `WeekCalendar.today()` into `@State` — so a hosted frame over this
    /// fixture would draw whichever weekday the run happened on.
    ///
    /// The stack below is therefore **the test's surround, not the screen's**:
    /// one row gap between rows and the widget's inset around the block, which
    /// is a frame to hold the rows still rather than a claim about how the list
    /// arranges them. Every number in it comes from `RowGeometry` — the app's
    /// own object — so it moves when the app moves, but a change to
    /// `WeeklyGridView`'s `listRowInsets` will not show up here, and should not
    /// be read as covered because this frame exists.
    ///
    /// **The label's three renderings are held, and that was checked rather
    /// than assumed.** `HabitRowView` picks `GlowPalette.lit` or
    /// `GlowPalette.grey` underneath from `isHandled`, and crossfades an
    /// emitting copy over it at `opacity(lit)` — where `lit` is `@State`
    /// initialised to 1 and set from `.onAppear`. A renderer that skipped
    /// `onAppear` would leave every name emitting, and the frame would silently
    /// gate nothing here.
    ///
    /// It does not skip it. In the committed frame exactly four names emit —
    /// Workout, Early night, Hydration, Cold plunge — and those are exactly the
    /// four rows `WeekGrid`/`WeekSpans` leave `open` on the pinned Tuesday. All
    /// three steps of #335's scale are painted in the one frame.
    struct GridRows: View {
        let entry: WeekEntry
        /// Which of the two pictures this is. See the `grid rows editing`
        /// frame.
        var mode: EditMode = .inactive

        /// The panel the grid sits on: a 6.1" phone's width, less the margin
        /// `WeeklyGridView` insets the panel by. The widget frames pin
        /// `WidgetMetrics.largeWidth` for the same reason — a signature is only
        /// comparable against a width that cannot move.
        static let screenWidth: CGFloat = 393
        static var panelWidth: CGFloat { screenWidth - GridMetrics.horizontalPadding * 2 }
        static var geometry: RowGeometry { RowGeometry(totalWidth: panelWidth) }

        static var insets: EdgeInsets {
            let geometry = geometry
            return EdgeInsets(
                top: geometry.padTop, leading: geometry.padLeading,
                bottom: geometry.padBottom, trailing: geometry.padTrailing
            )
        }

        /// Derived, not written down, the way `WidgetMetrics.size(of:)` is: as
        /// many rows as the fixture has, at the app's own slot height and row
        /// gap. A metric that moves under this makes the gate report a size
        /// mismatch, which is a clearer failure than a silently cropped frame.
        static var size: CGSize {
            let geometry = geometry
            let slot = SlotLayout.slotHeight(trackWidth: geometry.trackWidth)
            let rows = CGFloat(Fixture.week().habits.value?.count ?? 0)
            let height = rows * slot
                + max(0, rows - 1) * geometry.rowInset * 2
                + geometry.padTop + geometry.padBottom
            return CGSize(width: panelWidth, height: height.rounded(.up))
        }

        var body: some View {
            let geometry = Self.geometry
            let snapshots = entry.habits.value ?? []
            // The same call `WeeklyGridView` makes, so the cut this frame
            // draws is the one the screen would draw rather than a second
            // opinion about it.
            let cut = RestCut.rows(snapshots, capacity: WidgetMetrics.largeRowCapacity)
            VStack(spacing: geometry.rowInset * 2) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    HabitRowView(
                        snapshot: snapshot,
                        week: entry.week,
                        today: entry.date,
                        geometry: geometry,
                        index: index,
                        cut: cut,
                        // What the screen hands its rows on a store nobody
                        // seeded: the week is editable, the future is not.
                        editing: .week(allowingFuture: false)
                    ) { _ in } onEdit: { }
                    .frame(width: geometry.labelWidth + geometry.labelGap + geometry.trackWidth)
                }
            }
            // Stated rather than inherited. `editMode` is nil in a rendered
            // tree, which already means "not editing" — writing it down is what
            // stops a later default from moving this frame without a diff, and
            // it is the one value the `grid rows editing` frame changes.
            .environment(\.editMode, .constant(mode))
        }
    }

    /// The pinned scene. Fixed identifiers as well as a fixed date: a `UUID()`
    /// per run would be invisible in most families and is not worth finding out
    /// about the hard way.
    enum Fixture {
        /// A Tuesday, so the week has a completed past, a live today and an
        /// untouched future in it.
        static let anchor: Date = day(10)

        /// The Sunday of the **same** week, and the second pinned day (#384).
        ///
        /// One Tuesday could only ever draw one blank past day, so a missed
        /// mark in a committed frame was always exactly one column wide and
        /// there was never more than one of it. Sunday is the last day of the
        /// week, so the same nine rows — unchanged, not restaged — divide the
        /// other way round: five past days behind today instead of one. Run
        /// through `WeekSpans`, that is what the Tuesday frames could not hold:
        ///
        ///  - **a missed span wider than one column.** Early night (2x,
        ///    nothing logged) is `missed` 0–5 and `open` 6; on Tuesday the same
        ///    row is `open` 0–1, `inactive` 2–6, with no ✕ in it at all.
        ///
        ///    The glyph does not stretch — read the render before repeating
        ///    #384's "a wide ✕", which this frame does not contain. What is
        ///    new is that the ✕ is drawn once, **centred over six columns**,
        ///    so it sits between two column centres. Every mark in every
        ///    earlier frame is either on a column centre or a bar filling its
        ///    own range; this is the first that is neither.
        ///  - **a completion and a ✕ interleaved.** Piano (4x, Mon and Tue) is
        ///    `filled` 0, `filled` 1, `missed` 2–5, `open` 6 — the reading order
        ///    a lit mark and a lost one appear in, which no frame drew.
        ///  - **several ✕ in one row.** Cold plunge (7x) is six one-column
        ///    missed spans and then today's open one — six ✕ from the span
        ///    path, where the widest a Tuesday frame reached was one. Both
        ///    shapes a missed span takes, one spanning and many single, are in
        ///    this one frame.
        ///
        /// The daily rows widen with it: Hydration is six crosses and Stretch
        /// is `✕ ● ✕ ✕ ✕ ✕ ○`. Those come through `WeekGrid`, not `WeekSpans`,
        /// and the Tuesday frames already held one of each — what is new is the
        /// count, which is what the tone census measures.
        ///
        /// **Sunday rather than Saturday**, the only other day with more than
        /// one past day and a live today: on Saturday, Early night is still
        /// `open` 0–5 and Piano still `open` 2–5, because neither has run out
        /// of days yet. Both the spanning ✕ and the interleave appear for the
        /// first time on Sunday, and Wednesday through Friday are weaker again.
        ///
        /// **The Tuesday frames stay, and not only for continuity.** No span in
        /// the Sunday frame is `inactive` — a week with one day left has no
        /// future to be inactive in — so the two days cover between them what
        /// neither covers alone.
        static let sundayAnchor: Date = day(15)

        /// A day in March 2026, which is the month both anchors sit in.
        private static func day(_ dayOfMonth: Int) -> Date {
            var components = DateComponents()
            components.year = 2026
            components.month = 3
            components.day = dayOfMonth
            return WeekCalendar.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        }

        private static func id(_ n: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
        }

        /// The pinned week, seen from `today`.
        ///
        /// **`today` is the only thing this parameter moves.** The nine rows
        /// and their completions are written against the week's own Monday and
        /// Tuesday and do not depend on it, so the Sunday frame is a second
        /// *reading* of one week rather than a second scene to keep in step
        /// with the first. Editing a row edits both frames, which is what makes
        /// the pair worth having.
        static func week(today: Date = anchor) -> WeekEntry {
            let week = WeekCalendar.week(containing: WeekCalendar.day(today))
            let monday = week.days[0]
            let tuesday = week.days[1]

            func habit(
                _ n: Int, _ name: String, _ icon: String, _ frequency: Frequency, done: [Date]
            ) -> HabitSnapshot {
                HabitSnapshot(
                    id: id(n), name: name, icon: icon,
                    frequency: frequency, completedDays: Set(done)
                )
            }

            return WeekEntry(
                // The day the entry is *for*, which is the parameter — not
                // `tuesday`, which is a column these habits log against.
                date: WeekCalendar.day(today),
                week: week,
                habits: .loaded([
                    habit(1, "Workout", "figure.run", .daily, done: [monday]),
                    habit(2, "Stretch", "figure.flexibility", .daily, done: [tuesday]),
                    habit(3, "Study", "book", .daily, done: [tuesday]),
                    habit(4, "Early night", "bed.double", .timesPerWeek(2), done: []),
                    // Due on the pinned Tuesday and deliberately an emoji:
                    // the app-row and widget-row baselines both exercise the
                    // full-colour exception to the label glow (#457).
                    habit(5, "Hydration", "💧", .daily, done: []),
                    habit(6, "Touch Grass", "leaf", .daily, done: [monday, tuesday]),
                    habit(7, "Sunset", "sunrise", .timesPerWeek(1), done: [monday]),
                    // **The two rows that put a ✕ and a second filled mark
                    // into a committed frame** (#384). Every other span row
                    // here divides into `open`, `inactive` and `filled` and
                    // nothing else, so three things the mark model draws were
                    // rendered by no baseline at all: the cross itself
                    // (`56d34ca`), a row of seven one-column marks, and more
                    // than one filled mark in a row (#342). A change to any of
                    // them moved no signature.
                    //
                    // Still a plausible week, which is this fixture's other
                    // job. Seven a week with nothing logged has genuinely lost
                    // Monday by Tuesday — that is the ✕ rule doing exactly what
                    // it says, not a state contrived to make one appear.
                    //
                    // **Appended, not inserted.** `configuredWeek()` picks by
                    // index into this array, and the medium family draws the
                    // first four rows — so adding at the end moves the large
                    // frame's signature and leaves the other three alone, which
                    // is a diff a reviewer can read.
                    habit(8, "Cold plunge", "snowflake", .timesPerWeek(7), done: []),
                    habit(9, "Piano", "pianokeys", .timesPerWeek(4), done: [monday, tuesday]),
                ])
            )
        }

        /// The large frame an iPhone 17 Pro was measured giving (#410), rather
        /// than the design file's 338 × 354.
        static let deviceFrame = CGSize(width: 349.67, height: 365)

        /// The pinned week with a tenth row, for the frame above.
        ///
        /// **Appended rather than added to `week()`**, which would move three
        /// committed signatures to make a point about a fourth. The tenth row
        /// is what the large family holds and what every phone was drawing one
        /// short of, so this scene is the one where a lost row is visible at
        /// all.
        static func deviceWeek() -> WeekEntry {
            let base = week()
            var all = base.habits.value ?? []
            all.append(HabitSnapshot(
                id: id(10), name: "Read", icon: "book.closed",
                frequency: .daily, completedDays: [base.week.days[0]]
            ))
            return WeekEntry(date: base.date, week: base.week, habits: .loaded(all))
        }

        /// The same week, as a widget somebody configured: four rows in an
        /// order the app does not have, with a blank one third.
        ///
        /// Built through `WidgetRows` rather than by hand, so the picture this
        /// gate commits to is the one the provider would produce. A hand-typed
        /// array would pass forever while the selection regressed — the mirror
        /// copy this project's test rules already forbid.
        static func configuredWeek() -> WeekEntry {
            let base = week()
            let spacer = HabitSnapshot(
                id: id(90), name: "", icon: "", frequency: .daily,
                completedDays: [], isSpacer: true
            )
            // The app's own list, with the blank row where the app's own
            // clustering puts it — third, which is the shape #172 measured the
            // cost of.
            var all = base.habits.value ?? []
            all.insert(spacer, at: 2)
            // Chosen in an order that is not the app's, and one the system can
            // really deliver: #191 measured WidgetKit handing this array back
            // in tap order. The frame commits to the widget ignoring it —
            // Workout, blank, Study, Touch Grass, in the app's order.
            let chosen = [all[6].id, all[3].id, spacer.id, all[0].id]
            return WeekEntry(
                date: base.date,
                week: base.week,
                habits: .loaded(WidgetRows.rows(from: all, chosen: chosen))
            )
        }

        /// The same week with every day of it logged, for the second header
        /// frame.
        ///
        /// **A reading of the pinned week, not a second scene.** The nine rows,
        /// their names, icons and cadences are `week()`'s; what changes is that
        /// nothing is left open, which is the one input
        /// `TypeTier.weekday(isToday:anyHabitOpen:)` takes. Every day rather
        /// than just the anchor, because "handled" has to be true of the whole
        /// week for no row to be open: a 7x habit with only today logged is
        /// still open for the rest of it.
        static func handledWeek() -> WeekEntry {
            let base = week()
            let every = Set(base.week.days)
            let all = (base.habits.value ?? []).map { snapshot in
                HabitSnapshot(
                    id: snapshot.id, name: snapshot.name, icon: snapshot.icon,
                    frequency: snapshot.frequency, completedDays: every,
                    isSpacer: snapshot.isSpacer
                )
            }
            return WeekEntry(date: base.date, week: base.week, habits: .loaded(all))
        }

        static func month() -> MonthEntry {
            let week = WeekCalendar.week(containing: WeekCalendar.day(anchor))
            return MonthEntry(
                date: WeekCalendar.day(anchor),
                habit: .loaded(HabitSnapshot(
                    id: id(1), name: "Workout", icon: "figure.run",
                    frequency: .daily,
                    completedDays: Set(week.days.prefix(2))
                ))
            )
        }
    }

    // MARK: - Rendering

    private static let scale: CGFloat = 2

    /// Renders one frame under the pinned appearance contract.
    static func render(_ frame: Frame) throws -> CGImage {
        let framed = frame.view
            .padding(.leading, frame.insets.leading)
            .padding(.trailing, frame.insets.trailing)
            .padding(.top, frame.insets.top)
            .padding(.bottom, frame.insets.bottom)
            .frame(width: frame.size.width, height: frame.size.height)
            .background { GlowPalette.widgetSurface }
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(frame.size)
        return try #require(renderer.cgImage, "ImageRenderer produced nothing for \(frame.name)")
    }

    static func currentSignatures() throws -> [String: RenderSignature] {
        // The glow is part of the picture, so it is pinned rather than turned
        // off — and the cache is cleared, because a suite that legitimately
        // rendered at another setting leaves tiles in it.
        let previous = GlowSettings.store.object(forKey: GlowSettings.key)
        // **The second piece of ambient state, and it arrived with the app's
        // own row** (#386). `HabitRowView` reads the rest day out of the App
        // Group with `@AppStorage`, so it is a preference the scene depends on
        // and does not carry — the widget frames have none, which is why this
        // was not needed before. Pinned to nothing, which is what a real
        // install has since #390, rather than to whatever the last suite to run
        // on this device left behind.
        let previousRestDay = GlowSettings.store.object(forKey: WeekPreferences.restDayKey)
        defer {
            GlowSettings.store.set(previous, forKey: GlowSettings.key)
            GlowSettings.store.set(previousRestDay, forKey: WeekPreferences.restDayKey)
            GlowImageCache.shared.removeAll()
        }
        GlowSettings.store.set(GlowSettings.defaultValue, forKey: GlowSettings.key)
        GlowSettings.store.set(0, forKey: WeekPreferences.restDayKey)
        GlowImageCache.shared.removeAll()

        var out: [String: RenderSignature] = [:]
        for frame in frames {
            out[frame.name] = RenderSignature(of: try render(frame))
        }
        return out
    }

    // MARK: - The committed file

    /// The baseline for the OS this run is rendering on.
    ///
    /// A baseline is a picture of one renderer's output, and the renderer is
    /// the OS's: the same commit that moves no cell between two simulator
    /// *models* moves cells by more than the tolerance and the ground share by
    /// up to 7.4 points between iOS 26.5 and iOS 18.5 — measured on the
    /// minimum-iOS lane the day it landed (#286). So each gated OS major may
    /// carry its own file, `render-signatures-ios<major>.json`, and the
    /// unsuffixed file is the current runtime's. Approving a change on the
    /// minimum lane means copying that lane's `render-signatures-actual.json`
    /// over the suffixed file; `Tools/test.sh` names the right destination.
    static func committedBaseline() throws -> RenderBaseline {
        let bundle = Bundle(for: BaselineBundleToken.self)
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let url = try #require(
            bundle.url(forResource: "render-signatures-ios\(major)", withExtension: "json")
                ?? bundle.url(forResource: "render-signatures", withExtension: "json"),
            """
            RenderTests/Baselines/render-signatures.json is not in the test bundle. \
            It is a committed input, not a generated one — without it there is no gate.
            """
        )
        return try JSONDecoder().decode(RenderBaseline.self, from: Data(contentsOf: url))
    }

    // MARK: - Failure artifacts

    /// Expected, actual and an emphasised diff, attached to the result bundle
    /// so a reviewer can look rather than take a number's word for it.
    ///
    /// "Expected" is the baseline grid drawn back out at frame size. It is a
    /// 16 × 16 approximation because that is genuinely what was approved;
    /// showing a full-resolution image nobody committed would be a nicer
    /// picture of a claim this gate does not make.
    ///
    /// A tone failure attaches the same three images and the diff will show no
    /// red at all — the tone census exists precisely because that kind of
    /// change does not move a cell mean. Read the message, and look at
    /// `-actual.png` rather than at the diff. It is still worth attaching: a
    /// render failure that leaves nothing to look at is what
    /// `visualFailureAttachments` in `Tools/test-inventory.json` refuses.
    /// The frame as it renders now, attached under its own name.
    ///
    /// Split out of `attachFailure` because a frame with no committed signature
    /// has this and only this to show (#385). Nothing here traps: it runs only
    /// on a failing path, and a crash while collecting evidence for a failure
    /// destroys the evidence.
    private func attachActual(name: String) {
        let slug = name.replacingOccurrences(of: " ", with: "-")
        if let frame = RenderBaselineTests.frames.first(where: { $0.name == name }),
           let png = try? RenderBaselineTests.render(frame),
           let data = UIImage(cgImage: png).pngData() {
            Attachment.record(data, named: "\(slug)-actual.png")
        }
    }

    private func attachFailure(name: String, expected: RenderSignature, actual: RenderSignature) {
        let slug = name.replacingOccurrences(of: " ", with: "-")
        attachActual(name: name)
        if let data = expected.gridImage(width: actual.width, height: actual.height) {
            Attachment.record(data, named: "\(slug)-expected.png")
        }
        if let data = actual.diffImage(
            against: expected, tolerance: RenderBaselineTests.cellTolerance
        ) {
            Attachment.record(data, named: "\(slug)-diff.png")
        }
    }
}

// MARK: - The signature

/// One family's committed picture: its size, how much of it is pure black, and
/// a 16 × 16 grid of mean brightness.
struct RenderSignature: Codable, Equatable {
    static let side = 16

    /// The levels this app paints *flat* — the two colours of #111, as they
    /// land in an sRGB byte. `GlowPalette.greyOpaque` is 141 (2026-08-24; it
    /// was 43 before the default and Increase Contrast became one value) and
    /// the lit white is 255.
    ///
    /// **Literals, deliberately, and the same argument the grey band in
    /// `WidgetRenderDiffTests` is written under.** A level read from
    /// `GlowPalette` would agree with whatever `GlowPalette` says, which is the
    /// one thing this must not do — the palette is what is being checked. So
    /// these are numbers a person wrote down, and moving the palette means
    /// moving them, in the same change, on purpose.
    /// `RenderBaselineTests.flatTonesAreReal` is what notices if that does not
    /// happen — it is what just caught this one.
    /// The levels this app paints flat, and the reason the list is a literal.
    ///
    /// **141 became 109 with #335.** The resting grey is `#D9D9D9` at half
    /// rather than `#8D8D8D` opaque, and half of 217 composited on the widget's
    /// black ground lands on 109 — *measured*, not derived: 108.5 could round
    /// either way, and the probe that settled it found 107, 108 and 110 all
    /// reporting no paint at all while 109 held the whole count.
    ///
    /// **217 joined them with #332/#334.** A completion used to take the HDR
    /// tile and paint 255; it is lit but not emitting now, so it paints the
    /// reflecting tier at full strength. The gate caught that as a *collapse* —
    /// `week large` went from 4401 white pixels to 2170, under the retention
    /// floor — which is exactly the wording of the failure: "a tone that
    /// collapses like this has moved to another level". It had.
    ///
    /// So the list is the palette's three steps, and 255 is now the emitting
    /// tier alone: open rings and glowing type.
    ///
    /// `flatTonesAreReal` is what keeps this honest — a level nothing is
    /// painted at gates nothing, so the list cannot silently outlive the
    /// palette. That test is what caught the 141 → 109 move.
    /// **109 became 124 with #333, and the reason is worth more than the
    /// number.** The resting step is `#D9D9D9` at 50%, so what it *renders* as
    /// is a composite of the palette and whatever is behind it — 109 over the
    /// old pure-black ground, and 124 over the glass material, which measures
    /// 31. It is the one level in this list that is not a palette constant, and
    /// it moves whenever the ground does.
    ///
    /// Measured rather than derived, twice over: `0.5 × 217 + 0.5 × 31` is
    /// 124, and the probe found the count split 4063/364 across 124 and 125
    /// because the material dithers. 124 carries the bulk in every family.
    ///
    /// 217 and 255 are opaque and did not move at all, which is the other half
    /// of the same point.
    static let flatTones = [124, 217, 255]

    var width: Int
    var height: Int
    /// Percentage of the frame that is exactly 0,0,0, to one decimal place.
    var exactBlackPercent: Double
    /// `side * side` mean brightness values, row-major, 0...255.
    var grid: [Int]
    /// Level → how many pixels are painted flat at it, over and above the edge
    /// gradient that passes through it. See `toneExcess`. Keyed by the levels in
    /// `RenderBaselineTests.flatTones` and by nothing else.
    var tones: [Int: Int]

    init(
        width: Int, height: Int, exactBlackPercent: Double, grid: [Int],
        tones: [Int: Int] = [:]
    ) {
        self.width = width
        self.height = height
        self.exactBlackPercent = exactBlackPercent
        self.grid = grid
        self.tones = tones
    }

    // MARK: Coding

    /// The grid is written as sixteen lines of sixteen numbers rather than as
    /// 256 array elements. The committed file is something a person reads in a
    /// pull request, and one row per line means a change to one band of the
    /// widget shows up as a change to one line.
    private enum CodingKeys: String, CodingKey {
        case width, height, exactBlackPercent, tones, rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        exactBlackPercent = try container.decode(Double.self, forKey: .exactBlackPercent)
        // Written with the level as the key, so the file reads as "36: 4790"
        // rather than as a pair of positional numbers.
        let tones = try container.decodeIfPresent([String: Int].self, forKey: .tones) ?? [:]
        self.tones = Dictionary(uniqueKeysWithValues: tones.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        let rows = try container.decode([String].self, forKey: .rows)
        grid = rows.flatMap { $0.split(separator: " ").compactMap { Int($0) } }
        guard grid.count == Self.side * Self.side else {
            throw DecodingError.dataCorruptedError(
                forKey: .rows, in: container,
                debugDescription: "expected \(Self.side * Self.side) cells, found \(grid.count)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(exactBlackPercent, forKey: .exactBlackPercent)
        try container.encode(
            Dictionary(uniqueKeysWithValues: tones.map { (String($0.key), $0.value) }),
            forKey: .tones
        )
        let rows = stride(from: 0, to: grid.count, by: Self.side).map { start in
            grid[start..<min(start + Self.side, grid.count)]
                .map { String(format: "%3d", $0) }
                .joined(separator: " ")
        }
        try container.encode(rows, forKey: .rows)
    }

    init(of image: CGImage) {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var sums = [Int](repeating: 0, count: Self.side * Self.side)
        var counts = [Int](repeating: 0, count: Self.side * Self.side)
        var histogram = [Int](repeating: 0, count: 256)
        var black = 0
        for y in 0..<h {
            let row = y * Self.side / h
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                if r == 0 && g == 0 && b == 0 { black += 1 }
                let value = Int(max(r, max(g, b)))
                let cell = row * Self.side + (x * Self.side / w)
                sums[cell] += value
                counts[cell] += 1
                histogram[value] += 1
            }
        }

        self.width = w
        self.height = h
        self.exactBlackPercent = (Double(black) * 1000 / Double(w * h)).rounded() / 10
        self.grid = zip(sums, counts).map { $1 == 0 ? 0 : Int((Double($0) / Double($1)).rounded()) }
        self.tones = Dictionary(uniqueKeysWithValues: Self.flatTones.map {
            ($0, Self.toneExcess(in: histogram, at: $0))
        })
    }

    /// How many pixels are painted flat at `level`, over and above the smooth
    /// gradient running through it.
    ///
    /// A flat-filled mark deposits every one of its interior pixels at exactly
    /// one level; an antialiased edge deposits a ramp, one thin slice per
    /// level. So the
    /// count at a painted level stands well above its two neighbours, and the
    /// count at an unpainted one sits between them. Subtracting the neighbours'
    /// mean is what separates the two — and it is a **count**, which is the
    /// whole point. A hairline puts every one of its pixels into this number
    /// and about a four-hundredth of a level into a cell mean. See #199.
    ///
    /// 255 has no upper neighbour, so its lower one stands for both. Levels 0
    /// and 1 are not askable: the ground is 0 and would swamp them.
    static func toneExcess(in histogram: [Int], at level: Int) -> Int {
        guard (2...255).contains(level), histogram.count == 256 else { return 0 }
        let below = histogram[level - 1]
        let above = level < 255 ? histogram[level + 1] : histogram[level - 1]
        return histogram[level] - (below + above) / 2
    }

    struct Worst {
        var column = 0, row = 0, expected = 0, actual = 0, delta = 0
    }

    func worstCell(against other: RenderSignature) -> Worst {
        var worst = Worst()
        for i in 0..<min(grid.count, other.grid.count) {
            let delta = abs(grid[i] - other.grid[i])
            if delta > worst.delta {
                worst = Worst(
                    column: i % Self.side, row: i / Self.side,
                    expected: other.grid[i], actual: grid[i], delta: delta
                )
            }
        }
        return worst
    }

    /// The grid drawn back out as an image, one flat rectangle per cell.
    func gridImage(width: Int, height: Int) -> Data? {
        Self.png(width: width, height: height) { x, y in
            let value = UInt8(clamping: grid[(y * Self.side / height) * Self.side + (x * Self.side / width)])
            return (value, value, value)
        }
    }

    /// The actual grid, dimmed, with every cell beyond tolerance flooded red —
    /// the same emphasis the neighbouring diff map uses.
    func diffImage(against other: RenderSignature, tolerance: Int) -> Data? {
        Self.png(width: width, height: height) { x, y in
            let i = (y * Self.side / height) * Self.side + (x * Self.side / width)
            let mine = UInt8(clamping: grid[i])
            guard i < other.grid.count, abs(grid[i] - other.grid[i]) > tolerance else {
                return (mine / 4, mine / 4, mine / 4)
            }
            return (255, 0, 0)
        }
    }

    private static func png(
        width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) -> Data? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                let i = (y * width + x) * 4
                bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
            }
        }
        var copy = bytes
        guard let image = CGContext(
            data: &copy,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}

/// The committed file's shape.
struct RenderBaseline: Codable {
    var frames: [String: RenderSignature]
}

extension JSONEncoder {
    /// Sorted keys and pretty printing, because the product of this encoder is
    /// a file a person reviews in a diff.
    static var baseline: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Anchors `Bundle(for:)` to this test bundle, where the baseline lives.
private final class BaselineBundleToken {}
