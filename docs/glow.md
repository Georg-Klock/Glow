# The glow

Everything about the HDR effect: what it is, what was measured, and what is
still only inferred.

## Why an image and not a colour

Plain SwiftUI and UIKit colours never get extended dynamic range headroom.
Feeding a `Color` a component above 1.0 does nothing outside a Metal rendering
context, and SwiftUI has no HDR colour API: searching the iOS 26 SwiftUI
interface turns up no way to ask a shape to draw brighter than white.

The channel that does work is an HDR **image** decoded through the normal image
pipeline. So the glow is literally a small photo of a glowing capsule, rendered
at runtime by `GlowRenderer` and cached per size and colour.

## Why PQ and not a gain map

This is the part that was wrong for the first three versions of this app, so it
is worth stating plainly.

There are two ways to store HDR in a still image:

- **A gain map**: an SDR picture, plus an auxiliary map saying "here is how much
  brighter each pixel could be". This is what an iPhone camera writes, and it is
  what makes HDR photos glow in Photos.
- **PQ**: a transfer function whose range extends above SDR white, so bright
  pixels are simply *in* the image. No annotation, nothing for a decoder to
  decline.

The first implementation used gain maps. It produced files that genuinely
contained an ISO gain map with correct headroom metadata, verified by tests, and
it did not glow on a real iPhone. Measured on an iPhone 14 Pro:

| Encoding | `UIImage.isHighDynamicRange` |
| --- | --- |
| JPEG + ISO gain map | **false** |
| HEIF10 + ISO gain map | **false** |
| HEIF10, Rec. 2100 PQ | **true** |
| HEIF10, Display P3 PQ | **true** |

A gain map that the image pipeline declines to treat as HDR is an ordinary
picture of a dim capsule. The app now writes 10-bit HEIF in Rec. 2100 PQ, which
is what the technique this app is based on called for in the first place.

PQ files are also about ten times smaller: 2,230 bytes against 22,681.

### It is confirmed working

With the glow on screen, `UIScreen.currentEDRHeadroom` rises from **1.2 to
6.0**, which is exactly the renderer's `peakHeadroom`. The system granted the
headroom the image asked for, which is as close to "it glows" as a machine can
report. Reproduce it by printing `UIScreen.main.currentEDRHeadroom` before the
grid appears and three seconds after.

`potentialEDRHeadroom` on that device is 8.0, so there is room to push harder if
6x turns out to be too subtle in daylight.

## Three things that will waste your afternoon

**A non-zero bias vector gives a `CIColorMatrix` an infinite extent.** The bias
applies at every point in the plane, including outside the source image, so the
output extent becomes effectively infinite. `jpegRepresentation` cannot encode an
infinite image and returns `nil` with no error and no log line, which looks
exactly like "HDR encoding is unsupported here". Crop back to the source bounds
before encoding.

**Core Image infers headroom from the brightest pixel.** Ask for a 6x glow in
teal, whose brightest channel is 0.85, and you get 5.1x. The renderer divides
the gain by the largest colour component first, so the brightest channel lands
exactly on the requested peak. Without it, every accent glows a different amount
and the amount depends on its hue.

**The PQ encoder drops alpha.** Encoding from a bitmap with a transparent
surround produces byte-identical output to encoding from an opaque one, and the
result reports `noneSkipFirst` either way. The tile is therefore always opaque,
and callers clip it to the slot shape. That clip is what lets the app follow the
system appearance instead of requiring a black background behind every slot,
which is what an earlier version did.

## What the tests can and cannot say

`Tests/GlowRendererTests.swift` asserts on the encoded bytes: that the file is
in a PQ colour space, that ImageIO reports headroom above SDR white, that a
higher `peakHeadroom` produces more headroom, and that the decoded pixels
exceed 1.0 in extended linear.

The previous version of that file asserted a gain map was present and that its
metadata carried the right headroom. Both were true. The app did not glow. The
lesson is not "test harder" but "test the property that predicts the
behaviour": the colour space is what decided it, and nothing was checking the
colour space.

Two things that look like good tests and are not, because both ask the *display*
rather than the file, and so pass on a Mac and fail on a simulator:

- `CIImage(data:options: [.expandToHDR: true]).contentHeadroom`
- `applyingGainMap(_:headroom:)` followed by measuring the result

**No test can say how bright it looks.** Intensity depends on ambient light,
display brightness, thermal state and Low Power Mode. Design for "visibly
brighter than the surrounding UI", not for a nit value, and expect it to be
dramatic outdoors and subtle in a dim room.

## Tuning

| Property | Default | Effect |
| --- | --- | --- |
| `peakHeadroom` | 6.0 | How far above SDR white the glow peaks |
| `edgeFalloff` | 0.62 | Edge brightness relative to centre |

`GlowRenderer.colorSpace` selects the container's colour space. Display P3 PQ
measures as HDR too and is the narrower gamut of the two.
