// make-week-plates.swift
//
// Renders the emitting-tier plates for the "This Week" hero on the project
// page: the open ring (one to seven columns wide), the weekday letters, the
// eight default habit names and their SF Symbols — each as a PQ-encoded AVIF
// per headroom step, per responsive tier and device density, plus an alpha
// mask PNG per symbol for the page's lit tier.
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
//       [--gains 2,3,4,5,6,7,8] [--sets desktop@2,tablet@2,mobile@3]
//       [--only ring|day|name|icon] [--suffix -test]
//       [--halo-radius 0.155] [--halo-strength 0.085]
//       [--grain-depth 0.22] [--grain-softness 1.6]
//       [--pad 0.34] [--surround 000000]

import AppKit
import CoreGraphics
import SwiftUI
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
/// One plate per headroom step, for the page's slider: the same shape at 1x
/// … 8x SDR white (GlowSettings.range). 1x is written as Display P3 rather
/// than PQ, so it is exactly SDR white; it exists so the slider never mixes a
/// plate with the live CSS twin, which is rasterised differently.
let gains: [CGFloat] = arg("gains", "1,2,3,4,5,6,7,8").split(separator: ",")
    .compactMap { Double($0) }.map { CGFloat($0) }
let only = arg("only", "")
let suffix = arg("suffix", "")
// desktop@1 is not cut: a 1x screen with headroom is rare, and a 2x plate
// scaled to half is a downscale the word slider already found acceptable.
let setNames = arg("sets", "desktop@2,tablet@2,mobile@3")
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
    // DefaultHabits.all, icon = the SF Symbol name
    ("gratitude", "Gratitude", "pencil"),
    ("stretch", "Stretch", "figure.yoga"),
    ("read-book", "Read Book", "book"),
    ("workout", "Workout", "dumbbell"),
    ("vo2-max", "VO2 Max", "figure.run"),
    ("tutorial", "Tutorial", "play.rectangle"),
    ("sunset", "Sunset", "sunset"),
    ("early-night", "Early night", "bed.double"),
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

/// The habit's SF Symbol, exactly as the app draws it: `Image(systemName:)` at
/// `WidgetMetrics.iconSize` (12pt) in regular weight, rasterised by AppKit at
/// twice the plate's density and drawn down into the mask. The symbol's own
/// bounding box is the content box, so each icon's plate is its own size, as
/// the symbol is on the phone.
///
/// Alongside the emitting plate, the same mask goes out as a PNG with alpha:
/// the page paints the lit tier through it (CSS mask-image, background
/// #D9D9D9) so the two tiers are one outline. A PQ AVIF cannot carry alpha,
/// an SDR PNG can.
func symbolImage(_ name: String, pointSize: CGFloat) -> CGImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else { fatalError("no SF Symbol named \(name)") }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    else { fatalError("could not rasterise \(name)") }
    return cg
}

func iconPlate(set: RenderSet, icon: String) -> (Plate, maskPNG: Data) {
    let s = set.tier.scale
    // AppKit sizes the symbol in points; ask for the plate's pixel size as
    // points and it comes back at twice that, which is the supersample.
    let pointSize = set.px(Reference.text * s)   // WidgetMetrics.iconSize == textSize
    let cg = symbolImage(icon, pointSize: pointSize)
    let boxW = CGFloat(cg.width) / 2, boxH = CGFloat(cg.height) / 2
    let pad = max(2, (max(boxW, boxH) * padRatio).rounded())
    let width = evened(boxW + pad * 2), height = evened(boxH + pad * 2)
    let rect = CGRect(x: pad, y: pad, width: boxW, height: boxH)

    let ctx = maskContext(width: width, height: height)
    ctx.saveGState()
    ctx.clip(to: rect, mask: cg)          // the symbol's alpha is the shape
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(rect)
    ctx.restoreGState()
    guard let mask = ctx.makeImage() else { fatalError("icon mask failed") }

    // The same shape as white-on-transparent, for the page's lit tier.
    guard let rgba = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("mask png context") }
    rgba.clip(to: rect, mask: cg)
    rgba.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    rgba.fill(rect)
    guard let maskImage = rgba.makeImage() else { fatalError("mask png") }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("png destination") }
    CGImageDestinationAddImage(dest, maskImage, nil)
    CGImageDestinationFinalize(dest)

    return (Plate(
        mask: CIImage(cgImage: mask), width: width, height: height,
        contentLeft: pad, contentTop: CGFloat(height) - pad - boxH,
        contentWidth: boxW, contentHeight: boxH
    ), data as Data)
}

