// make-week-plates.swift
//
// Renders the emitting-tier plates for the "This Week" hero on the project
// page: the open ring (one to seven columns wide), the weekday letters, the
// eight default habit names and their icons — each as one PQ-encoded AVIF
// whose halo is baked in, per responsive tier and device density.
//
// It is make-glow-word.swift generalised. Everything that script learned
// still applies and is not repeated here; read docs/glow.md ("The same
// technique, off the phone") before changing the encode path. In short:
//
//   * PQ, not a gain map. Gain maps came back non-HDR on every device.
//   * The halo is in the pixels. CSS filters tone-map to SDR and blend modes
//     cannot undo a blurred opaque plate.
//   * Opaque black surround. ImageIO writes an invalid alpha plane, so the
//     card these sit on has to be #000000.
//   * Even dimensions. libavif refuses an odd 4:2:0 grid outright and Chrome
//     then draws nothing. Verify with `avifdec --info`, never with Preview.
//   * Font smoothing off, and render near 1:1 with the densest screen.
//
// Only the emitting tier is rendered. Lit (#D9D9D9) and resting marks are
// ordinary CSS on the page; a plate is only needed where the pixels have to
// go above SDR white.
//
// Usage:
//   swift Tools/make-week-plates.swift --out Website/week-widget/assets \
//       --font-file path/to/Inter-Regular.otf --icons Website/week-widget/icons \
//       [--gain 2] [--sets desktop@1,desktop@2,tablet@2,mobile@3]
//       [--only ring|day|name|icon] [--suffix -test]
//       [--halo-radius 0.155] [--halo-strength 0.085]
//       [--grain-depth 0.22] [--grain-softness 1.6] [--icon-box 15]
//       [--pad 0.34] [--surround 000000]

import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Arguments

func arg(_ name: String, _ fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return fallback }
    return args[i + 1]
}
func number(_ name: String, _ fallback: Double) -> CGFloat {
    CGFloat(Double(arg(name, String(fallback))) ?? fallback)
}

let outRoot = URL(fileURLWithPath: arg("out", "./out"), isDirectory: true)
let fontFile = arg("font-file", "")
let iconDir = URL(fileURLWithPath: arg("icons", "./icons"), isDirectory: true)
let gain = number("gain", 2)
let only = arg("only", "")
let suffix = arg("suffix", "")
let setNames = arg("sets", "desktop@1,desktop@2,tablet@2,mobile@3")
    .split(separator: ",").map(String.init)

// The halo, as measured for the word slider. Those numbers were tuned on
// letterforms; the ring and the icons are thinner shapes and have not been
// judged by eye yet — see the README's tuning note. Every one is an argument
// so a variant set can be cut without editing this file.
let haloRadiusRatio = number("halo-radius", 0.155)
let haloStrength = number("halo-strength", 0.085)
let grainDepth = number("grain-depth", 0.22)
let grainSoftness = number("grain-softness", 1.6)
/// Room around the shape, as a fraction of its reference size. The halo needs
/// about a third; with no halo, a few pixels for the antialiased edge suffice.
let padRatio = number("pad", 0.34)
/// The plate's surround, as a CSS hex. It has to be exactly the colour of the
/// card the plate sits on — a PQ AVIF carries no alpha — so a card that is not
/// black needs plates cut with its colour here (#202020 for the widget grey).
let surroundHex = arg("surround", "000000")
/// The square the icon glyph is drawn into, in reference points (a 24pt cell).
/// SF Symbols at 12pt ink about 12–14pt; Phosphor glyphs ink ~80% of their box.
let iconBoxRef = number("icon-box", 15)

/// Below this the plate is not HDR at all and is written as Display P3.
let sdrThreshold: CGFloat = 1.05

// MARK: - The grid's reference geometry, in points at the app's 24pt cell
//
// These are `WidgetMetrics` and `GlowShape` from the app, restated. A tier is
// this geometry times one scale factor, so every ratio survives.

