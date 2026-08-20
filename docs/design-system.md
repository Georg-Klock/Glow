# Design system

Every colour, size and effect the app draws, and where each one comes from.

Values marked **file** are taken from the design file's own properties, not
measured off a render. `1x` values are half the file's, which is authored at 2x
for a large widget.

Source of truth in code: `Glow/Glow/GlowPalette.swift`. For the large widget,
`docs/widget-large-spec.md` is the measurement this defers to — it reads the
node's own properties through the Plugin API rather than the generated CSS, and
where the two disagree it wins.

## Colour

**There are two.** White is anything lit; grey is anything that is not. No third
colour appears in the grid, and nothing is identified by hue — only by whether
it glows and, failing that, where it sits on the grey scale.

| Token | Value | Used for |
| --- | --- | --- |
| `color` | `#FFFFFF` | every glow: marks, due labels, today's letter |
| `grey` | `#FFFFFF` @ 55% | the base for everything below |
| `labelResting` | `#FFFFFF` @ 55% | a habit already handled today |
| `headerRest` | `#FFFFFF` @ 55% | weekday letters other than today |
| `missed` | `#FFFFFF` @ 55% | a day that went unlogged |
| `upcoming` | `#FFFFFF` @ 55% | a day still to come |
| `warning` | `#FFB838` | Low Power Mode only — see below |

**One value for everything unlit.** A resting label, a weekday letter that is
not today, a missed day and a day still to come are all the same.

**It is white at 55%, not the design's solid `#8D8D93`.** On black the two match
to within six levels of blue out of 255, so nothing changes in the app — but they
are not the same thing in a widget. A Home Screen set to Tinted or Clear renders
widgets in *accented* mode, where the system tints content a single white and
keeps only the alpha. A solid grey arrives identical to a lit mark and the
hierarchy collapses to one tone; white at 55% stays 55% and the grid still reads.

The alpha is what is being stored. The colour is incidental.

The weekday letters were 60% here, taken from generated CSS that had folded a
node opacity into the colour. `docs/widget-large-spec.md` §10 is a census of all
89 paints in the frame: there is no 60% anywhere in it.

The resting label was briefly a bespoke `#C7C7CC`, lifted on the grounds that an
SDR value reads dark beside HDR. That is still true in general — worth knowing
before matching any more values off a flat render — but it stopped mattering here
once the glows went to pure white with a single halo pass. Asked for as "between
the ✕ and where the label was": the ✕ composites to rgb(70, 70, 74) and the label
was rgb(199, 199, 204), so the midpoint is `#87878B`, and the grey is 4.7% off it.

## Type

**One family, one size, one weight.** SF Pro Regular. Nothing in the file is
bold, anywhere — including the label of a habit that is due and today's weekday
letter. Those are distinguished by white plus a glow, never by weight.

| Element | File | 1x | Weight |
| --- | --- | --- | --- |
| Habit name (widget) | 24px | **12pt** | Regular |
| Weekday letter (widget) | 24px | **12pt** | Regular |
| Habit name (app) | — | 15pt (`.subheadline`) | Regular |
| Weekday letter (app) | — | 12pt (`.caption`) | Regular |

The app has no frame in this design, so its two sizes are the phone-appropriate
step up and are not from the file.

Keeping the weight fixed has a second benefit: completing a habit does not
reflow its row.

## Geometry

| Element | File | 1x | As a ratio |
| --- | --- | --- | --- |
| Slot | 35 × 35, fully round | 17.5pt | 1 |
| Gap between slots | 24 | 12pt | 0.686 of a slot |
| Completion dot | 14 | 7pt | 0.4 |
| Missed ✕ | 14 | 7pt | 0.4 |
| Bar (spanning rows) | 8 thick | 4pt | 0.235 |
| Ring stroke | 3 | 1.5pt | 0.086 |
| Label column | 196 | 98pt | — |
| Label → track gap | 30 | 15pt | — |
| Row pitch | 55 | 27.5pt | — |

Everything scales from the slot, so one track measurement drives the whole grid
and the app and the widget cannot disagree about column positions.

## Effects

A CSS blur is roughly twice a SwiftUI shadow radius, so the code carries half
each published number.

A Figma shadow radius is roughly **half** a CSS blur and roughly **equal** to a
SwiftUI `.shadow(radius:)`. `get_design_context` emits the doubled CSS numbers;
these are the file's own.

