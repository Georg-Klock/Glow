# The glow

Everything about the HDR effect: what it is, what was verified, how, and what
is still unproven.

## Why an image and not a colour

Plain SwiftUI and UIKit colours never get extended dynamic range headroom.
Feeding a `Color` or `UIColor` a component above 1.0 does nothing outside a
Metal rendering context. There is no "brighter than white" for a view fill.

The channel that does work, and is the direct equivalent of the effect that
makes HDR photos glow in Photos, is a **gain-map image** decoded through the
normal image pipeline. No Metal and no custom shader required.

So the glow is literally a small photo of a glowing capsule.

## How the image is made

`Glow/Glow/GlowRenderer.swift`, in five steps:

1. Draw a greyscale capsule with a radial falloff on black, in Core Graphics.
2. Multiply it by the accent colour to get the **base** image, deliberately
   dimmed to half brightness.
3. Multiply it again by a much larger gain to get the **HDR** image.
4. Hand both to Core Image, which derives the gain map from their ratio and
   writes it as an ISO gain map alongside the base image in a JPEG.
5. Decode that JPEG back into a `UIImage` and draw it with
   `.allowedDynamicRange(.high)`.

Rendered at runtime and cached per size and colour, rather than shipped as an
asset. Asset catalogues have had unreliable support for importing gain-map
images, and a bundled sprite would have to be stretched to fit each slot width.
Encoding on demand sidesteps both and costs a few milliseconds once per
distinct slot.

### Three things that will waste your afternoon

**A non-zero bias vector gives a `CIColorMatrix` an infinite extent.** The bias
applies at every point in the plane, including outside the source image, so the
output extent becomes effectively infinite. `jpegRepresentation` cannot encode
an infinite image and returns `nil` with no error and no log line, which looks
exactly like "HDR encoding is unsupported here". Crop back to the source bounds
before encoding.

**Core Image infers headroom from the brightest pixel.** Ask for a 6x glow in
teal, whose brightest channel is 0.85, and you get 5.1x. The renderer divides
the gain by the largest colour component first, so the brightest channel lands
exactly on the requested peak. Without that, every accent glows a different
amount and the amount depends on its hue.

**JPEG has no alpha, and blend modes are a trap.** The obvious fix for a
rectangular glow tile is `.blendMode(.plusLighter)` or a `clipShape`, but any
blend or mask risks the compositor flattening the HDR layer into an SDR
offscreen buffer. Instead the glow tile is opaque with a black background and
the app background is pure black, so the corners disappear on their own and
nothing has to blend. This is why the app is dark-mode-only, and it is a
structural reason rather than a taste one.

## What is verified, and how

`Tests/GlowRendererTests.swift` asserts on the encoded bytes:

- every accent renders a file that carries a gain map;
- the gain map's `AlternateHeadroom` metadata equals the requested peak, so a
  6x glow really encodes 6x and not 5.1x;
- the glow exceeds one stop above SDR white, which fails loudly if the pipeline
  ever silently degrades to plain colour;
- without EDR the slot is a dim version of the accent, and visibly darker than
  a completed slot;
- rendering is deterministic, so the cache key is honest.

### Two tests that look right and are not

Both of these were written, both passed on a Mac, and both failed in the
simulator, which is the useful direction to fail in:

- `CIImage(data:options: [.expandToHDR: true]).contentHeadroom` returns the
  headroom **the display can show**, not the headroom in the file. A simulator
  answers 1.0 however good the file is.
- `applyingGainMap(_:headroom:)` is likewise clamped by the display, so
  reconstructing the HDR pixels and measuring them returns the base image
  unchanged on a simulator.

Either would have failed on CI and passed on a phone. The gain map's own
metadata is the display-independent fact, and it is what the tests assert.

Note that which auxiliary entry carries that metadata differs by platform: on
macOS it hangs off the ISO gain map, on iOS off the legacy one. The test reads
whichever has it.

## What is not verified

**How bright it actually looks.** Intensity depends on ambient light, display
brightness, thermal state and whether Low Power Mode is on. Design for "visibly
brighter than the surrounding UI", not for a nit value, and expect it to be
dramatic outdoors and subtle in a dim room.

**That an EDR screen renders it at all.** The encoding is proven; the
end-to-end path through `Image.allowedDynamicRange(.high)` on a real iPhone is
not, because no simulator can answer it. This is the outstanding item of Phase
0 and it needs about two minutes with a phone: run the app, add a habit, look
at today's slot in a normally-lit room and confirm it reads as lit rather than
merely coloured.

If it does not glow on device, the most likely causes, in order: the hosting
window is not permitting EDR; the completion layer is being composited in a way
that flattens dynamic range; or the peak headroom of 6.0 is too conservative
for the ambient conditions. `GlowRenderer.peakHeadroom` is the first dial to
turn.

## Tuning

`GlowRenderer` exposes the whole look as four values:

| Property | Default | Effect |
| --- | --- | --- |
| `peakHeadroom` | 6.0 | How far above SDR white the glow peaks |
| `edgeFalloff` | 0.62 | Edge brightness relative to centre |
| `sdrDimming` | 0.5 | How dim the no-headroom fallback is |
| `compressionQuality` | 0.9 | JPEG quality of the base image |
