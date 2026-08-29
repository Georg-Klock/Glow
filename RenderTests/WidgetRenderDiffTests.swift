import CoreGraphics
import SwiftUI
import Testing
import UIKit

/// Renders the real `WeekWidgetView` at the design's own 338 × 354 and, when a
/// design export is committed beside it, differences the two and reports where
/// they disagree.
///
/// This exists because "the numbers agree" has already proved weaker than it
/// sounds: the geometry checked out arithmetically while the label column was
/// 74 instead of 98, the content padding was missing, and the glows sat at a
/// quarter of their radius — all found by re-reading the spec, none by looking.
/// The masked `ProgressView` sweep was correct in every respect except that it
/// did not work. Rendering and comparing is the check that reading cannot do.
///
/// This target compiles the widget's own sources (see project.yml), so the
/// view under render is the shipping view, not a copy.
///
/// **The reference is an owed input.** `DesignReference/README.md` carries the
/// export recipe for node `83:1676`; until the PNG is committed, the diff half
/// records that it is waiting and the render half still asserts what it can.
@MainActor
@Suite("Widget render diff")
struct WidgetRenderDiffTests {
    /// The design frame's own size, at 2x — the scale the file is authored for.
    private static let size = CGSize(width: 338, height: 354)
    private static let scale: CGFloat = 2

    /// Channel delta below which two pixels count as agreeing. Antialiasing
    /// and colour management make exact equality meaningless.
    private static let tolerance = 8

    @Test("The widget renders at 338 × 354 and the grid is actually in it")
    func renderIsReal() throws {
        let image = try render()

        #expect(image.width == Int(Self.size.width * Self.scale))
        #expect(image.height == Int(Self.size.height * Self.scale))

        // A blank or all-black render would diff "successfully" against
        // anything. Demand evidence of content: lit pixels (the marks) and grey
        // pixels (the labels, the sockets and the span lines).
        //
        // **The grey band moved with #111 and is now narrow on purpose.** It
        // used to be everything above 40, which caught a four-step ramp from 23
        // to 141. There is one grey now, so the band is that grey with three
        // levels of slack either side for antialiasing against the ground. A
        // band wide enough to reach into lit territory would pass on halo
        // bleed alone and stop being evidence that anything unlit was drawn.
        //
        // It tracked `#171717` as 20...26, `#242424` as 33...39 after #194,
        // `#2B2B2B` as 40...46 after #240, and is 138...144 since the default
        // grey became `#8D8D8D` (2026-08-24) — the value `greyIncreasedContrast`
        // already was, not a fifth point on the old ramp. The band is a
        // function of the palette, so it moves whenever the palette does — and
        // it is written as a literal rather than derived from `GlowPalette`
        // because a band computed from the value it is checking would agree
        // with any value. That is the trade: this line is the one assertion in
        // this file a palette move still has to touch, and it is deliberate.
        // Everything else here asks about a *relationship* measured in the same
        // frame — see `isUnlit(_:beside:)`.
        //
        // **109, since #335.** The resting grey is `#D9D9D9` at half, and half
        // of 217 on the widget's black ground composites there — measured
        // rather than derived, because 108.5 could round either way and the
        // probe found 107, 108 and 110 all empty.
        let pixels = try rgba(of: image)
        var lit = 0, grey = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = max(pixels[i], pixels[i + 1], pixels[i + 2])
            if value > 200 { lit += 1 }
            else if (106...112).contains(value) { grey += 1 }
        }
        #expect(lit > 500, "no lit marks in the render")
        // **200, down from 250, which was down from 500.** An upcoming slot
        // used to be *filled* at the resting grey, and filled sockets were most
        // of the original count. §8.3 says the socket has no fill at all and
        // its upcoming row gives `Inner: none`, so what is left carrying this
        // grey is the text, the weekday letters and the ✕.
        //
        // That was measured at 343 and is 247 since a spanning ring came off
        // the pill rather than the slot: the ring is roughly half the height it
        // was, and a shorter perimeter puts fewer antialiased edge pixels
        // through this narrow band. **The edges were never what this assertion
        // is about.** Counted on the rendered frame, 112 of the remaining
        // pixels are in the label column and 86 in the header letters — the
        // text this is meant to find — and 23 are anywhere near a mark. So the
        // floor is set from the text, with the mark's contribution treated as
        // the noise it always was.
        //
        // The floor is lowered in the same change as the one that lowered it,
        // which is the rule.
        #expect(grey > 200, "nothing unlit in the render: \(grey) pixels at the grey")

