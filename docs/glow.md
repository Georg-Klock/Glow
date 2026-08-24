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

`peakHeadroom` is a user setting now, not a constant: Settings has a slider over
1x to 12x, stored in the App Group so the widget's halo scales with it too. The
default is 6x.

| Property | Default | Effect |
| --- | --- | --- |
| `peakHeadroom` | 6.0, user-set | How far above SDR white the glow peaks |
| `edgeFalloff` | 0.62 | Edge brightness relative to centre |
| `tileSize` | 16 | Edge of the uniform tile, in pixels |

**PQ declares headroom as a property of the container, not of the pixels in
it.** Encoding a 1x image into PQ still produced a file reporting nearly 5x, so
the bottom of the slider went on glowing while the UI said "Off". Below
`sdrThreshold` the encode switches to Display P3 and the slot becomes a plain
bright capsule. Found by a test asserting that off means off, not by looking at
it.

## The widget glows too

This project spent a long time asserting the opposite, and wrote it into the
spec as a non-goal: WidgetKit renders out-of-process and archives its result, so
HDR was supposed to be impossible in a widget. That reasoning is plausible and
it was never tested.

Swapping the widget's flat capsule for the same PQ tile the app uses took one
line, and the fallback was identical either way, so the experiment cost nothing
but a build. It glows. Measured on an iPhone 14 Pro, iOS 26.

The lesson is the same one this file already records twice: the assumption was
load-bearing, cheap to check, and wrong. Check the cheap ones.

## The breathing: built, then removed

The lit slot used to pulse: the glowing layer's opacity eased between 0.85 and
1.0 and back, forever, over 1.2 seconds each way, core and halo together. It was
deliberately shallow — the job was to catch the eye in peripheral vision, not to
blink at anyone — and Reduce Motion switched it off entirely.

