# Design system

Every colour, size and effect the app draws, and where each one comes from.

Values marked **file** are taken from the design file's own properties, not
measured off a render. `1x` values are half the file's, which is authored at 2x
for a large widget.

Source of truth in code: `Glow/Glow/GlowPalette.swift`.

## Colour

**There are two.** White is anything lit; grey is anything that is not. No third
colour appears in the grid, and nothing is identified by hue — only by whether
it glows and, failing that, where it sits on the grey scale.

| Token | Value | Used for |
| --- | --- | --- |
| `color` | `#FFFFFF` | every glow: marks, due labels, today's letter |
| `grey` | `#8D8D93` | the base for everything below |
| `labelResting` | `#8D8D93` | a habit already handled today |
| `headerRest` | `#8D8D93` @ 60% | weekday letters other than today |
| `missed` | `#8D8D93` @ 50% | a day that went unlogged |
| `upcoming` | `#8D8D93` @ 16% | a day still to come |
| `warning` | `#FFB838` | Low Power Mode only — see below |

**One grey at four strengths, and no fifth colour anywhere.** 100% for a resting
label, 60% for a weekday letter, 50% for a miss, 16% for a day still to come.

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

| Element | File | Code |
| --- | --- | --- |
| Completion dot / bar | `0 0 18px #FFF` | one shadow, radius 0.257 × slot |
| Open ring, outer | `0 ±2.5px 10px #FFF` @ 50% | two shadows, ±y, radius 0.143 × slot, 50% |
| Due label | `0 0 3px #FFF` | one shadow, radius 0.75pt |
| Today's letter | `0 0 4px #FFF` | one shadow, radius 1pt |
| Missed ✕ | none | none |
| Upcoming disc | none | none |

Every glow is **one** shadow. It used to be three stacked at increasing radius —
an invention to approximate a long tail the file never asked for.

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

### Not reproduced

The ring's **inner glow** — `inset 0 ±2.5px 5px #FFF` in the file. The outer
halo is matched; the inset pair is not. It would have to be baked into the mask
the HDR tile is cut with, and the ring already reads as lit without it.

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
- `headerRest` at 60% and `missed` at 50% are within ten percent of each other
  and could merge, taking the grey from four steps to three.
- `haloRadius` and `ringHaloRadius` differ only because the file draws the ring's
  halo softer. If the ring is going to keep its offset pair anyway, one radius
  would do.
- The app's two type sizes have no source. If the app screen gets a frame, they
  should come from it rather than from `.subheadline` and `.caption`.