enum Reference {
    static let cell: CGFloat = 24
    static let gap: CGFloat = 8            // SlotLayout.gapRatio 8/24
    static let text: CGFloat = 12          // WidgetMetrics.textSize
    static let ringWeight: CGFloat = 1     // GlowShape.ringWeight
    static let socketInset: CGFloat = 1    // GlowShape.socketInset
}

struct Tier {
    let name: String
    /// The day cell's CSS size, in CSS pixels. Everything else scales from it.
    let cell: CGFloat
    var scale: CGFloat { cell / Reference.cell }
}

let tiers: [String: Tier] = [
    "mobile": Tier(name: "mobile", cell: 21),
    "tablet": Tier(name: "tablet", cell: 36),
    "desktop": Tier(name: "desktop", cell: 48),
]

struct RenderSet {
    let tier: Tier
    let dpr: CGFloat
    var name: String { "\(tier.name)@\(Int(dpr))x" }
    /// CSS pixels to plate pixels.
    func px(_ css: CGFloat) -> CGFloat { css * dpr }
}

let sets: [RenderSet] = setNames.map { spec in
    let parts = spec.split(separator: "@")
    guard parts.count == 2, let tier = tiers[String(parts[0])],
          let dpr = Double(parts[1]) else {
        fatalError("bad set \(spec); expected tier@dpr, tiers: \(tiers.keys.sorted())")
    }
    return RenderSet(tier: tier, dpr: CGFloat(dpr))
}

// MARK: - Content

let weekdayLetters = ["M", "T", "W", "F", "S"]   // T and S repeat; one plate each
let habits: [(slug: String, name: String, icon: String)] = [
    ("gratitude", "Gratitude", "pencil"),
    ("stretch", "Stretch", "yoga"),
    ("read-book", "Read Book", "book"),
    ("workout", "Workout", "dumbbell"),
    ("vo2-max", "VO2 Max", "run"),
    ("tutorial", "Tutorial", "play-rectangle"),
    ("sunset", "Sunset", "sunset"),
    ("early-night", "Early night", "bed"),
]

// MARK: - Colour spaces and font

guard let pqSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ),
      let sdrSpace = CGColorSpace(name: CGColorSpace.displayP3),
      let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
      let maskSpace = CGColorSpace(name: CGColorSpace.linearGray)
else { fatalError("colour space unavailable") }

guard !fontFile.isEmpty else { fatalError("--font-file is required (Inter-Regular.otf)") }
guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
    URL(fileURLWithPath: fontFile) as CFURL
) as? [CTFontDescriptor], let fontDescriptor = descriptors.first
else { fatalError("could not read a font from \(fontFile)") }
let fontPostScriptName = CTFontCopyPostScriptName(
    CTFontCreateWithFontDescriptor(fontDescriptor, 12, nil)
) as String

guard let avifType = UTType("public.avif") else { fatalError("no AVIF writer on this machine") }

