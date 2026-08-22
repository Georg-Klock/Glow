// make-glow-word.swift
//
// Renders one word as a series of HDR images, one per headroom step, for the
// brightness slider on the Glow Up project page.
//
// This is the app's GlowRenderer technique applied to type instead of a tile.
// The reasoning is identical and is written up in docs/glow.md: a browser will
// not give extended range to text any more than SwiftUI will give it to a
// Color, so the only channel that works is an image decoded through the normal
// image pipeline. PQ rather than a gain map, for the same measured reason.
//
// Two differences from the app:
//
//   * The tile carries the shape here. The app renders a uniform tile and lets
//     the view clip it; a web page has no equivalent of that clip, so the
//     letterforms are composited into the image itself.
//   * The surround is opaque black rather than transparent, because the PQ
//     encoder drops alpha. That is fine only because the page background is
//     #000000 — if the page ever stops being black, these have to be re-cut.
//
// Usage:
//   swift make-glow-word.swift --text brighter --out ./out [--font Sohne-Buch]
//                              [--size 300] [--steps 12]

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

let text = arg("text", "brighter")
let fontName = arg("font", "Sohne-Buch")
let fontSize = CGFloat(Double(arg("size", "300")) ?? 300)
let steps = Int(arg("steps", "12")) ?? 12
let outDir = URL(fileURLWithPath: arg("out", "./out"), isDirectory: true)

// Matches GlowRenderer.sdrThreshold. Below this, PQ is abandoned for Display P3,
// because PQ declares headroom on the container rather than the pixels and a 1x
// image encoded into PQ still reports nearly 5x. Off has to mean off.
let sdrThreshold: CGFloat = 1.05

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Colour spaces

guard let pqSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ),
      let sdrSpace = CGColorSpace(name: CGColorSpace.displayP3),
      let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
      let maskSpace = CGColorSpace(name: CGColorSpace.linearGray)
else { fatalError("colour space unavailable") }

// MARK: - Draw the word as a mask

guard let font = CTFontCreateWithNameAndOptions(fontName as CFString, fontSize, nil, []) as CTFont?,
      CTFontCopyPostScriptName(font) as String == fontName
else {
    fatalError("""
    Font \(fontName) not found. Installed families can be listed with:
      system_profiler SPFontsDataType | grep 'Full Name'
    """)
}

let attributed = NSAttributedString(
    string: text,
    attributes: [.font: font, .foregroundColor: NSColor.white]
)
let line = CTLineCreateWithAttributedString(attributed)

// The box is the font's own ascent/descent, not the ink bounds. Ink bounds
// would be tighter, but they move with the word: "brighter" has a descender
// and "attention" does not, so two words rendered the same way would sit on
// different baselines. Typographic metrics are stable, which is what lets the
// CSS below align the image to a text baseline with one rule.
var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

// Horizontal air only: any vertical padding would move the baseline, and the
// manifest would have to carry it. The CSS pulls this back with a negative
// margin so the word still sits where the text flow expects it.
let padX = (fontSize * 0.06).rounded()
let width = Int((typographicWidth + padX * 2).rounded(.up))
let height = Int((ascent + descent).rounded(.up))

guard let maskContext = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: maskSpace,
    bitmapInfo: CGImageAlphaInfo.none.rawValue
) else { fatalError("could not make the mask context") }

maskContext.setFillColor(gray: 0, alpha: 1)
maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
maskContext.setAllowsAntialiasing(true)
maskContext.setShouldSmoothFonts(true)
maskContext.textPosition = CGPoint(x: padX, y: descent)
CTLineDraw(line, maskContext)

guard let maskImage = maskContext.makeImage() else { fatalError("could not draw the word") }
let bounds = CGRect(x: 0, y: 0, width: width, height: height)
let mask = CIImage(cgImage: maskImage)

print("word \"\(text)\" in \(fontName) at \(Int(fontSize))pt -> \(width)x\(height)")

// MARK: - Render one step

let ciContext = CIContext(options: [.workingColorSpace: workingSpace])