It came out on 2026-08-21 (#46), a reversal recorded in
[decisions.md](decisions.md). The glow already says the one thing it needs to
say — *still open* — by being brighter than white. The breath said it a second
time, in a register nothing else in the app uses: everything else here is a
state, drawn once, that changes only when you change it. With it gone, nothing
in `GlowModifier` animates, and the Reduce Motion branch that existed only to
still the breath went with it.

Two measurements from the breath's lifetime outlive it and are kept here on
purpose:

- **The compositor does not flatten an animated HDR layer into SDR.** Animating
  opacity on the HDR layer is the thing `SlotView`'s completion transition
  deliberately avoids, on exactly that theory. Confirmed wrong for the opacity
  case on an iPhone 14 Pro: the slot still read as HDR while breathing. The
  completion transition keeps its approach, which is correct for its own
  reasons.
- **The breath moved Today's rings** — a 15pt sideways walk (#45). The full
  measurement, the mechanism and the placement lesson are the next section's;
  the `geometryGroup()` it produced stays in `GlowModifier` as a guard for the
  next caller who animates anything there.

### The breath moved the ring, and only the ring

For as long as Today had rings, the per-day rings walked: about 15pt sideways
and back, in time with the breath. Measured on a 3x screen, the Water ring's
left edge swung between x=62 and x=107 while its width stayed at 271px — a
translation, not a halo growing under a threshold. The completed ring, with no
open arcs and so no glowing layer, never moved a pixel in the same frames.

`.animation(_:value:)` animates every animatable value beneath it, not the one
the modifier it sits above happens to name. `GlowModifier` builds the glow from
its content twice — once as the caster, once as the mask inside the overlay —
and where that content is a greedy shape it is measured twice. `DayRingView`'s
arcs are `Circle().trim()`, which take whatever size they are proposed, so the
second measurement lands after the repeating breath is installed. The breath
takes it for a change to interpolate and repeats it forever.

The marks never showed it because a mark is a fixed-size image with nothing
left to measure, which is why This Week looked right the whole time.

`DayRingView` is no longer in the app — the per-day kind moved to
`feature/daily-habits-2.0` (#209) — and the finding is not about it. It is about
a greedy shape under `GlowModifier`, which the next one will be too. The
`geometryGroup()` guard stays where it is.

The fix was `geometryGroup()` on the content, in `GlowModifier`, before either
the caster or the mask is built from it. **Placement is the whole fix**: the
same call written above `.opacity`, where it reads just as sensibly, was
measured still drifting — by that point both measurements have already
happened. Verified on the simulator, which cannot show the glow but shows
geometry perfectly well: pinned at x=107 across twelve frames while, at the
time, mean brightness still cycled 238 → 234 → 238 with the breath.

Since #46 removed the breath, nothing animates this geometry and the pin fixes
no live bug — it stays as a guard, still correct and still cheap, protecting
whoever animates something here next. The placement lesson is the part that
must not be lost with it.

### Breathing in the widget: measured, then removed

A widget cannot run a continuous animation — WidgetKit renders one snapshot per
timeline entry, out of process, so `repeatForever` has nothing to repeat in. The
breath was therefore baked into the timeline: entries a second apart, each
carrying the next point on the curve.

**It worked, and that is the surprising part.** WidgetKit is widely described as
having a one-minute floor on timeline entries. It does not behave that way:
printing each entry's own timestamp in the widget showed the seconds advancing
in step with the pulse, on an iPhone 14 Pro running iOS 26. Entries far finer
than a minute are rendered.

It came out anyway, because entries are free and **reloads** are not. A widget
gets roughly 40-70 timeline reloads per day, adaptively — more if you look at it
often, fewer in Low Power Mode. Only regenerating the timeline spends that
budget; the entries inside one are free. So the window length is the whole cost:

| Window | Reloads/day | Entries per timeline | |
| --- | --- | --- | --- |
| 60s | 1,440 | 60 | far over budget |
| 5 min | 288 | 300 | over budget |
| 30 min | 48 | 1,800 | fits, but a 1,800-entry timeline is fragile |

Breathing continuously for a whole day at 1s would need 86,400 entries.

The 30-minute shape is the only version that fits, and it trades the entire
day's refresh allowance for a pulse nobody is watching most of the time — while
risking the system truncating a timeline that large. A widget that is *stale* is
worse than one that does not breathe, so the widget kept a steady glow while the
breath stayed in the app, where there is a real run loop.

The app's breath has since come out too, for its own reason — one signal,
brightness, said once — so the two surfaces now agree: a lit mark is lit and
holds still, everywhere.

**An animated GIF is not a way around this.** WidgetKit renders SwiftUI to a
static snapshot; animated GIF and APNG do not animate in a widget. The only
self-updating widget primitives are `Text(timerInterval:)` and
`ProgressView(timerInterval:)`, and neither can drive opacity.

### What does not work: a masked `ProgressView` sweep

`ProgressView(timerInterval:)` and `Text(timerInterval:)` are the only two views
the system keeps animating inside a widget without a timeline entry per frame.
That makes them the obvious candidates for free motion: use one as a *mask* and
the thing it reveals appears to move on its own, one entry per cycle instead of
one per frame.

Built and tried on device: a white capsule masked by a linear
`ProgressView(timerInterval:)`, `plusLighter` over the lit slot. **Nothing
moved.** The glow rendered normally and the sweep never appeared.

It was deliberately built as an overlay rather than a replacement, so the
failure mode was "no sweep" rather than "invisible slot" — worth doing for any
effect resting on an uncertain rendering behaviour.

What this does **not** distinguish is whether `ProgressView(timerInterval:)`
fails to animate in a widget at all, or whether it animates but not once it is
inside a `.mask`. Rendering one visibly, unmasked, would settle that in one
build. Nobody has needed the answer enough to spend it yet.

### The tap burst

Motion in the widget is affordable in exactly one place: after a tap. The
`AppIntent` already writes to the store and asks WidgetKit for a new timeline,
so a second's worth of entries can ride inside the timeline that reload
produces. It spends nothing extra.

`WidgetBurst` is the note the intent leaves for the provider — which habit, and
when. The provider turns that into a **cross-fade**: three still entries, ring
fading out as the dot fades in, then the settle. Only completing animates.
Un-completing is a correction and should not be celebrated.

It did not start as a cross-fade, and the history is worth keeping. The first
version was ten frames at 10fps of the solid fill rising over the glow; that
read as a handful of stills, so it became a sampling of the app's own closing
spring — `response: 0.34, dampingFraction: 0.58`, evaluated as a second-order
step response at 40fps, roughly seventeen entries — on the theory that the two
surfaces should read as the same snap. On a real home screen it read as a
stutter instead (#40): **timeline entries do not arrive at the rate they were
sampled at**, and a curve played back at the wrong rate is not the curve.
Sampling a spring assumes the render clock is ours to spend, and it is not.
The app's `SlotView` keeps its spring — one shape, one number, no cross-fade —
so the two surfaces now read as different gestures for the same act. Accepted:
a gesture that reads wrong is worse than one that reads different, and a
widget is a sequence of stills either way.

The note expires. Without that, a midnight rollover or an edit made in the app
would replay somebody's last tap hours later, and there is a test for exactly
that. Reduce Motion skips the burst and renders the settled frame.

**The provider half is confirmed on device.** The note expires after one second,
which raised an obvious way for this to be quietly broken: if WidgetKit takes
longer than that to call the provider, the burst is always gone before it is
read and the widget renders still no matter how correct the logic is. It does
not. Measured on an iPhone 14 Pro, driving the burst from a tethered Mac with
`-glow-force-burst`:

```
15:10:04.342  forced burst for 87EC9E01-…-55D71E196D3D, reloading
15:10:04.399  timeline: 11 entries, burst 87EC9E01-…-55D71E196D3D starting 0.06s in
```

**57ms** from the write to the provider being called, and the full eleven-entry
burst timeline built. Reload latency is not the problem.

**The margin, though, was — and that sentence is now wrong** (#267). This used
to end "and the expiry window has fifteen times the margin it needs", which was
true of the burst it was measured on: the eleven-entry sampled spring, whose
window was around a second. The burst then became a three-frame cross-fade and
`WidgetBurst.duration` came down to **0.3s** — and because that one constant is
both the fade's length *and* the note's expiry, the margin came down with it
while this paragraph did not.

Measured again in the simulator with the current constant, two taps on a placed
week widget:

```
14:56:46.209  tap 3F757C9D-…: done, burst recorded
14:56:46.389  timeline: 1 entry, still (burst none pending)
14:58:49.208  tap 94676453-…: done, burst recorded
14:58:49.341  timeline: 2 entries, burst 94676453-… starting 0.17s in
```

133–180ms against a 300ms window: under 2x, and one of the two taps lost the
race outright. The other played two of three frames, starting 57% of the way
through the fade. So the reload is still fast; the window it has to beat is what
shrank.

**The rendering has since been watched, and it half-works** (#40): the entries
render — this is not the sweep's failure — but not at the rate they were
sampled at, so the sampled spring came out as a stutter rather than a close.
That observation is what turned the burst into the cross-fade above: frames
few enough that arrival rate has nothing left to ruin. The cross-fade itself
has not yet been watched on a device; when it is, this line should say so — and
per the measurement above, what is watched will usually be the tail of it or
none of it until #267 is decided.

## How to see inside a widget at all

A widget extension is close to unobservable: its own process, under a second of
animation, nothing to pause, and no debugger attached in ordinary use. This cost
more time than it should have, so the working route is written down.

**Start in the simulator.** This section is about a tethered phone because the
questions that reached it were about the glow, and it left the impression that
watching a widget at all needs hardware. It does not. A widget placed on the
simulator's Home Screen exercises the real registration, the real gallery entry,
the real provider and the real `WidgetTrace` — and the trace is easier to read
there than on a phone, because the App Group container is a directory on this
Mac:

```
plutil -p ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/\
Shared/AppGroup/*/Library/Preferences/group.com.georgklock.glow.plist
```

Simulator crash reports land in `~/Library/Logs/DiagnosticReports/` and carry
the same stacks as a phone's. #254 — the extension trapping inside WidgetKit's
own evaluation of the widget's body — was diagnosed on a device and then
reproduced in the simulator in under a minute, with an identical signature. It
had survived a day of investigation because nobody had placed a widget in the
simulator; the belief that widget behaviour needs a phone had quietly widened
from the one thing that does.

Two things still need hardware: the glow, and per-widget **configuration**,
where chronod serves stale configurations in the simulator (`docs/decisions.md`).
Everything else is cheaper here.

`log stream --device-name "<phone>"` is the documented way to read a tethered
phone's `os_log`. **The flag no longer exists** on current macOS —
`log: unrecognized option '--device-name'` — and there is then no live view into
an extension at all. Console.app still has one; nothing scriptable does.

So the same lines are also recorded into the App Group, and
`Tools/pull-widget-log.sh` fetches them. Getting them back is where the
assumptions were:

| Route out of the group container | Result |
| --- | --- |
| `devicectl copy from --source widget-trace.log` | fails — `File paths cannot contain '..'` |
| `devicectl copy from --source /` (whole container) | "succeeds", returns only `Library/`, silently omitting root-level files |
| `Library/Preferences/<group>.plist` | works |

The second row is the trap: a directory copy that reports success and returns an
incomplete tree. It does not bring back `Glow.store` either, which certainly
exists — so an empty-looking container is not evidence of an empty container,
and briefly looked like proof the App Group had broken again.

Hence the transport is the group's own `UserDefaults`. Unglamorous, and it
arrives. `WidgetTrace` records habit IDs, entry counts and timings — never a
habit's name, never anything anyone typed — capped at 60 lines, and nothing
leaves the phone by itself.

A still widget reads:

```
14:55:01.649  timeline: 1 entry, still (burst none pending)
```

and a tap should add the intent's write followed by a burst timeline of a few
entries — the cross-fade's stills and the settle.

## When the glow will not appear

Low Power Mode reduces the headroom iOS grants, so the tile tone-maps back to
ordinary white and today's slot stops being distinguishable by brightness. The
app watches `isLowPowerModeEnabled`, shows an amber banner for as long as it
lasts, and explains it once per activation — quoting the live
`currentEDRHeadroom` so the claim is checkable rather than asserted.

Low Power Mode cannot be toggled in the Simulator. Launch with
`-glow-force-low-power` to see the banner and the notice.

## The same technique, off the phone

`Tools/make-glow-word.swift` renders a word as twelve HDR images, one per
headroom step, for the brightness slider on the project page at
georgklock.com/glow-up. It is this file's argument applied to type: a browser
will not give extended range to text any more than SwiftUI will give it to a
`Color`, so the word has to be an image, encoded in PQ, for the same measured
reason the slot is.

Two things differ from `GlowRenderer`, both because a web page has no clip:

- **The letterforms are in the image.** The app renders a uniform tile and the
  view clips it to the slot. Nothing on a page does that, so the type is
  composited in.
- **The surround is opaque black**, since the PQ encoder drops alpha. That is
  only acceptable because the page background is `#000000`. If it ever stops
  being black, these have to be re-cut.

The output is AVIF rather than HEIF. Both carry PQ, but Chrome cannot decode
HEIC at all, and AVIF is the one HDR still format Safari and Chromium both read.

Measured, 2026-08-21:

| Check | Result |
| --- | --- |
| Colour space at 1x | Display P3 — off is a different encoding, as in Settings |
| Colour space at 2x and above | Rec. 2100 PQ |
| Decoded peak, extended linear | 1.00, 2.23, 3.44 … 13.08 |
| Size | ~10.5 KB per step, 126 KB for the slider |

The peaks run about 8% above the requested gain — 6x encodes to 6.67 — which is
the PQ round trip and is consistent across steps.

**Webflow does not re-encode an uploaded AVIF.** Uploaded, fetched back off the
CDN and compared: byte-identical, `image/avif` preserved, and no derivative
variants generated. That is only true of the raw asset URL. Webflow's own Image
element emits a `srcset` of resized variants, which is exactly where an HDR
original would be quietly replaced by an SDR one, so the page uses a plain
`<img>`.

**A screen without headroom must not be shown these at all.** The browser
tone-maps 6x content down to grey, so an SDR visitor sent the images would see a
word *dimmer* than the sentence around it. The page tests
`matchMedia('(dynamic-range: high)')` and falls back to ordinary white text,
hiding the slider rather than offering a control that does nothing.

The box is the font's ascent and descent rather than the ink bounds, because ink
bounds move with the word — "brighter" has a descender and "attention" does not,
so two words rendered the same way would sit on different baselines. The script
writes the metrics to `manifest.json` next to the images.

### What the browser refused, and why it took so long to see

The first set of these files was 1119x479 and **no strict decoder would touch
it**. ImageIO writes an AVIF that size as a *grid* of 512x512 tiles, and MIAF
(ISO/IEC 23000-22:2019, 7.3.11.4.2) requires a 4:2:0 grid's width and height to
be even. Both were odd, so libavif — which is what Chrome decodes with —
returned `Invalid image grid` and drew nothing at all. Not a dim word, not a
fallback: a hole in the middle of the sentence.

It survived a long time because **Apple's decoder is lenient**. The files opened
correctly in Preview, decoded through Core Image, reported the right colour
space and bit depth, and measured 1.00 to 13.08 in extended linear. Every check
run on the Mac that made them passed, because each one asked the encoder's own
vendor whether the encoder's output was valid.

`avifdec --info` said no in one line. Rounding both dimensions up to even fixed
it, and that is now what the renderer does.

**Check a written file with the decoder the target actually uses.** This is the
same lesson as the gain map, in a new costume: the property that decides the
behaviour was never the one being asserted on.

Two smaller findings from the same session:

- **Alpha is a dead end through ImageIO.** Encoding with a transparent surround
  does carry alpha into the AVIF, but writes it invalidly — `Alpha plane
  dimensions do not match color plane dimensions`. A transparent plate would
  have removed the black-background dependency and let CSS `drop-shadow` follow
  the letterforms; it is not available by this route.
- **`(dynamic-range: high)` is not a capability test.** It answers a question
  about the display, not about whether the browser will decode or paint the
  file, and a gate built on it hid the control on screens that could have shown
  it.

### The halo is in the image, not in CSS

The glow and its grain are rendered into the plate rather than added by the
page, for two reasons that are worth keeping.

A CSS filter forces a rasterisation that tone-maps to SDR, so a CSS halo around
an HDR word is a *dim* halo around a bright word — the opposite of the point.

And blurring an opaque plate cannot be undone by a blend mode. `mix-blend-mode:
screen` needs the page's black to cancel against, but an element that already
carries `filter` and `opacity` is an isolated group, so the blurred black plate
composited as grey and the word wore a visible rectangle. Measured on the
staging page by hiding one layer at a time: the box appeared with the blur layer
alone, before any grain was involved.

Baked in, the halo is HDR too, and the page's CSS is three numbers from the
renderer's `manifest.json`.

| Property | Value | Why |
| --- | --- | --- |
| `haloRadius` | `fontSize * 0.155` | Wide. A tight halo reads as an outline drawn round the word rather than as light coming off it |
| `haloStrength` | `0.085` | Faint. It is there to help the illusion, not to be the act. 0.55 was a neon sign; even 0.15 pooled brightly enough beside the stems to make the spacing look uneven |
| `grainDepth` | `0.22`, multiplied | Multiplying keeps black at black; anything additive lifts the surround |
| `grainSoftness` | `1.6` | Per-pixel noise reads as dust — and is incompressible: it took a step from 10 KB to 250 KB |

Wide and faint beats tight and strong. The first attempt reached for strength
and got a neon sign; the second kept the strength and shrank the radius, which
pooled light beside the vertical stems and made the word's own spacing look
wrong. Spreading it out and dimming it is what reads as glow.

Core and halo are combined with **maximum, not addition**: addition would push
the stroke centres above the requested gain, and dividing by the brightest
component exists precisely so the peak lands on `peakHeadroom` exactly.

About twenty kilobytes a step, 256 KB for a twelve-step slider.

### Render it at the size it will be seen at, and turn font smoothing off

Two settings that decide whether the word looks like the type it sits in.

**`setShouldSmoothFonts(false)`.** On macOS, font smoothing applies stem
darkening, which thickens the strokes. With it on, the word rendered visibly
heavier than the same font set as live text beside it — heavy enough to read as
a different, wrong cut. Browsers do not stem-darken, so neither should the
plate.

**Render at roughly display size times the densest screen that will show it.**
The first cut was 300pt, which meant 1216 natural pixels squeezed into 346
device pixels — a 3.5x reduction that softened the letterforms and, with them,
the apparent spacing. The default is now 144pt: 1:1 on a 3x display, 1.7x on a
2x one. It is also four times smaller on disk.

### The squash, and a measurement that could not have caught it

Webflow ships a global `img { max-width: 100% }`. The page gave the word image a
height and let width follow the intrinsic ratio, so that rule clamped it to the
parent's width — already narrowed by the negative margins that pull the plate's
padding back — while the height held. The letterforms rendered at **89% of their
width**. Squashed by 11%, which is exactly enough to look like the wrong
typeface without looking obviously broken.

The fix is to state both dimensions from `manifest.json` and set
`max-width: none`.

The reason it survived several rounds of checking is the part worth keeping.
The check being run was advance width: the image measured 173px, the same word
as live text measured 173px, so it was called a match. **173px was the squashed
width.** It agreed with the text only because the same negative margins that
caused the squash also pulled the box to that number — the one measurement that
reads correct precisely when the rendering is wrong. Advance width also says
nothing about x-height, cap height or letterform shape, so it could not have
caught this even in principle.

Compare the **ink box** instead, and the **aspect ratio against the natural
size**:

| Check | Before | After |
| --- | --- | --- |
| Natural → rendered aspect | 1.919 → 1.884 | 1.919 → **1.919** |
| Image ink width | — | 168.3px |
| Live text ink width | — | 168.4px |

Ink-to-ink, at 0.1px, is a claim about the rendering. Advance width was a claim
about a box that happened to be the right size.