/// sRGB hex to the linear working space.
func linear(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { fatalError("bad --surround \(hex)") }
    func channel(_ c: UInt32) -> CGFloat {
        let s = CGFloat(c) / 255
        return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return (channel((v >> 16) & 0xff), channel((v >> 8) & 0xff), channel(v & 0xff))
}
let surround = linear(surroundHex)
let ciContext = CIContext(options: [.workingColorSpace: workingSpace])

// MARK: - Masks

/// A single-channel mask, black surround, white shape, plus where the content
/// box sits inside it. Everything downstream is derived from this.
struct Plate {
    let mask: CIImage
    let width: Int
    let height: Int
    /// The content box inside the plate, in plate pixels, from the top-left.
    let contentLeft: CGFloat
    let contentTop: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}

/// Rounded up to even. Not cosmetic — see the header.
func evened(_ v: CGFloat) -> Int { let n = Int(v.rounded(.up)); return n + (n % 2) }

func maskContext(width: Int, height: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: maskSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { fatalError("could not make a mask context") }
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

/// The open ring: `Capsule().strokeBorder(lineWidth: ringWeight).padding(socketInset)`
/// over a box `columns` wide. One column is a circle.
func ringPlate(set: RenderSet, columns: Int) -> Plate {
    let s = set.tier.scale
    let cssWidth = CGFloat(columns) * set.tier.cell + CGFloat(columns - 1) * Reference.gap * s
    let cssHeight = set.tier.cell
    let w = set.px(cssWidth), h = set.px(cssHeight)
    let pad = max(2, (set.px(set.tier.cell) * padRatio).rounded())
    let width = evened(w + pad * 2), height = evened(h + pad * 2)
    let ctx = maskContext(width: width, height: height)

    let inset = set.px(Reference.socketInset * s)
    let weight = set.px(Reference.ringWeight * s)
    // strokeBorder keeps the whole stroke inside the padded box, so the path is
    // inset by half the weight on top of the socket inset.
    let rect = CGRect(x: pad, y: pad, width: w, height: h)
        .insetBy(dx: inset + weight / 2, dy: inset + weight / 2)
    let radius = rect.height / 2
    ctx.setStrokeColor(gray: 1, alpha: 1)
    ctx.setLineWidth(weight)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()

    guard let image = ctx.makeImage() else { fatalError("ring mask failed") }
    return Plate(
        mask: CIImage(cgImage: image), width: width, height: height,
        contentLeft: pad, contentTop: CGFloat(height) - pad - h,
        contentWidth: w, contentHeight: h
    )
}

/// Text on the font's typographic box, exactly as the word slider does it.
func textPlate(set: RenderSet, text: String) -> (Plate, ascent: CGFloat, descent: CGFloat) {
    let s = set.tier.scale
    let fontSize = set.px(Reference.text * s)
    let font = CTFontCreateWithFontDescriptor(fontDescriptor, fontSize, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: NSColor.white]
    ))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

    let padX = max(2, (fontSize * padRatio).rounded()), padY = max(2, (fontSize * padRatio * 0.94).rounded())
    let width = evened(advance + padX * 2), height = evened(ascent + descent + padY * 2)
    let ctx = maskContext(width: width, height: height)
    // No stem darkening: the browser does not, and the lit text beside this
    // plate is the browser's.
    ctx.setShouldSmoothFonts(false)
    ctx.textPosition = CGPoint(x: padX, y: padY + descent)
    CTLineDraw(line, ctx)
    guard let image = ctx.makeImage() else { fatalError("text mask failed") }
    let contentHeight = ascent + descent
    return (Plate(
        mask: CIImage(cgImage: image), width: width, height: height,
        contentLeft: padX, contentTop: CGFloat(height) - padY - descent - ascent,
        contentWidth: advance, contentHeight: contentHeight
    ), ascent, descent)
}

/// An icon SVG (Phosphor, one or more `<path d>` in a 256-unit box) drawn white
/// into a square box. The path data is parsed here rather than handed to
/// NSImage: NSImage's SVG support trapped when drawn into a grey mask context,
/// and a parser also guarantees the plate and the page's inline SVG are the
/// same outline — the page uses the same `d` string for the lit tier.
func iconPlate(set: RenderSet, icon: String) -> Plate {
    let s = set.tier.scale
    let box = set.px(iconBoxRef * s)
    let pad = max(2, (box * padRatio).rounded())
    let width = evened(box + pad * 2), height = evened(box + pad * 2)
    let ctx = maskContext(width: width, height: height)

    let url = iconDir.appendingPathComponent("\(icon).svg")
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("missing icon \(url.path)")
    }
    let viewBox = SVG.viewBox(of: svg)
    // SVG y grows downward; the mask context's y grows upward. Map the view box
    // onto the box, flipped.
    let scale = box / max(viewBox.width, viewBox.height)
    ctx.saveGState()
    ctx.translateBy(x: pad, y: pad + box)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -viewBox.minX, y: -viewBox.minY)
    ctx.setFillColor(gray: 1, alpha: 1)
    for (d, evenOdd) in SVG.paths(of: svg) {
        ctx.addPath(SVG.path(from: d))
        if evenOdd { ctx.fillPath(using: .evenOdd) } else { ctx.fillPath() }
    }
    ctx.restoreGState()

    guard let cg = ctx.makeImage() else { fatalError("icon mask failed") }
    return Plate(
        mask: CIImage(cgImage: cg), width: width, height: height,
        contentLeft: pad, contentTop: CGFloat(height) - pad - box,
        contentWidth: box, contentHeight: box
    )
}

