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
        // anything. Demand evidence of content: lit pixels (the marks) and
        // mid-grey pixels (the labels and sockets).
        let pixels = try rgba(of: image)
        var lit = 0, grey = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let value = max(pixels[i], pixels[i + 1], pixels[i + 2])
            if value > 200 { lit += 1 }
            else if value > 40 { grey += 1 }
        }
        #expect(lit > 500, "no lit marks in the render")
        #expect(grey > 500, "no grey hierarchy in the render")

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
        // this row are far brighter, so a generous floor still separates the
        // line from the background without catching a dot.
        func isCut(_ y: Int) -> Bool {
            let i = (y * width + column) * 4
            guard i + 2 < pixels.count else { return false }
            return max(pixels[i], pixels[i + 1], pixels[i + 2]) > 40
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

    // MARK: - The fixture

    /// The exact week `docs/widget-large-spec.md` §14 says the design frame
    /// depicts — today is Tuesday — so a committed export of `83:1676` is
    /// compared against its own data, not against whatever this store held.
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

    private func render() throws -> CGImage {
        // The paddings and background the widget configuration applies, so the
        // render is the widget as shipped rather than the bare view.
        // `containerBackground` cannot render outside WidgetKit; a plain
        // background of the same colour stands in for exactly that one
        // modifier.
        let view = WeekWidgetView(entry: entry(), familyOverride: .systemLarge)
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