// MARK: - The missed mark, as the app draws it

// `CrossShape`, `InnerShadow` and the missed mark's layer stack, copied from
// Glow/Views/SlotMarkView.swift and GlowShape. An SVG filter rebuild of the
// three inner shadows came out flat and soft next to the real thing; rendering
// the app's own view through ImageRenderer is what makes the web mark the
// app's mark. It is SDR, so it goes out as a PNG with alpha and sits on any
// card colour. Keep these in step with SlotMarkView when that changes.
enum MissedMark {
    static let span: CGFloat = 11.0 / 12.0        // GlowShape.missedSpan
    static let thickness: CGFloat = 9.0 / 32.0    // GlowShape.missedThickness
    static let corner: CGFloat = 0.0352           // GlowShape.missedCorner
    static let wellOffset: CGFloat = 1.0 / 6.0    // GlowShape.missedWellOffset
    static let wellBlur: CGFloat = 1.0 / 8.0      // GlowShape.missedWellBlur
    static let socketFill: Double = 0.15          // SlotMarkView.socketFill
}

struct InnerShadow: View {
    let shape: AnyShape
    let color: Color
    let radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
    var body: some View {
        color
            .mask {
                shape.fill(.black)
                    .overlay {
                        shape.fill(.black).offset(x: x, y: y).blur(radius: radius).blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .clipShape(shape)
    }
}

struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let thickness = side * MissedMark.thickness
        let corner = side * MissedMark.corner
        let halfSpan = side * MissedMark.span / 2
        let length = 2 * (halfSpan - corner) * CGFloat(2).squareRoot() - thickness + 4 * corner
        var path = Path()
        for degrees in [45.0, -45.0] {
            var bar = Path()
            bar.addRoundedRect(
                in: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
                cornerSize: CGSize(width: corner, height: corner)
            )
            path.addPath(bar, transform: CGAffineTransform(rotationAngle: degrees * .pi / 180)
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        }
        return path
    }
}

struct MissedView: View {
    let side: CGFloat
    var body: some View {
        let shape = AnyShape(CrossShape())
        let bevel = side * MissedMark.corner
        ZStack {
            shape.fill(.black.opacity(MissedMark.socketFill))
            InnerShadow(shape: shape, color: .black, radius: bevel, y: bevel)
            InnerShadow(shape: shape, color: .white.opacity(0.25), radius: bevel, y: -bevel)
            InnerShadow(shape: shape, color: .black.opacity(0.48),
                        radius: side * MissedMark.wellBlur, y: side * MissedMark.wellOffset)
        }
        .frame(width: side, height: side)
    }
}

@MainActor
func missedPNG(set: RenderSet) -> (Data, width: Int, height: Int) {
    let renderer = ImageRenderer(content: MissedView(side: set.tier.cell))
    renderer.scale = set.dpr
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { fatalError("missed mark render") }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("png destination") }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
    return (data as Data, cg.width, cg.height)
}

// MARK: - Halo and encode (the word slider's pipeline, parameterised)

func lit(_ plate: Plate, haloRadius: CGFloat, gain: CGFloat) -> CIImage {
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

/// The plate's own shape as a PNG with alpha, at the plate's exact pixel size.
/// The page clips every plate to it with mask-image, so the plate's opaque
/// surround never reaches the screen — which is what lets the card be any
/// colour or texture, and what stops a tone-mapped surround from showing as
/// a rectangle on a screen without headroom.
func writeMask(_ plate: Plate, to url: URL) throws {
    guard let mask = ciContext.createCGImage(plate.mask, from: plate.bounds) else { throw NSError(domain: "weekplates", code: 4) }
    guard let ctx = CGContext(
        data: nil, width: plate.width, height: plate.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "weekplates", code: 5) }
    // The grey mask becomes alpha: white where the shape is, transparent elsewhere.
    ctx.clip(to: plate.bounds, mask: mask)   // a gray image without alpha clips by luminance
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(plate.bounds)
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "weekplates", code: 6) }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "weekplates", code: 7) }
}