/// Just enough SVG to read Phosphor's icons: a `viewBox`, `<path d>` elements
/// with an optional `fill-rule="evenodd"`, and the path commands
/// M L H V C S Q T A Z in both cases. Nothing else is needed and nothing else
/// is parsed.
enum SVG {
    static func viewBox(of svg: String) -> CGRect {
        guard let match = svg.range(of: #"viewBox="([^"]+)""#, options: .regularExpression) else {
            return CGRect(x: 0, y: 0, width: 256, height: 256)
        }
        let numbers = svg[match].split(whereSeparator: { !"0123456789.-".contains($0) })
            .compactMap { Double($0) }
        guard numbers.count == 4 else { return CGRect(x: 0, y: 0, width: 256, height: 256) }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static func paths(of svg: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []
        let regex = try! NSRegularExpression(pattern: #"<path\b[^>]*>"#)
        let whole = NSRange(svg.startIndex..., in: svg)
        for match in regex.matches(in: svg, range: whole) {
            guard let range = Range(match.range, in: svg) else { continue }
            let tag = String(svg[range])
            guard let d = tag.range(of: #"\bd="([^"]*)""#, options: .regularExpression) else { continue }
            let data = String(tag[d]).dropFirst(3).dropLast()
            result.append((String(data), tag.contains("evenodd")))
        }
        return result
    }

    static func path(from d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") && !current.hasSuffix("E") {
                tokens.append(current); current = "-"
            } else if ch == "." && current.contains(".") && !current.contains("e") {
                tokens.append(current); current = "."
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var command: Character = "M"
        var point = CGPoint.zero, start = CGPoint.zero, control = CGPoint.zero
        func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func isNumber(_ t: String) -> Bool { Double(t) != nil }

        while i < tokens.count {
            if !isNumber(tokens[i]) { command = tokens[i].first!; i += 1 }
            let relative = command.isLowercase
            func abs(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: point.x + x, y: point.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased() {
            case "M":
                point = abs(next(), next()); start = point; path.move(to: point)
                command = relative ? "l" : "L"
            case "L":
                point = abs(next(), next()); path.addLine(to: point)
            case "H":
                let x = next(); point.x = relative ? point.x + x : x; path.addLine(to: point)
            case "V":
                let y = next(); point.y = relative ? point.y + y : y; path.addLine(to: point)
            case "C":
                let c1 = abs(next(), next()), c2 = abs(next(), next()), p = abs(next(), next())
                path.addCurve(to: p, control1: c1, control2: c2); control = c2; point = p
            case "S":
                let c1 = CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
                let c2 = abs(next(), next()), p = abs(next(), next())
                path.addCurve(to: p, control1: c1, control2: c2); control = c2; point = p
            case "Q":
                let c = abs(next(), next()), p = abs(next(), next())
                path.addQuadCurve(to: p, control: c); control = c; point = p
            case "T":
                let c = CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
                let p = abs(next(), next())
                path.addQuadCurve(to: p, control: c); control = c; point = p
            case "A":
                let rx = next(), ry = next(), rotation = next(), large = next() != 0, sweep = next() != 0
                let p = abs(next(), next())
                arc(path, from: point, to: p, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                point = p
            case "Z":
                path.closeSubpath(); point = start
            default:
                fatalError("unsupported SVG path command \(command)")
            }
            if command.uppercased() != "C" && command.uppercased() != "S"
                && command.uppercased() != "Q" && command.uppercased() != "T" {
                control = point
            }
        }
        return path
    }

    /// SVG elliptical arc to cubic Béziers (the W3C implementation notes, F.6.5).
    static func arc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                    rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        var rx = rx, ry = ry
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = (num / den).squareRoot()
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = Int(ceil(Swift.abs(delta) / (.pi / 2)))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            let e1 = CGPoint(x: cos(a), y: sin(a)), e2 = CGPoint(x: cos(b), y: sin(b))
            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cosPhi * rx * x - sinPhi * ry * y + cx, y: sinPhi * rx * x + cosPhi * ry * y + cy)
            }
            let c1 = map(e1.x - t * e1.y, e1.y + t * e1.x)
            let c2 = map(e2.x + t * e2.y, e2.y - t * e2.x)
            path.addCurve(to: map(e2.x, e2.y), control1: c1, control2: c2)
            a = b
        }
    }
}

// MARK: - Halo and encode (the word slider's pipeline, parameterised)

func lit(_ plate: Plate, haloRadius: CGFloat) -> CIImage {
    let bounds = plate.bounds
    let mask = plate.mask

    let blurred = mask
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: haloRadius])
        .cropped(to: bounds)
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .cropped(to: bounds)
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: grainSoftness])
        .cropped(to: bounds)
    let grey = noise.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
        "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
        "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
    ]).cropped(to: bounds)
    // Remapped into 1-grainDepth ... 1: the grain only ever darkens.
    let modulator = grey.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: grainDepth, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: grainDepth, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: grainDepth, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBiasVector": CIVector(x: 1 - grainDepth, y: 1 - grainDepth, z: 1 - grainDepth, w: 1),
    ]).cropped(to: bounds)
    // Multiplied, never added: black stays black.
    let textured = blurred.applyingFilter("CIMultiplyCompositing", parameters: [
        kCIInputBackgroundImageKey: modulator,
    ]).cropped(to: bounds)
    let halo = textured.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: haloStrength, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: haloStrength, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: haloStrength, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
    ]).cropped(to: bounds)

    // Maximum, not addition: the core lands exactly on `gain`.
    let shape = mask.applyingFilter("CIMaximumCompositing", parameters: [
        kCIInputBackgroundImageKey: halo,
    ]).cropped(to: bounds)

    let white = CIImage(color: CIColor(red: gain, green: gain, blue: gain, colorSpace: workingSpace)!)
        .cropped(to: bounds)
    let black = CIImage(color: CIColor(red: surround.0, green: surround.1, blue: surround.2,
                                       colorSpace: workingSpace)!).cropped(to: bounds)
    guard let out = CIFilter(name: "CIBlendWithMask", parameters: [
        kCIInputImageKey: white, kCIInputBackgroundImageKey: black, kCIInputMaskImageKey: shape,
    ])?.outputImage else { fatalError("blend failed") }
    return out.cropped(to: bounds)
}