/// White multiplied by `gain`, composited over black through the letterforms.
func litImage(gain: CGFloat) -> CIImage {
    let lit = CIImage(color: CIColor(red: gain, green: gain, blue: gain,
                                     colorSpace: workingSpace)!).cropped(to: bounds)
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0,
                                       colorSpace: workingSpace)!).cropped(to: bounds)
    let blend = CIFilter(name: "CIBlendWithMask", parameters: [
        kCIInputImageKey: lit,
        kCIInputBackgroundImageKey: black,
        kCIInputMaskImageKey: mask,
    ])
    guard let out = blend?.outputImage else { fatalError("blend failed") }
    // A filter whose output extends past the source would be infinite, and an
    // infinite image fails to encode by returning nil with no error at all.
    return out.cropped(to: bounds)
}

func write(_ image: CIImage, space: CGColorSpace, to url: URL, type: UTType) throws {
    if type == .heic {
        let data = try ciContext.heif10Representation(of: image, colorSpace: space, options: [:])
        try data.write(to: url)
        return
    }
    guard let cg = ciContext.createCGImage(
        image, from: bounds, format: .RGBA16, colorSpace: space
    ) else { throw NSError(domain: "glowword", code: 1) }
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, 1, nil
    ) else { throw NSError(domain: "glowword", code: 2) }
    CGImageDestinationAddImage(dest, cg, [
        kCGImageDestinationLossyCompressionQuality: 0.92,
    ] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "glowword", code: 3) }
}

/// Reads the file back and reports what a decoder will actually see. The app's
/// history here is the whole reason this exists: the gain-map version passed
/// every test it had and did not glow, because nothing was asserting on the
/// property that decides it — the colour space.
func describe(_ url: URL) -> String {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    else { return "unreadable" }
    let depth = props[kCGImagePropertyDepth] as? Int ?? 0
    let name = (CGImageSourceCreateImageAtIndex(src, 0, nil)?.colorSpace?.name as String?) ?? "none"
    let short = name.replacingOccurrences(of: "kCGColorSpace", with: "")
    let bytes = (try? Data(contentsOf: url).count) ?? 0
    return "\(short), \(depth)-bit, \(bytes) bytes"
}

// MARK: - Run

// UTType has no static member for AVIF; ImageIO knows it by identifier.
guard let avifType = UTType("public.avif") else { fatalError("no AVIF writer on this machine") }

for step in 1...steps {
    let gain = CGFloat(step)
    let isOff = gain <= sdrThreshold
    let space = isOff ? sdrSpace : pqSpace
    let image = litImage(gain: gain)
    let stem = String(format: "%@-%02d", text, step)

    // AVIF only. HEIC carries PQ just as well, but Chrome cannot decode HEIC at
    // all, and AVIF is the one HDR still format both Safari and Chromium read.
    for type in [avifType] {
        let url = outDir.appendingPathComponent("\(stem).avif")
        do {
            try write(image, space: space, to: url, type: type)
            print("  \(url.lastPathComponent)  gain \(step)x  ->  \(describe(url))")
        } catch {
            print("  \(url.lastPathComponent)  FAILED: \(error)")
        }
    }
}

// The CSS needs these three numbers to sit the image on a text baseline at any
// font size. Emitting them beats measuring the PNG by eye later.
let manifest: [String: Any] = [
    "text": text,
    "font": fontName,
    "renderedAtPt": Int(fontSize),
    "pixelWidth": width,
    "pixelHeight": height,
    "steps": steps,
    "css": [
        "height": String(format: "%.4fem", (ascent + descent) / fontSize),
        "verticalAlign": String(format: "%.4fem", -descent / fontSize),
        "marginInline": String(format: "%.4fem", -padX / fontSize),
    ],
]
let manifestURL = outDir.appendingPathComponent("manifest.json")
try JSONSerialization
    .data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: manifestURL)

print("\nWritten to \(outDir.path)")
print("CSS: height \((ascent + descent) / fontSize)em, "
      + "vertical-align \(-descent / fontSize)em, "
      + "margin-inline \(-padX / fontSize)em")
