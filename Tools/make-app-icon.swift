#!/usr/bin/env swift
//
// Generates the app icon into the asset catalogue.
//
//     swift Tools/make-app-icon.swift
//
// The icon is the app's one idea at its simplest: a single slot, lit. Not a
// row of seven, which turns to mush at 40 points.
//
// Committed as a script rather than as a hand-drawn asset so the icon can be
// re-derived when the accent changes, and so the geometry is stated once
// rather than eyeballed. The generated PNGs are committed too: a build should
// never depend on a script having been run.
//
// Three variants, per the iOS 18 icon appearances:
//   light   opaque black background, the glow in the app's white
//   dark    transparent, composited on the system's backdrop
//   tinted  transparent, greyscale, the system applies the user's tint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
// Must track GlowPalette.components: an icon in the old accent is the
// clearest possible signal that the app's colour moved and the icon did not.
let glow = (red: 0.85, green: 0.91, blue: 1.0)

enum Variant: String, CaseIterable {
    case light = "AppIcon"
    case dark = "AppIcon-Dark"
    case tinted = "AppIcon-Tinted"

    var isOpaque: Bool { self == .light }
    var isGreyscale: Bool { self == .tinted }
}

func drawIcon(_ variant: Variant) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    if variant.isOpaque {
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(bounds)
    }

    let centre = CGPoint(x: bounds.midX, y: bounds.midY)
    let core = Double(side) * 0.19          // radius of the solid slot
    let bloom = Double(side) * 0.46         // how far the halo carries

    func colour(_ level: Double, alpha: Double) -> CGColor {
        let rgb = variant.isGreyscale
            ? (red: 1.0, green: 1.0, blue: 1.0)
            : glow
        return CGColor(
            srgbRed: rgb.red * level,
            green: rgb.green * level,
            blue: rgb.blue * level,
            alpha: alpha
        )
    }

    // The halo, as a smooth exponential falloff sampled into many stops.
    //
    // Three stops with a mid-point is the obvious way to write this and it
    // produces a visible ring at the mid-point plus banding across the dark
    // tail, because a piecewise-linear ramp has a corner at every stop. A
    // sampled curve has no corners to see.
    let stopCount = 48
    let edgeLevel = 0.72  // where the slot's own edge lands, so the seam matches
    var haloColours: [CGColor] = []
    var haloLocations: [CGFloat] = []
    for step in 0...stopCount {
        let t = Double(step) / Double(stopCount)
        let falloff = exp(-4.2 * t)
        haloColours.append(
            variant.isOpaque
                ? colour(edgeLevel * falloff, alpha: 1)
                : colour(edgeLevel, alpha: falloff)
        )
        haloLocations.append(CGFloat(t))
    }
    if let halo = CGGradient(
        colorsSpace: space,
        colors: haloColours as CFArray,
        locations: haloLocations
    ) {
        context.drawRadialGradient(
            halo,
            startCenter: centre,
            startRadius: core * 0.97,
            endCenter: centre,
            endRadius: bloom,
            options: []
        )
    }

    // Then the slot itself, with the same centre-to-edge falloff the real slots
    // have, so the icon and the app agree about what a lit slot looks like.
    context.saveGState()
    context.addPath(CGPath(
        ellipseIn: CGRect(
            x: centre.x - core,
            y: centre.y - core,
            width: core * 2,
            height: core * 2
        ),
        transform: nil
    ))
    context.clip()
    if let fill = CGGradient(
        colorsSpace: space,
        colors: [colour(1.0, alpha: 1), colour(0.72, alpha: 1)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawRadialGradient(
            fill,
            startCenter: centre,
            startRadius: 0,
            endCenter: centre,
            endRadius: core,
            options: [.drawsAfterEndLocation]
        )
    }
    context.restoreGState()

    return context.makeImage()
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "Glow/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

for variant in Variant.allCases {
    guard let image = drawIcon(variant) else {
        FileHandle.standardError.write(Data("failed to draw \(variant.rawValue)\n".utf8))
        exit(1)
    }
    let url = iconSet.appending(path: "\(variant.rawValue).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        FileHandle.standardError.write(Data("failed to write \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    print("wrote \(url.lastPathComponent)")
}

let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