        let out = save(image, as: "widget-render@2x.png")
        print("render-diff: render written to \(out.path)")
    }

    @Test("Against the design export, when one is committed")
    func diffAgainstDesign() throws {
        guard let referenceURL = Bundle(for: BundleToken.self)
            .url(forResource: "widget-large-338x354@2x", withExtension: "png")
        else {
            // Not a failure: the export is an input this machine cannot mint.
            // The recipe is in DesignReference/README.md; the day the PNG is
            // committed, this test starts reporting.
            print("render-diff: no design export committed; diff waiting. See RenderTests/DesignReference/README.md")
            return
        }
        let data = try Data(contentsOf: referenceURL)
        let reference = try #require(UIImage(data: data)?.cgImage)
        let rendered = try render()

        #expect(reference.width == rendered.width && reference.height == rendered.height,
                "export is \(reference.width)×\(reference.height), render is \(rendered.width)×\(rendered.height) — re-export at 2x")

        let a = try rgba(of: rendered)
        let b = try rgba(of: reference)
        let width = rendered.width

        // Count disagreements and bucket them by grid row (row pitch 27.5pt =
        // 55px at 2x), so the report says *which rows* disagree rather than
        // only how much.
        var differing = 0
        var byBand: [Int: Int] = [:]
        var diffPixels = [UInt8](repeating: 0, count: a.count)
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            let delta = max(
                abs(Int(a[i]) - Int(b[i])),
                abs(Int(a[i + 1]) - Int(b[i + 1])),
                abs(Int(a[i + 2]) - Int(b[i + 2]))
            )
            if delta > Self.tolerance {
                differing += 1
                let y = (i / 4) / width
                byBand[y / 55, default: 0] += 1
                diffPixels[i] = 255
                diffPixels[i + 3] = 255
            } else {
                // Dimmed base, so the diff image reads in context.
                diffPixels[i] = a[i] / 4
                diffPixels[i + 1] = a[i + 1] / 4
                diffPixels[i + 2] = a[i + 2] / 4
                diffPixels[i + 3] = 255
            }
        }

        let total = a.count / 4
        let percent = Double(differing) * 100 / Double(total)
        let bands = byBand.sorted { $0.value > $1.value }.prefix(8)
            .map { "band \($0.key) (y \($0.key * 55)–\(($0.key + 1) * 55 - 1)px): \($0.value)px" }
            .joined(separator: ", ")
        print("render-diff: \(differing)/\(total) pixels differ (\(String(format: "%.2f", percent))%) beyond ±\(Self.tolerance); worst bands: \(bands)")

        if let diffImage = image(fromRGBA: diffPixels, width: width, height: rendered.height) {
            let out = save(diffImage, as: "widget-diff@2x.png")
            print("render-diff: difference map written to \(out.path)")
        }

        // No threshold assertion, deliberately. The app is documented as not
        // matching the flat export — HDR against clipped white, no glass —
        // so a hard gate would either fail forever or hide behind a number
        // nobody derived. The harness reports; deciding is a person's job.
        //
        // **This is a report, and the gate is elsewhere** (#138). An audit run
        // of this test found 90.04% of pixels beyond tolerance and passed, and
        // the fix was not to adopt that number: `RenderBaselineTests` asserts
        // against a committed signature of what the widget itself renders,
        // which is a claim this project can actually make.
    }

    @Test("The rest day's line runs between the first and last habit, and no further")
    func restCutStartsAndStopsOnAHabit() throws {
        // Sunday, which is the mockup's rest day and also the last column — so
        // a line drawn at the wrong x lands outside the track entirely rather
        // than one column over, which is the easier failure to read.
        let entry = self.entry()
        let sunday = entry.week.days[6]
        let weekday = WeekCalendar.calendar.component(.weekday, from: sunday)

        let previous = WeekPreferences.restDay
        defer { WeekPreferences.restDay = previous }
        WeekPreferences.restDay = weekday
        // This target has its own copy of the discipline `TestPreferences`
        // carries in the app's suite: it is a separate bundle and cannot see
        // it. The scheme runs both sequentially — see project.yml — which is
        // what makes writing a process-wide preference here safe at all.

        let pixels = try rgba(of: try render())
        let width = Int(Self.size.width * Self.scale)

        // Where the line should be, from `RestCut`'s own numbers rather than
        // from a measured render — the pixel-scanning script that chased a
        // four-point baseline error into three real code changes is the reason.
        let track = Self.size.width
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
        let x = WidgetMetrics.padLeading + RestCut.x(
            restIndex: 6,
            trackWidth: track,
            labelWidth: WidgetMetrics.labelWidth,
            labelGap: WidgetMetrics.labelGap
        )
        let column = Int((x * Self.scale).rounded())

        // The cut's grey against black, sampled down the column. The marks in
        // this row are far brighter, so a floor above the ground still separates
        // the line from the background without catching a dot.
        //
        // The floor was 40, chosen when the cut composited to 72. With #111 the
        // cut is the one grey — 23 then, 36 after #194, 43 since #240 — so the
        // floor is
        // `lineFloor`: the same 15
        // every other unlit-line scan in this file uses, and the number that
        // now has to hold for all of them.
        func isCut(_ y: Int) -> Bool {
            let i = (y * width + column) * 4
            guard i + 2 < pixels.count else { return false }
            return Int(max(pixels[i], pixels[i + 1], pixels[i + 2])) > Self.lineFloor
        }

        // Eight habits under a header, all in points, derived rather than
        // measured off the render this is checking.
        let side = SlotLayout.slotHeight(trackWidth: track)
        let headerBottom = WidgetMetrics.padTop + WidgetMetrics.headerHeight
        // Centred, not flush under the header (#368): eight rows in a frame
        // that holds ten leave a gap above them, and `WidgetMetrics.rowsOffset`
        // is where the widget gets that gap from.
        let firstRowTop = headerBottom + WidgetMetrics.headerGap
            + WidgetMetrics.rowsOffset(
                contentHeight: Self.size.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
                slot: side,
                rows: 8,
                hasHeader: true
            )
        let lastRowBottom = firstRowTop + 8 * side + 7 * WidgetMetrics.rowGap

        func yRange(from top: CGFloat, to bottom: CGFloat) -> Range<Int> {
            Int((top * Self.scale).rounded())..<Int((bottom * Self.scale).rounded())
        }

        // Sunday's own header letter sits in this column too, so the scan
        // starts below it. One point of slack at each boundary for
        // antialiasing.
        let above = yRange(from: headerBottom + 1, to: firstRowTop - 1)
        #expect(!above.contains(where: isCut),
                "the cut runs up into the header's air")

        let band = yRange(from: firstRowTop + 1, to: lastRowBottom - 1)
        let litInBand = band.filter(isCut).count
        #expect(litInBand > band.count * 9 / 10,
                "the cut is broken: \(litInBand) of \(band.count) rows lit between the first and last habit")

        let below = yRange(from: lastRowBottom + 1, to: Self.size.height)
        #expect(!below.contains(where: isCut),
                "the cut runs on past the last habit")
    }

    // MARK: - The rest day's window (#73)

    /// The track and column pitch the large frame divides itself by, so the
    /// scans below aim at `SlotLayout`'s own numbers rather than at something
    /// measured off the render they are checking. The pixel-scanning script
    /// that chased a four-point baseline error into three real code changes is
    /// the reason that distinction is written down.
    private var track: CGFloat {
        Self.size.width
            - WidgetMetrics.padLeading - WidgetMetrics.padTrailing
            - WidgetMetrics.labelWidth - WidgetMetrics.labelGap
    }

    /// The centre of one weekday's column, in points from the widget's left
    /// edge.
    private func columnCentre(_ index: Int) -> CGFloat {
        let slot = SlotLayout.dailySlot(trackWidth: track)
        let gap = SlotLayout.gap(trackWidth: track)
        return WidgetMetrics.padLeading + WidgetMetrics.labelWidth + WidgetMetrics.labelGap
            + CGFloat(index) * (slot + gap) + slot / 2
    }

    /// The brightest pixel anywhere in the first row's band, at one column.
    ///
    /// Down the whole row rather than along its centre line, because a filled
    /// span is a 2pt bar on the centre and an open one is a capsule outline
    /// whose strokes are at the top and bottom — one scan line would find one
    /// and miss the other.
    ///
    /// `row` is which band, counted from the first one under the header. It
    /// defaults to the first, which is what every scan here wanted until a
    /// configured widget had to be checked row by row (#188).
    ///
    /// `rows` is how many the widget under test draws, because the block is
    /// centred in what the header leaves (#368) and so its top edge moves with
    /// the count. The offset comes from `WidgetMetrics.rowsOffset` — the same
    /// call the widget centres by — rather than being worked out again here,
    /// which would be a copy that keeps agreeing with itself after the widget
    /// has moved.
    private func brightest(
        atColumn centre: CGFloat, row: Int = 0, rows: Int = 1, in pixels: [UInt8]
    ) -> Int {
        let width = Int(Self.size.width * Self.scale)
        let side = SlotLayout.slotHeight(trackWidth: track)
        let top = WidgetMetrics.padTop + WidgetMetrics.headerHeight + WidgetMetrics.headerGap
            + WidgetMetrics.rowsOffset(
                contentHeight: Self.size.height - WidgetMetrics.padTop - WidgetMetrics.padBottom,
                slot: side,
                rows: rows,
                hasHeader: true
            )
            + CGFloat(row) * (side + WidgetMetrics.rowGap)
        let x = Int((centre * Self.scale).rounded())
        var best = 0
        for y in Int((top * Self.scale).rounded())..<Int(((top + side) * Self.scale).rounded()) {
            let i = (y * width + x) * 4
            guard i + 2 < pixels.count else { continue }
            best = max(best, Int(max(pixels[i], pixels[i + 1], pixels[i + 2])))
        }
        return best
    }

    /// The brightest mark in the rest day's own column, sampled a quarter-slot
    /// either side of its centre.
    ///
    /// Not at the centre, because since #71 the widget draws the rest cut
    /// there: a flat 2pt rule in `GlowPalette.grey`, which composites to 141
    /// on black (2026-08-24) and would be read as a mark. The cut casts no halo, so a
    /// quarter-slot clears it, and that is still well inside the window the
    /// span is supposed to have lost.
    private func brightestInRestColumn(_ index: Int, rows: Int = 1, in pixels: [UInt8]) -> Int {
        let quarter = SlotLayout.dailySlot(trackWidth: track) / 4
        return max(
            brightest(atColumn: columnCentre(index) - quarter, rows: rows, in: pixels),
            brightest(atColumn: columnCentre(index) + quarter, rows: rows, in: pixels)
        )
    }

    /// The rest day's own line, sampled down the centre of its column — the
    /// flat `GlowPalette.grey` rule `RestCut` draws there, which composites to
    /// 141 on black (2026-08-24).
    ///
    /// The counterpart to `brightestInRestColumn`, which steps around it, and
    /// the quantity that says the rest day's column was *drawn* rather than
    /// merely left dark. A claim that the column holds no light is satisfied
    /// perfectly by a column with nothing in it — see #219.
    private func brightestAtRestLine(_ index: Int, rows: Int = 1, in pixels: [UInt8]) -> Int {
        brightest(atColumn: columnCentre(index), rows: rows, in: pixels)
    }

    /// Whether a tone is unlit, judged against the lit marks in the same frame
    /// rather than against a level.
    ///
    /// The palette has two colours and nothing between them (#111): the grey
    /// composites to 141 on black (2026-08-24; it was 43 before) and a lit
    /// mark to 255. This says "grey, not white" without naming either number —
    /// and it goes on saying it the next time the palette moves, which the
    /// fixed band `renderIsReal` still needs did not. #194 moved the grey
    /// thirteen levels underneath the multiplier below and nothing noticed;
    /// this move of ninety-eight levels did, which is exactly why the
    /// multiplier itself had to change this time rather than just the number
    /// it is compared against.
    ///
    /// **This was `value * 4 < lit` until 2026-08-24.** At `#2B2B2B` (43) that
    /// gave roughly 21 levels of tolerance above the raw grey before the check
    /// failed — plenty against halo bleed at a gap this wide (255:43, better
    /// than 5.9:1). `#8D8D8D` (141) closed most of that gap (255:141, 1.8:1),
    /// and `* 4` no longer holds at all: `141 * 4 = 564`, which is not less
    /// than any lit value this app renders. `* 1.5` gives 141 about 29 levels
    /// of the same kind of headroom — comparable slack, recomputed for the
    /// ratio that actually exists now rather than kept as a constant that
    /// quietly assumed the old one.
    private func isUnlit(_ value: Int, beside lit: Int) -> Bool { Double(value) * 1.5 < Double(lit) }

    /// One habit, so the first row's band is unambiguous.
    private func oneHabit(_ frequency: Frequency, done: [Int], todayColumn: Int) -> WeekEntry {
        let week = WeekCalendar.week(containing: WeekCalendar.day(Date()))
        return WeekEntry(
            date: week.days[todayColumn],
            week: week,
            habits: .loaded([HabitSnapshot(
                id: UUID(), name: "Gym", icon: "figure.run",
                frequency: frequency, completedDays: Set(done.map { week.days[$0] })
            )])
        )
    }

    /// Same discipline as `TestPreferences` in the app's suite, which this
    /// target cannot see — it is a separate bundle. Safe because the scheme
    /// runs tests sequentially; see project.yml.
    private func withRestColumn(_ column: Int, of week: Week, _ body: () throws -> Void) rethrows {
        let previous = WeekPreferences.restDay
        defer { WeekPreferences.restDay = previous }
        WeekPreferences.restDay = WeekCalendar.calendar.component(
            .weekday, from: week.days[column]
        )
        try body()
    }

    /// **The widget's ground, measured** (#333). It was 0,0,0 and it is a dark
    /// glass material now, which reads at 30–31 across every family.
    ///
    /// Every threshold below used to be a level against black. They are levels
    /// against *this* — because "nothing is drawn here" stopped meaning "this
    /// pixel is zero" the moment the surface stopped being zero, and a test
    /// that kept comparing against zero would report the background as content.
    private static let ground = 31

    /// A span's own line, unlit — "is the span there" is a question about the
    /// resting grey, not about light. `GlowPalette.grey` composites to 109 on
    /// black and to about 123 over the glass.
    private static let lineFloor = ground + 15

    /// Nothing drawn here at all — not "unlit", which is a different claim.
    ///
    /// The two are not interchangeable and #226 is where that matters.
    /// `isUnlit(_:beside:)` asks whether a tone is grey rather than white; the
    /// scans below rule out a *grey line* running where it should not, which
    /// sits well inside that. So this stays a level. It is a level against the
    /// ground rather than against the palette, which is why it does not move
    /// when the palette does — and why `lineFloor` sits above it: between them
    /// is the band nothing is ever painted in.
    ///
    /// **Relative to the ground since #333**, for the reason given there: a
    /// cleared column measures 32 against a ground of 31, and against the old
    /// absolute 10 that read as content.
    private static let clear = ground + 6

    /// Where *lit* starts, as distinct from unlit-with-a-bevel.
    ///
    /// **The socket's highlight moved this** (#332, #333). An unlit mark used
    /// to top out at the resting grey; it now carries the bevel's white edge at
    /// 13%, which over a 123-level disc peaks around 157. The lit step is 217
    /// and the emitting one 255, so the boundary sits between — where the old
    /// absolute 150 now lands *inside* what an unlit mark can reach.
    private static let litFloor = 185

    @Test("A met goal with Sunday resting stops at Saturday")
    func metGoalStopsBeforeSunday() throws {
        let entry = oneHabit(.timesPerWeek(2), done: [0, 1], todayColumn: 4)
        try withRestColumn(6, of: entry.week) {
            let pixels = try rgba(of: try render(entry))
            let saturday = brightest(atColumn: columnCentre(5), in: pixels)
            let sunday = brightestInRestColumn(6, in: pixels)
            // Sunday's own line down the centre of its column, and the lit
            // level of this very frame to judge it against: the two logged days
            // carry lit dots here, which is what `daysCarryTheLight` renders
            // this same fixture to say.
            let restLine = brightestAtRestLine(6, in: pixels)
            let dots = min(
                brightest(atColumn: columnCentre(0), in: pixels),
                brightest(atColumn: columnCentre(1), in: pixels)
            )

            #expect(saturday > Self.lineFloor,
                    "the met-goal line is missing at Saturday (\(saturday))")

            // **Sunday's column has something in it.** #226. `sunday < clear`
            // is an upper bound, and measured, the region it reads holds
            // exactly **0**: the span has been subtracted there, and
            // `brightestInRestColumn` steps a quarter-slot around the rest cut
            // on purpose, so what is left is empty. The bound was being met by
            // emptiness rather than by the line stopping — delete the rest
            // day's mark and it still passes. The floor on Saturday next door
            // does not notice, because it is in another column.
            //
            // The pairing is `restCutStartsAndStopsOnAHabit`'s: a claim about
            // absence is worth something only beside a claim that the same
            // column was drawn at all.
            #expect(restLine > Self.lineFloor,
                    "nothing is drawn in Sunday's column at all (\(restLine))")
            #expect(isUnlit(restLine, beside: dots),
                    "Sunday's line is lit (\(restLine), against the dots at \(dots))")
            #expect(sunday < Self.clear,
                    "the line runs into Sunday's column (\(sunday))")
        }
    }

    @Test("A met goal with Wednesday resting is cut in two")
    func metGoalIsCutInTheMiddle() throws {
        // **Monday and today, not Monday and Tuesday** (#230). The goal is met
        // either way — a met goal is one span across the whole week, whichever
        // two days carried it — but where the completions fall decides what
        // this test's own floors can see. Wednesday resting cuts that span at
        // columns 0...1 and 3...6, and with Monday and Tuesday logged *both*
        // columns of the left piece carried a lit dot: the floor below read 255
        // and would have gone on reading 255 with the line deleted underneath
        // it. Logging today instead leaves Tuesday carrying the line and
        // nothing else, so the floor measures the piece it names.
        let entry = oneHabit(.timesPerWeek(2), done: [0, 4], todayColumn: 4)
        try withRestColumn(2, of: entry.week) {
            let pixels = try rgba(of: try render(entry))
            let tuesday = brightest(atColumn: columnCentre(1), in: pixels)
            let wednesday = brightestInRestColumn(2, in: pixels)
            let thursday = brightest(atColumn: columnCentre(3), in: pixels)
            // The same pairing as above, and for the same reason: measured, the
            // window either side of Wednesday's centre reads **0**, which is
            // emptiness rather than a line that stops. See #226.
            let restLine = brightestAtRestLine(2, in: pixels)
            // The lit level to judge the rest line against. Both columns sit
            // inside a completed mark, which #344 lights — they used to be the
            // *dots*, and the dots are gone.
            let lit = min(
                brightest(atColumn: columnCentre(0), in: pixels),
                brightest(atColumn: columnCentre(4), in: pixels)
            )

            #expect(restLine > Self.lineFloor,
                    "nothing is drawn in Wednesday's column at all (\(restLine))")
            // **The rest line stays unlit, and it is now the only thing in this
            // row that is.** It is the cut, not a mark: absence, which does not
            // glow (#72). That it is measured against a *lit* neighbour rather
            // than a lit dot is the whole of what #344 changed here.
            #expect(isUnlit(restLine, beside: lit),
                    "Wednesday's line is lit (\(restLine), against the marks at \(lit))")
            #expect(wednesday < Self.clear, "the line crosses the rest day (\(wednesday))")

            // **Both pieces are there, and both are lit.** A floor alone says a
            // column is not empty, and a column is not empty for lots of
            // reasons — a completion dot in it being the one that cost #230.
            // Each piece is sampled at a column its own mark covers, so both
            // read the lit mark and both go to nothing when the piece they name
            // is not drawn.
            //
            // This assertion is inverted from what it was. It read `isUnlit`,
            // which was #47 in pixels: a met span drew the same grey line an
            // upcoming one draws. #344 reverses that, and this is where the
            // reversal is measured rather than argued.
            #expect(tuesday > Self.lineFloor, "the left piece is missing (\(tuesday))")
            #expect(!isUnlit(tuesday, beside: lit),
                    "the left piece is unlit (\(tuesday), against the marks at \(lit))")
            #expect(thursday > Self.lineFloor, "the right piece is missing (\(thursday))")
            #expect(!isUnlit(thursday, beside: lit),
                    "the right piece is unlit (\(thursday), against the marks at \(lit))")
        }
    }

    @Test("A met row is lit across the week, and an unmet one is not")
    func metRowIsLit() throws {
        // **#344 in one render, and it used to be #47 in one render.** It read
        // "the days carry the light, and the span does not": two a week with
        // Monday and Tuesday logged drew an unlit line across the week with a
        // lit dot on each of the two days it happened on.
        //
        // Both halves of that moved. The dots are gone, and the marks are lit —
        // so a met row is lit *everywhere*, including the Wednesday and
        // Thursday that this test used to require be dark. The rep the mark
        // stands for happened; the mark reaching back over a blank day is the
        // forgiveness the model exists for, not a claim about that day.
        let met = oneHabit(.timesPerWeek(2), done: [0, 1], todayColumn: 4)
        try withRestColumn(6, of: met.week) {
            let pixels = try rgba(of: try render(met))
            for column in [0, 1, 2, 3] {
                #expect(brightest(atColumn: columnCentre(column), in: pixels) > Self.litFloor,
                        "a met row is dark at column \(column)")
            }
        }

        // The control the old test had built into it and this one would lose:
        // the same row, same target, nothing logged. If a met row were lit
        // because *every* row is lit, this would pass too.
        let untouched = oneHabit(.timesPerWeek(2), done: [], todayColumn: 4)
        try withRestColumn(6, of: untouched.week) {
            let pixels = try rgba(of: try render(untouched))
            // Column 5 is past the open mark, which ends on today (column 4),
            // so it is upcoming track and nothing has been asked of it.
            let value = brightest(atColumn: columnCentre(5), in: pixels)
            // **`ground`, not `lineFloor`.** `lineFloor` asks whether a *grey
            // line* is drawn there, and an upcoming slot is no longer one: it
            // is a socket with no fill, drawn entirely by its bevel (§8.3).
            // What is still true, and still worth asserting, is that the bevel
            // paints *something* — it measures 45 against a ground of 31 — so
            // the socket has not silently vanished.
            //
            // An empty slot is deliberately not held to a legibility floor. It
            // is the ground the lit marks are read against, and being hard to
            // see is its job.
            #expect(value > Self.ground, "the upcoming socket draws nothing")
            #expect(value < Self.litFloor, "an untouched row is lit at column 5 (\(value))")
        }
    }

    @Test("An open span straddling the rest day keeps both arcs")
    func openSpanKeepsBothArcs() throws {
        // Nothing logged and today is Friday, so the open span reaches back
        // across Wednesday — a span cannot be open *on* a rest day, but it can
        // straddle one, and that is the case the subtraction has to survive.
        let entry = oneHabit(.timesPerWeek(2), done: [], todayColumn: 4)
        try withRestColumn(2, of: entry.week) {
            let spans = WeekSpans.spans(
                for: (entry.habits.value ?? [])[0], in: entry.week, today: entry.date, target: 2,
                editing: .todayOnly,
                restDay: WeekCalendar.calendar.component(
                    .weekday, from: entry.week.days[2]
                )
            )
            let open = try #require(spans.first { $0.state == .open })
            #expect(open.firstDay < 2 && open.lastDay > 2, "the fixture does not straddle Wednesday")

            let pixels = try rgba(of: try render(entry))
            let before = brightest(atColumn: columnCentre(open.firstDay), in: pixels)
            let after = brightest(atColumn: columnCentre(3), in: pixels)
            // Four quantities out of one frame, and every claim below is a
            // relationship between them rather than a level: the two arcs, the
            // rest day's own line down the middle of its column, and the window
            // the span is supposed to have lost either side of that line.
            let restLine = brightestAtRestLine(2, in: pixels)
            let window = brightestInRestColumn(2, in: pixels)
            let arcs = min(before, after)

            #expect(before > Self.litFloor, "the left arc is missing (\(before))")
            #expect(after > Self.litFloor, "the right arc is missing (\(after))")

            // **The rest day's column was drawn.** This is the half #219 was
            // filed for. The claim here is that the open span crosses the rest
            // day rather than lighting it, and it used to be evidenced by
            // `wednesday < 60` alone — an upper bound, which a column with
            // nothing painted in it at all satisfies perfectly. Measured on
            // this frame, the window either side of the line reads exactly 0,
            // so that bound was already passing on emptiness rather than on the
            // subtraction it was gating. Same shape as the near-miss in #199.
            #expect(restLine > Self.lineFloor,
                    "the rest day's line is missing from its own column (\(restLine))")
            // And it is structure rather than a mark, next to the arcs beside
            // it in the same frame.
            #expect(isUnlit(restLine, beside: arcs),
                    "the rest day's line is lit (\(restLine), against arcs at \(arcs))")
            // Only now does "no light here" mean anything: there is something
            // in this column, and what is in it is not the span.
            #expect(isUnlit(window, beside: arcs),
                    "the open span crosses the rest day (\(window), against arcs at \(arcs))")
        }
    }

    // MARK: - A configured widget (#188)

    @Test("A configured widget draws the chosen rows in the app's order")
    func configuredRowsAreDrawnInTheAppsOrder() throws {
        // The claim `WidgetRowsTests` cannot make: that the selection filters
        // the *pixels* without reordering them. Two daily habits logged on
        // different days, so which row is which is readable off the render
        // without reading any text — Alpha is lit on Monday and missed on
        // Wednesday, Beta is the mirror image.
        //
        // The chosen order below is deliberately the reverse of the app's, and
        // it is an order the system really can deliver: #191 measured on an
        // iPhone 14 Pro that WidgetKit hands the array back in tap order. So
        // this asserts a decision, not a platform limit — see `WidgetRows`.
        let week = WeekCalendar.week(containing: WeekCalendar.day(Date()))
        func habit(_ name: String, done: [Int]) -> HabitSnapshot {
            HabitSnapshot(
                id: UUID(), name: name, icon: "figure.run", frequency: .daily,
                completedDays: Set(done.map { week.days[$0] })
            )
        }
        let alpha = habit("Alpha", done: [0])
        let beta = habit("Beta", done: [2])
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completedDays: [], isSpacer: true
        )
        // The app's own order is Beta, blank, Alpha. The choice asks for the
        // reverse and gets the app's order anyway; if tap order were still
        // reaching the render, every assertion below would land on the wrong
        // row.
        let all = [beta, spacer, alpha]
        let rows = WidgetRows.rows(from: all, chosen: [alpha.id, spacer.id, beta.id])
        #expect(rows.map(\.name) == ["Beta", "", "Alpha"])

        // Friday, so Monday and Wednesday are both behind it and both readable.
        let entry = WeekEntry(date: week.days[4], week: week, habits: .loaded(rows))

        try withRestColumn(6, of: week) {
            // The halo is off for this one. It is not part of the claim, and
            // with it on a lit dot's light reaches the row above and below —
            // which is exactly where the blank row's assertion looks.
            try withoutHalo {
                let pixels = try rgba(of: try render(entry))

                #expect(brightest(atColumn: columnCentre(2), row: 0, rows: 3, in: pixels) > Self.litFloor,
                        "row 0 is not Beta: nothing lit on Wednesday")
                #expect(brightest(atColumn: columnCentre(0), row: 0, rows: 3, in: pixels) < Self.litFloor,
                        "row 0 is lit on Monday — the tap order reached the render")
                #expect(brightest(atColumn: columnCentre(0), row: 2, rows: 3, in: pixels) > Self.litFloor,
                        "row 2 is not Alpha: nothing lit on Monday")
                #expect(brightest(atColumn: columnCentre(2), row: 2, rows: 3, in: pixels) < Self.litFloor,
                        "row 2 is lit on Wednesday — the tap order reached the render")

                // The blank row draws nothing — no socket, no cross, no dot —
                // in any column but the rest day's, where the cut crosses it.
                // That is `RestCut`'s own rule, and until now no committed
                // render contained a spacer at all, so nothing was checking it.
                for column in 0..<6 {
                    let value = brightest(atColumn: columnCentre(column), row: 1, rows: 3, in: pixels)
                    #expect(value <= Self.clear,
                            "the blank row drew something at column \(column) (\(value))")
                }
                #expect(brightest(atColumn: columnCentre(6), row: 1, rows: 3, in: pixels) > Self.lineFloor,
                        "the rest day's cut does not cross the blank row")
            }
        }
    }

    // MARK: - The ground is 0,0,0 (#87)

    /// Renders one view at a widget's own size, over the declared background,
    /// exactly as the configurations do.
    private func renderFamily(
        _ view: some View, size: CGSize,
        top: CGFloat = WidgetMetrics.padTop, bottom: CGFloat = WidgetMetrics.padBottom
    ) throws -> CGImage {
        let framed = view
            .padding(.leading, WidgetMetrics.padLeading)
            .padding(.trailing, WidgetMetrics.padTrailing)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(width: size.width, height: size.height)
            .background { GlowPalette.widgetSurface }
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(size)
        return try #require(renderer.cgImage, "ImageRenderer produced nothing")
    }

    /// Every family, at the sizes a 6.1" phone gives them.
    private func families() -> [(String, AnyView, CGSize)] {
        let week = entry()
        return [
            ("week medium", AnyView(WeekWidgetView(entry: week, familyOverride: .systemMedium)),
             WidgetMetrics.size(of: .systemMedium)),
            ("week large", AnyView(WeekWidgetView(entry: week, familyOverride: .systemLarge)),
             WidgetMetrics.size(of: .systemLarge)),
            // The densest family, and the one most likely to lose the ground
            // claim without anyone noticing: six rows of seven cells, where a
            // lifted floor reads as "the marks are dim" rather than as "the
            // background is wrong".
            ("month small", AnyView(MonthWidgetView(entry: monthEntry())),
             WidgetMetrics.size(of: .systemSmall)),
        ]
    }

    /// A month with something in it: completions, misses, and today still open,
    /// so the sweep runs against marks rather than an empty grid.
    private func monthEntry() -> MonthEntry {
        let week = entry()
        return MonthEntry(
            date: week.date,
            habit: .loaded(HabitSnapshot(
                id: UUID(), name: "Workout", icon: "figure.run",
                frequency: .daily,
                completedDays: Set(week.week.days.prefix(2))
            ))
        )
    }

    /// Renders with the glow at the bottom of its range, where
    /// `GlowSettings.haloScale` is 0 and no mark casts a shadow.
    ///
    /// The background cannot be measured with the halo on. A lit mark spreads
    /// white onto the ground on purpose — that is the product, not a leak — and
    /// on a small family it reaches the corners: the measurement that
    /// established this was the Today ring's halo at
    /// `96 * ringHaloRadius * maxHaloScale` = 46.6pt across a 158pt frame,
    /// whose corners read 1,1,1 with the glow up and **0,0,0 with it down**.
    /// That family is gone (#209) and the claim is not — `haloIsWhatLiftsIt`
    /// makes it against a family that still ships, and fails rather than
    /// passing vacuously if no halo reaches that far.
    private func withoutHalo<T>(_ body: () throws -> T) rethrows -> T {
        let previous = GlowSettings.store.object(forKey: GlowSettings.key)
        defer { GlowSettings.store.set(previous, forKey: GlowSettings.key) }
        GlowSettings.store.set(GlowSettings.range.lowerBound, forKey: GlowSettings.key)
        GlowImageCache.shared.removeAll()
        return try body()
    }

    @Test("The ground is one flat dark tone in every family")
    func groundIsFlatGlass() throws {
        try withoutHalo {
        // **#87's claim was that the ground is 0,0,0, and #333 replaces it.**
        // The widget's surface is a dark glass material now, so pure black is
        // no longer the truth and asserting it would only assert that #333 had
        // not happened.
        //
        // What #87 was actually defending survives, and it is the part worth
        // keeping: the design file's own container is a ~13-level *gradient*,
        // and a gradient is what this refuses. A material is flat. So the
        // claims become uniform, neutral and dark — each of which a gradient,
        // a tint or a light panel breaks, and none of which "nearly black"
        // was ever really about.
        for (name, view, size) in families() {
            let image = try renderFamily(view, size: size)
            let pixels = try rgba(of: image)
            let w = image.width, h = image.height

            let corners = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)].map { x, y in
                let i = (y * w + x) * 4
                return (r: Int(pixels[i]), g: Int(pixels[i + 1]), b: Int(pixels[i + 2]))
            }

            // **Uniform.** Every corner the same tone, within the dithering the
            // material itself produces — measured at 30...32 across the three
            // families. A gradient across the frame cannot pass this: the
            // file's own is thirteen levels top to bottom.
            let levels = corners.flatMap { [$0.r, $0.g, $0.b] }
            let spread = (levels.max() ?? 0) - (levels.min() ?? 0)
            #expect(spread <= 4, "\(name): the ground is not flat, corners span \(spread) levels")

            // **Neutral.** Still true and still worth saying: accented
            // rendering keeps alpha and throws colour away, so a hue here would
            // be invisible in the one mode that would suffer from it.
            for corner in corners {
                #expect(max(corner.r, corner.g, corner.b) - min(corner.r, corner.g, corner.b) <= 3,
                        "\(name): a hue in the ground — \(corner)")
            }

            // **Dark.** The glass is a surface for sockets to be pressed into,
            // not a panel. Measured at 31; the bound is where "dark glass"
            // stops being a fair description.
            let ground = levels.reduce(0, +) / levels.count
            #expect(ground > 8 && ground < 60,
                    "\(name): the ground is at \(ground), which is not dark glass")

            // **And most of the frame is that same tone.** A corner sample
            // alone could miss a gradient that is subtle at the edges; this is
            // the whole-frame half of the claim, and the number it replaces is
            // the exact-black share #332 had already lowered from 90 to 70.
            var atGround = 0
            for i in stride(from: 0, to: pixels.count, by: 4)
            where abs(Int(pixels[i]) - ground) <= 3
                && abs(Int(pixels[i + 1]) - ground) <= 3
                && abs(Int(pixels[i + 2]) - ground) <= 3 {
                atGround += 1
            }
            let share = Double(atGround) * 100 / Double(w * h)
            print("bg-audit: \(name) ground \(ground), flat share \(String(format: "%.1f", share))%")
            #expect(share > 40,
                    "\(name): only \(Int(share))% of the frame sits at the ground tone")

            // **And 100 is what a frame with nothing in it reads.** #226
            // catalogued this bound and `noHueAnywhere` beside the two that
            // were fixed there, as whole-frame claims a blank render would
            // satisfy. Deliberately not closed with a content floor here: the
            // four frames are already held, per family, by
            // `RenderBaselineTests` — a committed 16 × 16 grid of mean
            // brightness, this same exact-black share, and a census of the
            // tones each family paints. Blanking `month small` was measured
            // against both: that gate went red three ways at once (a cell
            // moved 23 against a tolerance of 3, the share went 90.2 → 100.0
            // against 0.5, and the level-36 tone went 680 → 0) while this test
            // and `noHueAnywhere` stayed green. A floor here would restate a
            // gate that is already the stricter of the two.
        }
        }
    }

    @Test("With the glow up, the only thing lifting the ground is the halo")
    func haloIsWhatLiftsIt() throws {
        // The other half of the same claim, and the reason the test above turns
        // the glow down rather than loosening its tolerance.
        //
        // It used to read one corner of the small Today family, whose ring halo
        // reached `96 * ringHaloRadius * maxHaloScale` = 46.6pt and so covered a
        // 158pt frame corner to corner: there was nowhere in that frame where
        // "no mark is near". **That family is gone** (#209), and measured on the
        // four that remain, no corner is lifted at all — the corner was a
        // property of the ring, not of the halo.
        //
        // So the sample is the difference itself rather than a place. Every
        // pixel that is exactly 0,0,0 with the glow down and is not with it up
        // is a pixel the halo lifted, wherever it falls, and the claim is about
        // all of them: there are some, and every one is neutral.
        var lifted = 0
        var worstSpread = 0
        for (name, view, size) in families() {
            // Explicitly, both times. `withoutHalo` empties the cache on the way
            // in and not on the way out, so a lit render following a dark one
            // would otherwise draw the previous family's unlit tiles.
            GlowImageCache.shared.removeAll()
            let lit = try rgba(of: try renderFamily(view, size: size))
            let dark = try withoutHalo { try rgba(of: try renderFamily(view, size: size)) }
            #expect(lit.count == dark.count, "\(name) rendered two different sizes")

            // **At the ground, not at zero** (#333). This used to select
            // pixels the unlit render left at 0,0,0 and ask whether the lit one
            // raised them. The ground is a glass material now and sits at ~31,
            // so nothing is ever 0 and the selector matched nothing at all —
            // the test passed its hue clause vacuously and failed its "the glow
            // lifts something" clause, which is exactly the pair #226 warns
            // about.
            for i in stride(from: 0, to: min(lit.count, dark.count), by: 4)
            where Int(max(dark[i], dark[i + 1], dark[i + 2])) <= Self.clear {
                let high = Int(max(lit[i], lit[i + 1], lit[i + 2]))
                guard high > Self.clear else { continue }
                lifted += 1
                worstSpread = max(
                    worstSpread, high - Int(min(lit[i], lit[i + 1], lit[i + 2]))
                )
            }
        }
        GlowImageCache.shared.removeAll()

        #expect(lifted > 0, "the glow lifts no pixel off the ground at all")
        // Neutral where it lands, which is the claim that survives the halo.
        // Three levels of slack, and each is accounted for: one is the
        // encoder's own rounding between channels, #333's material dithers the
        // ground by another, and the track's 25% black inner shadow rounds
        // again where it composites over that dither. Measured at 3; an actual
        // tint lands in the tens.
        #expect(worstSpread <= 3, "the halo carries a hue: channels spread by \(worstSpread)")
    }

    @Test("No pixel the widget renders carries a hue")
    func noHueAnywhere() throws {
        // Two colours and no third. This also covers the halo, which is a white
        // shadow: near a lit mark the ground is genuinely not zero, and that is
        // the product rather than a leak — but it is still neutral.
        for (name, view, size) in families() {
            let pixels = try rgba(of: try renderFamily(view, size: size))
            var worst = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let spread = Int(max(pixels[i], pixels[i + 1], pixels[i + 2]))
                    - Int(min(pixels[i], pixels[i + 1], pixels[i + 2]))
                worst = max(worst, spread)
            }
            // Three levels of slack, each accounted for: the encoder's own
            // rounding between channels, the material dithering the ground —
            // measured at 30,31,31 and 30,32,31 on corners of one frame — and
            // the track's 25% black inner shadow rounding again where it
            // composites over that dither. Anything with an actual tint lands
            // in the tens. Held against a blank frame by the same gate as the
            // ground's own flatness. #226.
            #expect(worst <= 3, "\(name) carries a hue: channels spread by \(worst)")
        }
    }

    // MARK: - The fixture

    /// The week the committed design export depicts — today is Tuesday — so
    /// the reference is compared against its own data rather than against
    /// whatever this store happened to hold. See DesignReference/README.md.
    private func entry() -> WeekEntry {
        let anchor = WeekCalendar.day(Date())
        let week = WeekCalendar.week(containing: anchor)
        let monday = week.days[0]
        let tuesday = week.days[1]

        func habit(_ name: String, _ icon: String, _ frequency: Frequency, done: [Date]) -> HabitSnapshot {
            HabitSnapshot(id: UUID(), name: name, icon: icon, frequency: frequency, completedDays: Set(done))
        }

        return WeekEntry(
            date: tuesday,
            week: week,
            habits: .loaded([
                habit("Workout", "figure.run", .daily, done: [monday]),
                habit("Stretch", "figure.flexibility", .daily, done: [tuesday]),
                habit("Study", "book", .daily, done: [tuesday]),
                habit("Early night", "bed.double", .timesPerWeek(2), done: []),
                habit("Hydration", "drop", .daily, done: []),
                habit("Touch Grass", "leaf", .daily, done: [monday, tuesday]),
                habit("Touch Grass", "leaf", .timesPerWeek(2), done: [tuesday]),
                habit("Watch Sunset", "sunrise", .timesPerWeek(1), done: [monday]),
            ])
        )
    }

    // MARK: - Plumbing

    private func render(_ entry: WeekEntry? = nil) throws -> CGImage {
        // The paddings and background the widget configuration applies, so the
        // render is the widget as shipped rather than the bare view.
        // `containerBackground` cannot render outside WidgetKit; a plain
        // background of the same colour stands in for exactly that one
        // modifier.
        let view = WeekWidgetView(entry: entry ?? self.entry(), familyOverride: .systemLarge)
            .padding(.leading, WidgetMetrics.padLeading)
            .padding(.trailing, WidgetMetrics.padTrailing)
            .padding(.top, WidgetMetrics.padTop)
                .padding(.bottom, WidgetMetrics.padBottom)
            .frame(width: Self.size.width, height: Self.size.height)
            .background { GlowPalette.widgetSurface }
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(Self.size)
        return try #require(renderer.cgImage, "ImageRenderer produced nothing")
    }

    private func rgba(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func image(fromRGBA pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var copy = pixels
        return CGContext(
            data: &copy,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }

    @discardableResult
    private func save(_ image: CGImage, as name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = UIImage(cgImage: image).pngData() {
            try? data.write(to: url)
        }
        return url
    }
}

/// Anchors `Bundle(for:)` to this test bundle, where the design export lives.
private final class BundleToken {}
