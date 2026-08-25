import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

/// A committed, reviewed picture of what every widget family looks like — and
/// a gate that goes red when one of them changes without anyone approving it.
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
/// The app paints exactly two colours and no ramp between them (#111), which
/// means every unlit mark deposits pixels at *one exact level* while the halo
/// around a lit mark deposits a smooth gradient. That shows in a histogram as a
/// spike standing on a ramp, and the height of the spike above the ramp —
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
///   whole grid every month. Every frame here is rendered for
///   `Fixture.anchor`, a fixed Tuesday.
/// * **The glow.** Pinned to `GlowSettings.defaultValue` with the render cache
///   cleared, because the halo is part of the picture and another suite is
///   allowed to have turned it down.
/// * **Size, scale, colour space and appearance.** 2x, sRGB, dark, over
///   `GlowPalette.widgetBackground`, exactly as the widget configurations do.
///
/// Locale still reaches the weekday initials. It is the simulator's own, en_US
/// on every machine this runs on; a machine with another one is a legitimate
/// failure of this gate and its message says so.
///
/// ## Approving a change
///
/// The manifest of what was actually rendered is attached to every run, passing
/// or failing, as `render-signatures-actual.json`. Approving a deliberate
/// visual change is copying it over `RenderTests/Baselines/render-signatures.json`
/// and saying in the pull request what moved. `Tools/test.sh` prints that
/// command with the run's own path in it.
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
                Issue.record("""
                    \(name) has no committed signature. A new family is a \
                    deliberate change: approve it into \
                    RenderTests/Baselines/render-signatures.json.
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
    /// #213's claim; every frame left paints both levels well above this. The
    /// floor still separates a tone from a rounding artefact, which is the job
    /// it was written for.
    static let toneFloor = 200

    // MARK: - The scene

    /// Every family, at the sizes a 6.1" phone gives them, rendered for one
    /// pinned day.
    struct Frame {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    static var frames: [Frame] {
        let week = Fixture.week()
        let month = Fixture.month()
        return [
            Frame(name: "week medium", size: WidgetMetrics.size(of: .systemMedium),
                  view: AnyView(WeekWidgetView(entry: week, familyOverride: .systemMedium))),
            Frame(name: "week large", size: WidgetMetrics.size(of: .systemLarge),
                  view: AnyView(WeekWidgetView(entry: week, familyOverride: .systemLarge))),
            Frame(name: "month small", size: WidgetMetrics.size(of: .systemSmall),
                  view: AnyView(MonthWidgetView(entry: month))),
        ]
    }

    /// The pinned scene. Fixed identifiers as well as a fixed date: a `UUID()`
    /// per run would be invisible in most families and is not worth finding out
    /// about the hard way.
    enum Fixture {
        /// A Tuesday, so the week has a completed past, a live today and an
        /// untouched future in it.
        static let anchor: Date = {
            var components = DateComponents()
            components.year = 2026
            components.month = 3
            components.day = 10
            return WeekCalendar.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        }()

        private static func id(_ n: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
        }

        static func week() -> WeekEntry {
            let week = WeekCalendar.week(containing: WeekCalendar.day(anchor))
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
                date: tuesday,
                week: week,
                habits: [
                    habit(1, "Workout", "figure.run", .daily, done: [monday]),
                    habit(2, "Stretch", "figure.flexibility", .daily, done: [tuesday]),
                    habit(3, "Study", "book", .daily, done: [tuesday]),
                    habit(4, "Early night", "bed.double", .timesPerWeek(2), done: []),
                    habit(5, "Hydration", "drop", .daily, done: []),
                    habit(6, "Touch Grass", "leaf", .daily, done: [monday, tuesday]),
                    habit(7, "Sunset", "sunrise", .timesPerWeek(1), done: [monday]),
                ]
            )
        }

        static func month() -> MonthEntry {
            let week = WeekCalendar.week(containing: WeekCalendar.day(anchor))
            return MonthEntry(
                date: WeekCalendar.day(anchor),
                habit: HabitSnapshot(
                    id: id(1), name: "Workout", icon: "figure.run",
                    frequency: .daily,
                    completedDays: Set(week.days.prefix(2))
                )
            )
        }
    }

    // MARK: - Rendering

    private static let scale: CGFloat = 2

    /// Renders one frame under the pinned appearance contract.
    static func render(_ frame: Frame) throws -> CGImage {
        let framed = frame.view
            .padding(.leading, WidgetMetrics.padLeading)
            .padding(.trailing, WidgetMetrics.padTrailing)
            .padding(.vertical, WidgetMetrics.padVertical)
            .frame(width: frame.size.width, height: frame.size.height)
            .background(GlowPalette.widgetBackground)
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
        defer {
            GlowSettings.store.set(previous, forKey: GlowSettings.key)
            GlowImageCache.shared.removeAll()
        }
        GlowSettings.store.set(GlowSettings.defaultValue, forKey: GlowSettings.key)
        GlowImageCache.shared.removeAll()

        var out: [String: RenderSignature] = [:]
        for frame in frames {
            out[frame.name] = RenderSignature(of: try render(frame))
        }
        return out
    }

    // MARK: - The committed file

    static func committedBaseline() throws -> RenderBaseline {
        let url = try #require(
            Bundle(for: BaselineBundleToken.self)
                .url(forResource: "render-signatures", withExtension: "json"),
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
    private func attachFailure(name: String, expected: RenderSignature, actual: RenderSignature) {
        let slug = name.replacingOccurrences(of: " ", with: "-")
        // Nothing here traps. This runs only on the failing path, and a crash
        // while collecting evidence for a failure destroys the evidence.
        if let frame = RenderBaselineTests.frames.first(where: { $0.name == name }),
           let png = try? RenderBaselineTests.render(frame),
           let data = UIImage(cgImage: png).pngData() {
            Attachment.record(data, named: "\(slug)-actual.png")
        }
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
    static let flatTones = [141, 255]

    var width: Int
    var height: Int
    /// Percentage of the frame that is exactly 0,0,0, to one decimal place.
    var exactBlackPercent: Double
    /// `side * side` mean brightness values, row-major, 0...255.
    var grid: [Int]
    /// Level → how many pixels are painted flat at it, over and above the halo
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
    /// one level; a halo deposits a ramp, one thin slice per level. So the
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
