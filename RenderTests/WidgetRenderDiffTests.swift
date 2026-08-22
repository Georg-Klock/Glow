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
        // to 141. There is one grey now and it sits at 23, so the band is 20 to
        // 26 — one level of slack either side for antialiasing against the
        // ground. A band that still reached to 141 would pass on halo bleed
        // alone and stop being evidence that anything unlit was drawn.
        let pixels = try rgba(of: image)
        var lit = 0, grey = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = max(pixels[i], pixels[i + 1], pixels[i + 2])
            if value > 200 { lit += 1 }
            else if (20...26).contains(value) { grey += 1 }
        }
        #expect(lit > 500, "no lit marks in the render")
        #expect(grey > 500, "nothing unlit in the render: \(grey) pixels at the grey")

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
        // cut is the one grey at 23, so the floor is `lineFloor` — the same 15
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
        let headerBottom = WidgetMetrics.padVertical + WidgetMetrics.headerHeight
        let firstRowTop = headerBottom + WidgetMetrics.headerGap
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
    private func brightest(atColumn centre: CGFloat, in pixels: [UInt8]) -> Int {
        let width = Int(Self.size.width * Self.scale)
        let side = SlotLayout.slotHeight(trackWidth: track)
        let top = WidgetMetrics.padVertical + WidgetMetrics.headerHeight + WidgetMetrics.headerGap
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
    /// there: a flat 2pt rule in `GlowPalette.grey`, which composites to 23
    /// on black and would be read as a mark. The cut casts no halo, so a
    /// quarter-slot clears it, and that is still well inside the window the
    /// span is supposed to have lost.
    private func brightestInRestColumn(_ index: Int, in pixels: [UInt8]) -> Int {
        let quarter = SlotLayout.dailySlot(trackWidth: track) / 4
        return max(
            brightest(atColumn: columnCentre(index) - quarter, in: pixels),
            brightest(atColumn: columnCentre(index) + quarter, in: pixels)
        )
    }

    /// One habit, so the first row's band is unambiguous.
    private func oneHabit(_ frequency: Frequency, done: [Int], todayColumn: Int) -> WeekEntry {
        let week = WeekCalendar.week(containing: WeekCalendar.day(Date()))
        return WeekEntry(
            date: week.days[todayColumn],
            week: week,
            habits: [HabitSnapshot(
                id: UUID(), name: "Gym", icon: "figure.run",
                frequency: frequency, completedDays: Set(done.map { week.days[$0] })
            )]
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

    /// A span's own line, unlit. Since #47 an achieved span is structure rather
    /// than a mark, so "is the span there" is a question about the grey line,
    /// not about light — `GlowPalette.grey` composites to 23 on black.
    private static let lineFloor = 15
    private static let clear = 10

    @Test("A met goal with Sunday resting stops at Saturday")
    func metGoalStopsBeforeSunday() throws {
        let entry = oneHabit(.timesPerWeek(2), done: [0, 1], todayColumn: 4)
        try withRestColumn(6, of: entry.week) {
            let pixels = try rgba(of: try render(entry))
            let saturday = brightest(atColumn: columnCentre(5), in: pixels)
            let sunday = brightestInRestColumn(6, in: pixels)
            #expect(saturday > Self.lineFloor,
                    "the met-goal line is missing at Saturday (\(saturday))")
            #expect(sunday < Self.clear,
                    "the line runs into Sunday's column (\(sunday))")
        }
    }

    @Test("A met goal with Wednesday resting is cut in two")
    func metGoalIsCutInTheMiddle() throws {
        let entry = oneHabit(.timesPerWeek(2), done: [0, 1], todayColumn: 4)
        try withRestColumn(2, of: entry.week) {
            let pixels = try rgba(of: try render(entry))
            let tuesday = brightest(atColumn: columnCentre(1), in: pixels)
            let wednesday = brightestInRestColumn(2, in: pixels)
            let thursday = brightest(atColumn: columnCentre(3), in: pixels)
            #expect(wednesday < Self.clear, "the line crosses the rest day (\(wednesday))")
            #expect(tuesday > Self.lineFloor, "the left piece is missing (\(tuesday))")
            #expect(thursday > Self.lineFloor, "the right piece is missing (\(thursday))")
        }
    }

    @Test("The days carry the light, and the span does not")
    func daysCarryTheLight() throws {
        // #47 in one render. Two a week with Monday and Tuesday logged: the
        // span across the week is an unlit line, and the two days it happened
        // on are lit dots on it.
        let entry = oneHabit(.timesPerWeek(2), done: [0, 1], todayColumn: 4)
        try withRestColumn(6, of: entry.week) {
            let pixels = try rgba(of: try render(entry))
            for logged in [0, 1] {
                #expect(brightest(atColumn: columnCentre(logged), in: pixels) > 150,
                        "no lit dot on the day it was logged (column \(logged))")
            }
            // Wednesday and Thursday were not logged: line, no light.
            for quiet in [2, 3] {
                let value = brightest(atColumn: columnCentre(quiet), in: pixels)
                #expect(value > Self.lineFloor, "the line is missing at column \(quiet)")
                #expect(value < 150, "column \(quiet) is lit and nothing happened on it")
            }
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
                for: entry.habits[0], in: entry.week, today: entry.date, target: 2
            )
            let open = try #require(spans.first { $0.state == .open })
            #expect(open.firstDay < 2 && open.lastDay > 2, "the fixture does not straddle Wednesday")

            let pixels = try rgba(of: try render(entry))
            let wednesday = brightestInRestColumn(2, in: pixels)
            let before = brightest(atColumn: columnCentre(open.firstDay), in: pixels)
            let after = brightest(atColumn: columnCentre(3), in: pixels)
            #expect(wednesday < 60, "the open span crosses the rest day (\(wednesday))")
            #expect(before > 150, "the left arc is missing (\(before))")
            #expect(after > 150, "the right arc is missing (\(after))")
        }
    }

    // MARK: - The ground is 0,0,0 (#87)

    /// Renders one view at a widget's own size, over the declared background,
    /// exactly as the configurations do.
    private func renderFamily(
        _ view: some View, size: CGSize, vertical: CGFloat = WidgetMetrics.padVertical
    ) throws -> CGImage {
        let framed = view
            .padding(.leading, WidgetMetrics.padLeading)
            .padding(.trailing, WidgetMetrics.padTrailing)
            .padding(.vertical, vertical)
            .frame(width: size.width, height: size.height)
            .background(GlowPalette.widgetBackground)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(size)
        return try #require(renderer.cgImage, "ImageRenderer produced nothing")
    }

    /// Every family, at the sizes a 6.1" phone gives them.
    private func families() -> [(String, AnyView, CGSize)] {
        let week = entry()
        let today = TodayEntry(date: week.date, habits: [
            DayRingSnapshot(id: UUID(), name: "Water", icon: "drop", target: 6, done: 2),
        ])
        return [
            ("week small", AnyView(WeekWidgetView(entry: week, familyOverride: .systemSmall)),
             CGSize(width: 158, height: 158)),
            ("week medium", AnyView(WeekWidgetView(entry: week, familyOverride: .systemMedium)),
             CGSize(width: 338, height: 158)),
            ("week large", AnyView(WeekWidgetView(entry: week, familyOverride: .systemLarge)),
             CGSize(width: 338, height: 354)),
            ("today small", AnyView(TodaySmallView(entry: today)),
             CGSize(width: 158, height: 158)),
            ("today medium", AnyView(TodayMediumView(entry: today)),
             CGSize(width: 338, height: 158)),
            // The densest family, and the one most likely to lose the ground
            // claim without anyone noticing: six rows of seven cells, where a
            // lifted floor reads as "the marks are dim" rather than as "the
            // background is wrong".
            ("month small", AnyView(MonthWidgetView(entry: monthEntry())),
             CGSize(width: 158, height: 158)),
        ]
    }

    /// A month with something in it: completions, misses, and today still open,
    /// so the sweep runs against marks rather than an empty grid.
    private func monthEntry() -> MonthEntry {
        let week = entry()
        return MonthEntry(
            date: week.date,
            habit: HabitSnapshot(
                id: UUID(), name: "Workout", icon: "figure.run",
                frequency: .daily,
                completedDays: Set(week.week.days.prefix(2))
            )
        )
    }

    /// Renders with the glow at the bottom of its range, where
    /// `GlowSettings.haloScale` is 0 and no mark casts a shadow.
    ///
    /// The background cannot be measured with the halo on. A lit mark spreads
    /// white onto the ground on purpose — that is the product, not a leak — and
    /// on the small Today family the ring's halo reaches
    /// `96 * ringHaloRadius * maxHaloScale` = 46.6pt, which covers a 158pt
    /// frame corner to corner. Its corners read 1,1,1 with the glow up, and
    /// **0,0,0 with it down**, which is what proves the one level is the halo
    /// and not the ground.
    private func withoutHalo<T>(_ body: () throws -> T) rethrows -> T {
        let previous = GlowSettings.store.object(forKey: GlowSettings.key)
        defer { GlowSettings.store.set(previous, forKey: GlowSettings.key) }
        GlowSettings.store.set(GlowSettings.range.lowerBound, forKey: GlowSettings.key)
        GlowImageCache.shared.removeAll()
        return try body()
    }

    @Test("The ground is 0,0,0 in every family, exactly")
    func groundIsPureBlack() throws {
        try withoutHalo {
        // The corners, which no halo reaches. Exactly zero, not a tolerance
        // band: the claim is pure black, and "nearly" is the thing being
        // ruled out — the design file's own container is a ~13-level gradient,
        // and that is exactly the difference this refuses.
        for (name, view, size) in families() {
            let image = try renderFamily(view, size: size)
            let pixels = try rgba(of: image)
            let w = image.width, h = image.height
            for (x, y) in [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)] {
                let i = (y * w + x) * 4
                #expect(pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0,
                        "\(name) corner (\(x),\(y)) is \(pixels[i]),\(pixels[i+1]),\(pixels[i+2])")
            }

            // And most of the frame is exactly zero. A gradient, a tint or a
            // material would lift every one of these off the floor at once,
            // which a corner sample alone could miss if it were subtle at the
            // edges.
            var exact = 0
            for i in stride(from: 0, to: pixels.count, by: 4)
            where pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0 {
                exact += 1
            }
            let share = Double(exact) * 100 / Double(w * h)
            print("bg-audit: \(name) exact-black \(String(format: "%.1f", share))%")
            // 95-98% measured across the five. A gradient, a tint or a material
            // would lift every one of these off the floor at once, which a
            // corner sample alone could miss if it were subtle at the edges.
            #expect(share > 90, "\(name): only \(Int(share))% of the frame is pure black")
        }
        }
    }

    @Test("With the glow up, the only thing lifting the ground is the halo")
    func haloIsWhatLiftsIt() throws {
        // The other half of the same claim, and the reason the test above turns
        // the glow down rather than loosening its tolerance. On the small Today
        // family the ring's halo covers the whole frame — corner to corner —
        // so there is nowhere in it that "no mark is near".
        let (_, view, size) = families()[3]
        let lit = try rgba(of: try renderFamily(view, size: size))
        let dark = try withoutHalo { try rgba(of: try renderFamily(view, size: size)) }

        func corner(_ p: [UInt8]) -> Int { Int(p[(1 * Int(size.width * Self.scale) + 1) * 4]) }
        #expect(corner(dark) == 0, "the ground itself is not black")
        #expect(corner(lit) > 0, "the halo does not reach the corner after all")
        // And it is still neutral where it lands, which is the claim that
        // survives the halo.
        let i = (1 * Int(size.width * Self.scale) + 1) * 4
        #expect(lit[i] == lit[i + 1] && lit[i + 1] == lit[i + 2])
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
            // One level of slack for the encoder's own rounding between
            // channels; anything with an actual tint lands far above it.
            #expect(worst <= 1, "\(name) carries a hue: channels spread by \(worst)")
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
            habits: [
                habit("Workout", "figure.run", .daily, done: [monday]),
                habit("Stretch", "figure.flexibility", .daily, done: [tuesday]),
                habit("Study", "book", .daily, done: [tuesday]),
                habit("Early night", "bed.double", .timesPerWeek(2), done: []),
                habit("Hydration", "drop", .daily, done: []),
                habit("Touch Grass", "leaf", .daily, done: [monday, tuesday]),
                habit("Touch Grass", "leaf", .timesPerWeek(2), done: [tuesday]),
                habit("Watch Sunset", "sunrise", .timesPerWeek(1), done: [monday]),
            ]
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
            .padding(.vertical, WidgetMetrics.padVertical)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(GlowPalette.widgetBackground)
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