func write(_ image: CIImage, bounds: CGRect, gain: CGFloat, to url: URL) throws {
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
        // original file name and every set shares every plate name.
        var files: [String: String] = [:]
        var lines: [String] = []
        for gain in gains {
            let file = "gw-\(set.tier.name)-\(Int(set.dpr))x-g\(Int(gain))-\(key)\(suffix).avif"
            let url = dir.appendingPathComponent(file)
            do {
                try write(lit(plate, haloRadius: haloRadius, gain: gain), bounds: plate.bounds, gain: gain, to: url)
            } catch {
                print("  \(file) FAILED: \(error)")
                return
            }
            totalBytes += (try? Data(contentsOf: url).count) ?? 0
            files[String(Int(gain))] = file
            if gain == gains.first || gain == gains.last { lines.append("\(Int(gain))x \(describe(url))") }
        }
        let maskFile = "gw-\(set.tier.name)-\(Int(set.dpr))x-\(key)-mask\(suffix).png"
        do { try writeMask(plate, to: dir.appendingPathComponent(maskFile)) } catch { print("  \(maskFile) FAILED: \(error)"); return }
        totalBytes += (try? Data(contentsOf: dir.appendingPathComponent(maskFile)).count) ?? 0
        print("  \(key)  \(plate.width)x\(plate.height)  \(lines.joined(separator: "; "))")
        // Everything in CSS pixels, so the page divides by nothing.
        var entry: [String: Any] = [
            "files": files,
            "mask": maskFile,
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
    var masks: [String: Any] = [:]
    if only.isEmpty || only == "icon" {
        for habit in habits {
            let (plate, png) = iconPlate(set: set, icon: habit.icon)
            emit("icon-\(habit.slug)", plate, haloRadius: haloRadiusRatio * plate.contentWidth,
                 extra: ["symbol": habit.icon])
            let file = "gw-\(set.tier.name)-\(Int(set.dpr))x-icon-\(habit.slug)-mask\(suffix).png"
            try png.write(to: dir.appendingPathComponent(file))
            totalBytes += png.count
            masks[habit.slug] = [
                "file": file,
                "cssWidth": Double(plate.contentWidth / set.dpr),
                "cssHeight": Double(plate.contentHeight / set.dpr),
                "pixelWidth": plate.width, "pixelHeight": plate.height,
                "offsetLeft": Double(-plate.contentLeft / set.dpr),
                "offsetTop": Double(-plate.contentTop / set.dpr),
            ]
        }
    }

    var missed: [String: Any] = [:]
    if only.isEmpty || only == "icon" {
        let (png, w, h) = MainActor.assumeIsolated { missedPNG(set: set) }
        let file = "gw-\(set.tier.name)-\(Int(set.dpr))x-missed\(suffix).png"
        try png.write(to: dir.appendingPathComponent(file))
        totalBytes += png.count
        missed = ["file": file, "pixelWidth": w, "pixelHeight": h,
                  "cssWidth": Double(CGFloat(w) / set.dpr), "cssHeight": Double(CGFloat(h) / set.dpr)]
        print("  missed  \(w)x\(h) png, \(png.count) B")
    }

    let manifest: [String: Any] = [
        "set": set.name,
        "missed": missed,
        "tier": set.tier.name,
        "dpr": Double(set.dpr),
        "cell": Double(set.tier.cell),
        "scale": Double(s),
        "gap": Double(Reference.gap * s),
        "textSize": Double(Reference.text * s),
        "font": fontPostScriptName,
        "gains": gains.map { Double($0) },
        "masks": masks,
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