func write(_ image: CIImage, bounds: CGRect, to url: URL) throws {
    let space = gain <= sdrThreshold ? sdrSpace : pqSpace
    guard let cg = ciContext.createCGImage(image, from: bounds, format: .RGBA16, colorSpace: space)
    else { throw NSError(domain: "weekplates", code: 1) }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, avifType.identifier as CFString, 1, nil)
    else { throw NSError(domain: "weekplates", code: 2) }
    CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "weekplates", code: 3) }
}

/// What ImageIO sees when it reads the file back. Necessary, not sufficient:
/// Apple's decoder is lenient, so `avifdec --info` is the real check.
func describe(_ url: URL) -> String {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    else { return "unreadable" }
    let depth = props[kCGImagePropertyDepth] as? Int ?? 0
    let name = (CGImageSourceCreateImageAtIndex(src, 0, nil)?.colorSpace?.name as String?) ?? "none"
    let bytes = (try? Data(contentsOf: url).count) ?? 0
    return "\(name.replacingOccurrences(of: "kCGColorSpace", with: "")), \(depth)-bit, \(bytes) B"
}

// MARK: - Run

var totalBytes = 0
for set in sets {
    let dir = outRoot.appendingPathComponent(set.name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let s = set.tier.scale
    var entries: [String: Any] = [:]
    print("\(set.name): cell \(set.tier.cell)css, scale \(s), dpr \(set.dpr)")

    func emit(_ key: String, _ plate: Plate, haloRadius: CGFloat, extra: [String: Any] = [:]) {
        // Globally unique, because Webflow's asset manager keys uploads by
        // original file name and four tiers share every plate name.
        let file = "gw-\(set.tier.name)-\(Int(set.dpr))x-\(key)\(suffix).avif"
        let url = dir.appendingPathComponent(file)
        do {
            try write(lit(plate, haloRadius: haloRadius), bounds: plate.bounds, to: url)
        } catch {
            print("  \(file) FAILED: \(error)")
            return
        }
        let bytes = (try? Data(contentsOf: url).count) ?? 0
        totalBytes += bytes
        print("  \(file)  \(plate.width)x\(plate.height)  \(describe(url))")
        // Everything in CSS pixels, so the page divides by nothing.
        var entry: [String: Any] = [
            "file": file,
            "pixelWidth": plate.width,
            "pixelHeight": plate.height,
            "cssWidth": Double(CGFloat(plate.width) / set.dpr),
            "cssHeight": Double(CGFloat(plate.height) / set.dpr),
            // Where the plate's top-left sits relative to the content box.
            "offsetLeft": Double(-plate.contentLeft / set.dpr),
            "offsetTop": Double(-plate.contentTop / set.dpr),
            "contentWidth": Double(plate.contentWidth / set.dpr),
            "contentHeight": Double(plate.contentHeight / set.dpr),
        ]
        extra.forEach { entry[$0] = $1 }
        entries[key] = entry
    }

    if only.isEmpty || only == "ring" {
        for columns in 1...7 {
            emit("ring-\(columns)", ringPlate(set: set, columns: columns),
                 haloRadius: haloRadiusRatio * set.px(set.tier.cell))
        }
    }
    let textHalo = haloRadiusRatio * set.px(Reference.text * s)
    if only.isEmpty || only == "day" {
        for letter in weekdayLetters {
            let (plate, ascent, descent) = textPlate(set: set, text: letter)
            emit("day-\(letter)", plate, haloRadius: textHalo, extra: [
                "ascent": Double(ascent / set.dpr), "descent": Double(descent / set.dpr),
            ])
        }
    }
    if only.isEmpty || only == "name" {
        for habit in habits {
            let (plate, ascent, descent) = textPlate(set: set, text: habit.name)
            emit("name-\(habit.slug)", plate, haloRadius: textHalo, extra: [
                "ascent": Double(ascent / set.dpr), "descent": Double(descent / set.dpr),
            ])
        }
    }
    if only.isEmpty || only == "icon" {
        for habit in habits {
            emit("icon-\(habit.slug)", iconPlate(set: set, icon: habit.icon),
                 haloRadius: haloRadiusRatio * set.px(iconBoxRef * s))
        }
    }

    let manifest: [String: Any] = [
        "set": set.name,
        "tier": set.tier.name,
        "dpr": Double(set.dpr),
        "cell": Double(set.tier.cell),
        "scale": Double(s),
        "gap": Double(Reference.gap * s),
        "textSize": Double(Reference.text * s),
        "iconBox": Double(iconBoxRef * s),
        "font": fontPostScriptName,
        "gain": Double(gain),
        "surround": "#" + surroundHex.replacingOccurrences(of: "#", with: ""),
        "padRatio": Double(padRatio),
        "halo": [
            "radiusRatio": Double(haloRadiusRatio), "strength": Double(haloStrength),
            "grainDepth": Double(grainDepth), "grainSoftness": Double(grainSoftness),
        ],
        "plates": entries,
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: dir.appendingPathComponent("manifest\(suffix).json"))
}
print("\nWritten to \(outRoot.path) — \(totalBytes / 1024) KB in total")