| Element | Radius | Colour | Offset |
| --- | --- | --- | --- |
| Completion dot / bar | **9** (0.514 × slot) | `#FFF` | 0 |
| Open ring, outer ×2 | **5** (0.286 × slot) @ 50% | `#FFF` | ∓1.25 |
| Open ring, inner ×2 | **2.5** (0.143 × slot) | `#FFF` | ∓1.25 |
| Due label | **1.5** | `#FFF` | 0 |
| Today's letter | **2** | `#FFF` | 0 |
| Missed ✕ | none | | |
| Upcoming disc | none | | |

Five radii — 1.5, 2, 2.5, 5, 9 — are the whole vocabulary. **No stacking:** no
element carries two shadows of different radii to fake a long tail. The only
element with more than one is the ring, and its four are two symmetric pairs.

These were briefly built at a quarter of their reach: the CSS numbers are already
doubled, and halving them again compounds the error.

### Not in the file

Three effects exist in the app and nowhere in the design:

- **HDR.** Every white above is a real PQ image with headroom, running to 6–12×
  SDR white. The file clips all of them to 255, so the app is deliberately not
  what the render shows. This is the product.
- **Breathing.** Today's open ring eases between 85% and 100% opacity, 1.2s each
  way. Requested directly; Reduce Motion switches it off. Open slots only — with
  every completion glowing, a full week of pulsing dots is unreadable.
- **Completion animation.** Ring holds 0.2s, fills solid 0.35s, collapses to the
  dot 0.25s.

### Widget appearance

A widget does not choose whether it has a background — the person does, in
**Home Screen → Edit → Customize**:

| Appearance | Rendering mode | Background |
| --- | --- | --- |
| Default | `fullColor` | ours, drawn opaquely — black |
| Tinted / Clear | `accented` | **removed**, replaced with system glass |

Under `fullColor` every alpha in a container background resolves against black,
so a `.clear` background measures as black. That is a real observation about one
appearance and was briefly written up here as a platform limit, which it is not.

Three rules follow, and the code obeys all three:

1. Declare the background with `containerBackground`, never `.background` — that
   modifier is the signal that the view may be dropped.
2. Leave `containerBackgroundRemovable` alone. It defaults to true; false opts
   out of glass, out of the StandBy and iPad Lock Screen galleries, and out of
   foreground tinting.
3. Expect content to be flattened to white, and store hierarchy in **alpha**,
   which survives. Hence the grey above.

The glow tile carries `.widgetAccentedRenderingMode(.fullColor)` so its headroom
is not tinted away. Apple reserves that for media like album art; the argument
here is that the light is the content rather than a treatment applied to it.
**Unverified on a Tinted or Clear home screen** — worth checking before it is
relied on.

### Not reproduced

**Figma's `GLASS` effect** on the widget container — radius 4, refraction 0.8,
depth 20, light at −45°. There is no SwiftUI equivalent; `Material` and
`.glassEffect` reproduce none of the refraction, dispersion or directional light.
In a flat export it contributes the faint hairline along the top-left corner arc.

**The container's 30pt corner radius**, because iOS masks a widget to its own
continuous-corner squircle regardless. The file's interior corners are plain
circular arcs — corner smoothing is 0 on all 93 corner-bearing nodes — and those
are reproduced.

## Outside the grid

The rest of the app — settings, the habit editor, the icon picker, the Low Power
notice — uses **system semantic colours** rather than these tokens: `.secondary`
(8 uses), `.tertiary`, `.primary`, `.fill.tertiary`, `.bar`, and `.indigo` on
one swipe action. That is deliberate: those screens are built from `List`,
`Form` and `ContentUnavailableView`, and a system control tinted with a custom
grey stops looking like the system.

`warning` is the single exception to the two-colour rule and is used for exactly
one thing: saying that the glow is unavailable in Low Power Mode. A warning
rendered in the app's own white would be indistinguishable from the thing it is
warning about.

## Simplification candidates

Now that it is all in one place:

- `.secondary` and `labelResting` are two greys doing one job in different
  places. They could be the same token — `.secondary` only appears on screens
  built from system controls, where a custom grey stops them looking systemic.
- `headerRest` and `labelResting` are now the same value and could be one name.
- `haloRadius` and `ringHaloRadius` differ only because the file draws the ring's
  halo softer. If the ring is going to keep its offset pair anyway, one radius
  would do.
- The app's two type sizes have no source. If the app screen gets a frame, they
  should come from it rather than from `.subheadline` and `.caption`.
