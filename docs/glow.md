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

## The breathing

The lit slot pulses: the glowing layer's opacity eases between 0.85 and 1.0 and
back, forever, over 1.2 seconds each way. Core and halo breathe together, so the two
never drift out of step.

It is deliberately shallow. The job is to catch the eye in peripheral vision,
not to blink at anyone, and a pulse this subtle is the difference between
"something here is live" and a notification badge.

**Reduce Motion switches it off entirely.** Oscillating content is exactly what
that setting exists for, and an app whose only signal is a glowing shape has to
survive the glow standing still.

Animating opacity on the HDR layer is the thing `SlotView`'s completion
transition deliberately avoids, on the theory that a compositor might flatten an
animated HDR layer into SDR. **It does not.** Confirmed on an iPhone 14 Pro: the
slot still reads as HDR while breathing. That theory can now be retired for the
opacity case, though the completion transition keeps its approach, which is
correct for its own reasons.

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
worse than one that does not breathe, so the widget keeps a steady glow and the
breathing stays in the app, where there is a real run loop.

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
when. The provider turns that into ten frames at 10fps and then one settled
entry, animating the same direction the app does: the solid fill rises over a
glow that never changes, after a 0.2s hold. Only completing animates.
Un-completing is a correction and should not be celebrated.

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
burst timeline built. Reload latency is not the problem, and the expiry window
has fifteen times the margin it needs.

**What is still unconfirmed is the rendering.** Nobody has watched the burst
animate under a thumb, and "the timeline was built" is exactly the kind of
evidence the masked `ProgressView` sweep also had. If a real tap produces these
two lines and nothing visibly moves, the failure is WidgetKit declining to
render sub-second entries during a burst, and the burst comes out the same way
the sweep did.

## How to see inside a widget at all

A widget extension is close to unobservable: its own process, under a second of
animation, nothing to pause, and no debugger attached in ordinary use. This cost
more time than it should have, so the working route is written down.

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

and a tap should add the intent's write followed by a burst timeline of about
eleven entries.

## When the glow will not appear

Low Power Mode reduces the headroom iOS grants, so the tile tone-maps back to
ordinary white and today's slot stops being distinguishable by brightness. The
app watches `isLowPowerModeEnabled`, shows an amber banner for as long as it
lasts, and explains it once per activation — quoting the live
`currentEDRHeadroom` so the claim is checkable rather than asserted.

Low Power Mode cannot be toggled in the Simulator. Launch with
`-glow-force-low-power` to see the banner and the notice.
