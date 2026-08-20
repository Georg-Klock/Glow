# Widget — Large (Figma `83:1676`)

A complete measurement of the large widget frame in `Glow-Up`
(file `0m9qFcvvUrIgLmqIxE0jtj`, page **05 Widgets**, node **`83:1676`**).

Every number here is read off the node's own properties via the Figma Plugin
API — not measured off a render, not inferred from the generated CSS, not
rounded to something tidier. Where the file sits on a half point, so does this
document.

**Read this first:**

- The frame is authored at **1×**. It is 338 × 354, which is the point size of a
  large widget on a 6.1″ iPhone, so **every number below is already in points**.
  (This differs from `docs/design-system.md`, whose "File" column is 2× — that
  column describes a different frame.)
- The subtree is **117 nodes**. There are **no components, no instances, no
  shared styles, and no variables** anywhere in it. `get_variable_defs` returns
  `{}`. Every value is a literal on a raw `FRAME`, `TEXT`, `RECTANGLE`, or
  `BOOLEAN_OPERATION`. Nothing in the file is tokenised.
- Coordinates are given two ways. **Local** = the node's `x`/`y` inside its
  parent (what Figma's inspector shows). **Widget** = resolved to the root
  frame's top-left corner. Where only one is given, it is local.

---

## 1. At a glance

| | |
| --- | --- |
| Node | `83:1676` — `Widget — Large` |
| Type | `FRAME` |
| Size | **338 × 354** pt |
| Canvas position | x `4636`, y `2272` |
| Rotation | `0` |
| Corner radius | **30** pt, uniform |
| Clips content | **false** |
| Export settings | none |
| Parent | page `05 Widgets` |
| Mask | no |

Aspect ratio 338 : 354 = 0.955. The widget is very slightly taller than wide.

---

## 2. Layer tree

Indentation is the real hierarchy. Sizes are `w × h`, positions are local.

```
83:1676  Widget — Large          FRAME   338 × 354   @ 4636, 2272 (canvas)
└ 83:1677  content               FRAME   338 × 354   @ 0, 0        clips
  ├ 83:1678  Frame 3  (header)   FRAME   307 × 14    @ 15, 16
  │ ├ 83:1679  Text  (spacer)    TEXT      0 × 14    @ 0, 0
  │ └ 83:1680  track             FRAME   214 × 14    @ 108.5, 0
  │   ├ 83:1681  filled          FRAME    28 × 14    @ 0, 0      └ 83:1682  "M"
  │   ├ 83:1683  filled          FRAME    28 × 14    @ 29.5, 0   └ 83:1684  "T"
  │   ├ 83:1685  filled          FRAME    28 × 14    @ 59, 0     └ 83:1686  "W"
  │   ├ 83:1687  filled          FRAME    28 × 14    @ 88.5, 0   └ 83:1688  "T"
  │   ├ 83:1689  filled          FRAME    28 × 14    @ 118, 0    └ 83:1690  "F"
  │   ├ 83:1691  filled          FRAME    28 × 14    @ 147.5, 0  └ 83:1692  "S"
  │   └ 83:1693  filled          FRAME    28 × 14    @ 177, 0    └ 83:1694  "S"
  └ 83:1695  Frame 1  (rows)     FRAME   313 × 210   @ 15, 43
    ├ 83:1696  Early night       FRAME   313 × 17.5  @ 0, 0        ← Workout
    ├ 83:1709  Early night       FRAME   313 × 17.5  @ 0, 27.5     ← Stretch
    ├ 83:1725  Early night       FRAME   313 × 17.5  @ 0, 55       ← Study
    ├ 83:1741  Early night       FRAME   313 × 17.5  @ 0, 82.5     ← Early night
    ├ 83:1748  Early night       FRAME   313 × 17.5  @ 0, 110      ← Hydration
    ├ 83:1763  Early night       FRAME   313 × 17.5  @ 0, 137.5    ← Touch Grass
    ├ 83:1777  Early night       FRAME   313 × 17.5  @ 0, 165      ← Touch Grass
    └ 83:1786  Early night       FRAME   313 × 17.5  @ 0, 192.5    ← Watch Sunset
```

Every habit row frame is named `Early night` regardless of which habit it holds —
the name is a leftover from the row that was duplicated to make the others. The
real habit identity is in the two `TEXT` children of its `label`.

Each habit row has exactly two children:

```
83:16xx  Early night   FRAME   313 × 17.5
├ label               FRAME    98 × 17.5   @ 0, 0
│ ├ (icon)            TEXT      ~ × 17     @ ~0–4.5, 0.625   SF Symbol glyph
│ └ (name)            TEXT      ~ × 14     @ 28.5, 0.625
└ track               FRAME   200 × 17.5   @ 113, 0
  └ 1–7 slot frames
```

---

## 3. The container

### 3.1 Fill — one linear gradient

The root's only fill:

| Property | Value |
| --- | --- |
| Type | `GRADIENT_LINEAR` |
| Paint opacity | **0.20** |
| Blend mode | `NORMAL` |
| `gradientTransform` | `[[6.123e-17, 1, 0], [-1, 6.123e-17, 1]]` |

That transform is a 90° rotation, so the gradient runs **straight down**, top
edge to bottom edge.

| Stop | Position | Colour | Stop alpha | **Effective alpha** (stop × paint) |
| --- | --- | --- | --- | --- |
| 0 | `0.0` | `#464649` — rgb(70, 70, 73) | `0.15` | **0.03** |
| 1 | `1.0` | `#000000` — rgb(0, 0, 0) | `0.15` | **0.03** |

So the rendered gradient is:

```
top     rgba(70, 70, 73, 0.03)
bottom  rgba( 0,  0,  0, 0.03)
```

Both ends carry the same 3% alpha; only the hue changes, from a near-black warm
grey to true black. On a black wallpaper the whole thing amounts to a barely
perceptible lightening of the top edge — about 2 levels out of 255 — which is
the entire point: it separates the widget's corner from the wallpaper without
reading as a panel.

### 3.2 Effect — Figma "Glass"

One effect on the root, and only on the root:

| Property | Value |
| --- | --- |
| Type | `GLASS` |
| Visible | `true` |
| Radius | **4** |
| Refraction | **0.8** |
| Depth | **20** |
| Light angle | **−45°** |
| Light intensity | **0.8** |
| Dispersion | **0.5** |
| Splay | **0** |

This is Figma's liquid-glass effect, not a background blur and not a shadow. It
has no direct SwiftUI equivalent; the nearest analogue is `.glassEffect(…)` /
`Material`, and neither reproduces the refraction, dispersion, or the −45°
directional light. In the flat PNG export it contributes the faint bright
hairline along the top-left corner arc.

### 3.3 Strokes

**None.** `strokes: []`. The widget has no border. The corner is defined
entirely by the 30 pt radius against the wallpaper.

### 3.4 `content` (`83:1677`)

A full-bleed child frame that carries the padding and does the clipping.

| Property | Value |
| --- | --- |
| Size | 338 × 354 (identical to the root) |
| Position | 0, 0 |
| Fill | none |
| **Clips content** | **true** |
| Layout mode | `VERTICAL` |
| Item spacing | **13** |
| Padding top | **16** |
| Padding right | **16** |
| Padding bottom | **16** |
| Padding left | **15** |
| Primary axis sizing | `FIXED` |
| Counter axis sizing | `FIXED` |
| Primary align | `MIN` (top) |
| Counter align | `MIN` (leading) |
| Wrap | `NO_WRAP` |

**The padding is not symmetric: 15 left, 16 right.** This is deliberate and
should not be averaged. The last slot's right edge lands at x = 322.5 (see
§7.2), 0.5 pt past the 322 content edge — the extra point on the right is what
keeps the last column off the rounded corner.

Content box: **307 × 322**, spanning x 15 → 322, y 16 → 338.

Because `content` clips and the root does not, **any glow that spills past
x 0/338 or y 0/354 is cut**, but nothing spills that far in this composition.

---

## 4. The vertical spine

| Band | From y | To y | Height | Source |
| --- | --- | --- | --- | --- |
| Top padding | 0 | 16 | 16 | `content.paddingTop` |
| Header row | 16 | 30 | 14 | `83:1678` height |
| Header → rows gap | 30 | 43 | 13 | `content.itemSpacing` |
| Row stack | 43 | 253 | 210 | `83:1695` height |
| **Empty** | 253 | 338 | **85** | slack |
| Bottom padding | 338 | 354 | 16 | `content.paddingBottom` |

### Row stack (`83:1695`, "Frame 1")

| Property | Value |
| --- | --- |
| Size | 313 × 210 |
| Position | 15, 43 (widget) |
| Layout mode | `VERTICAL` |
| Item spacing | **10** |
| Padding | 0 on all four sides |
| Primary / counter sizing | `AUTO` / `AUTO` (hug both axes) |
| Align | `MIN` / `MIN` |

Height check: 8 rows × 17.5 + 7 gaps × 10 = 140 + 70 = **210** ✓

**Row pitch = 27.5** (17.5 slot + 10 gap).

Row top edges, in widget coordinates:

| Row | Habit | y (local) | y (widget) |
| --- | --- | --- | --- |
| 1 | Workout | 0 | **43** |
| 2 | Stretch | 27.5 | **70.5** |
| 3 | Study | 55 | **98** |
| 4 | Early night | 82.5 | **125.5** |
| 5 | Hydration | 110 | **153** |
| 6 | Touch Grass | 137.5 | **180.5** |
| 7 | Touch Grass | 165 | **208** |
| 8 | Watch Sunset | 192.5 | **235.5** |

### Row capacity

Vertical space available to the row stack is 322 − 14 − 13 = **295**.

`n × 17.5 + (n − 1) × 10 ≤ 295` → `n ≤ 11.09`, so the widget holds **11 rows**
at this pitch (11 rows measure 292.5). Eight are drawn. The **85 pt of empty
space** below the last row is unclaimed capacity, not a designed gutter — the
row stack hugs its content, so it simply stops.

---

## 5. The horizontal spine

| Band | From x | To x | Width | Source |
| --- | --- | --- | --- | --- |
| Left padding | 0 | 15 | 15 | `content.paddingLeft` |
| Label column | 15 | 113 | **98** | `label` frame width |
| Label → track gap | 113 | 128 | **15** | row `itemSpacing` |
| Track column | 128 | 328 | **200** | `track` frame width |
| *(track content ends)* | | *322.5* | | last slot right edge |
| Right padding | 322 | 338 | 16 | `content.paddingRight` |

The **track frame is declared 200 wide but its content ends at 194.5** (last
slot at local x 177 + 17.5). The frame therefore overhangs its own children by
5.5, and overhangs the content box by 6. Nothing renders in that overhang, so
it is invisible — but it means you cannot use the track's declared width to
derive column positions. Derive them from the pitch instead.

### Inside a habit row (`83:1696` and its seven siblings)

| Property | Value |
| --- | --- |
| Size | 313 × 17.5 |
| Layout mode | `HORIZONTAL` |
| Item spacing | **15** |
| Padding | 0 on all four sides |
| Primary axis sizing | `FIXED` (313) |
| Counter axis sizing | `AUTO` (hug → 17.5) |
| Primary align | `MIN` |
| **Counter align** | **`CENTER`** |
| Wrap | `NO_WRAP` |

Width check: 98 + 15 + 200 = **313** ✓

---

## 6. The header row

### 6.1 `Frame 3` (`83:1678`)

| Property | Value |
| --- | --- |
| Size | 307 × 14 @ 15, 16 (widget) |
| Layout mode | `HORIZONTAL` |
| **Item spacing** | **108.5** |
| Padding | 0 |
| Primary / counter sizing | `FIXED` / `AUTO` |
| Layout sizing | `FILL` / `HUG` |
| Align | `MIN` / `MIN` |
| Clips | false |

### 6.2 The spacer text (`83:1679`)

| Property | Value |
| --- | --- |
| Type | `TEXT` |
| Characters | `"    "` — four literal spaces |
| **Measured size** | **0 × 14** |
| Fill | `#8D8D93` @ 100% |
| Font | SF Pro Regular, 12 |
| Line height | `AUTO` |
| Letter spacing | 0% |
| Align | `LEFT` / `TOP` |
| Auto-resize | `WIDTH_AND_HEIGHT` |

Figma measures the trailing spaces as **zero width**, so this node contributes
nothing to the layout. It is a vestigial placeholder standing in for the label
column. All of the header's leading offset comes from the parent's 108.5 gap.

**Consequence:** the header's horizontal registration is governed by `108.5`,
while the rows' is governed by `98 + 15 = 113`. These are two independent
numbers describing the same column boundary, and they disagree — see §9.1.

### 6.3 Header track (`83:1680`)

| Property | Value |
| --- | --- |
| Size | 214 × 14 @ 108.5, 0 (local) / **123.5, 16** (widget) |
| Layout mode | `HORIZONTAL` |
| **Item spacing** | **1.5** |
| Padding | 0 |
| Primary / counter sizing | `FIXED` / `FIXED` |

Content check: 7 cells × 28 + 6 gaps × 1.5 = 196 + 9 = **205**. The frame is
declared 214, so it overhangs its content by 9.

**Header column pitch = 28 + 1.5 = 29.5** — identical to the slot pitch
(17.5 + 12 = 29.5). This is the one number the two grids agree on.

### 6.4 Header cells (`83:1681`, `1683`, `1685`, `1687`, `1689`, `1691`, `1693`)

All seven are identical apart from the letter inside.

| Property | Value |
| --- | --- |
| Type | `FRAME` |
| Size | **28 × 14** |
| Corner radius | **7** (a 28 × 14 capsule — never visible, the fill is transparent) |
| Fill | `#8D8D93` @ **0% opacity** — i.e. invisible |
| Stroke | none |
| Effects | none |
| Clips | false |
| Name | `filled` (copied from the slot component; misleading here) |

The cell is **wider than a slot (28 vs 17.5) and its gap is nearly nothing
(1.5 vs 12)** because a letter needs the width and a slot does not. The pitch
comes out the same either way.

### 6.5 Header letters

All: SF Pro Regular, **12 pt**, line height `AUTO`, letter spacing 0%, text
align `LEFT`/`TOP`, auto-resize `WIDTH_AND_HEIGHT`, constraints `CENTER`/`CENTER`,
height 14, **y = 2.5** inside the 14-tall cell.

| Node | Char | x | w | Fill | Effect |
| --- | --- | --- | --- | --- | --- |
| `83:1682` | `M` | 9 | 11 | `#8D8D93` @ 100% | none |
| `83:1684` | `T` | 10 | 8 | **`#FFFFFF` @ 100%** | **drop shadow, r 2, `#FFFFFF` α 1, offset (0, 0), spread 0** |
| `83:1686` | `W` | 8.5 | 12 | `#8D8D93` @ 100% | none |
| `83:1688` | `T` | 10 | 8 | `#8D8D93` @ 100% | none |
| `83:1690` | `F` | 10.5 | 7 | `#8D8D93` @ 100% | none |
| `83:1692` | `S` | 10 | 8 | `#8D8D93` @ 100% | none |
| `83:1694` | `S` | 10 | 8 | `#8D8D93` @ 100% | none |

**Today is Tuesday** — column 2 is the only white, glowing letter. Its weight is
still `Regular` (400). Nothing in this frame is bold anywhere.

Optical centring inside each 28-wide cell (half = 14):

| Char | Glyph centre | Offset from cell centre |
| --- | --- | --- |
| M | 9 + 5.5 = 14.5 | **+0.5** |
| T | 10 + 4 = 14 | 0 |
| W | 8.5 + 6 = 14.5 | **+0.5** |
| T | 14 | 0 |
| F | 10.5 + 3.5 = 14 | 0 |
| S | 14 | 0 |
| S | 14 | 0 |

The two wide glyphs (M, W) sit half a point right of centre; the rest are exact.

**Vertical overflow:** a 14-tall glyph box placed at y = 2.5 in a 14-tall cell
extends to y = 16.5 — 2.5 past the cell and 2.5 past the header frame. Since
nothing between here and `content` clips, it renders fine. In widget
coordinates the letters occupy **y 18.5 → 32.5**, leaving a 10.5 pt gap to the
first row of slots at y 43.

---

## 7. The habit rows

### 7.1 The label column

`label` frame — `83:1697`, `1710`, `1726`, `1742`, `1749`, `1764`, `1778`, `1787`.

| Property | Value |
| --- | --- |
| Size | **98 × 17.5** |
| Position | 0, 0 (local) / x 15 (widget) |
| Layout mode | **none** — children are absolutely positioned |
| Fill | none |
| Stroke | none |
| Effects | none |
| Clips content | **true** — except `83:1787` (row 8), which is **false** |

Two absolutely-positioned `TEXT` children.

#### The icon glyph

An **SF Symbol rendered as a text glyph in SF Pro**, not a vector and not an
image. Common properties for all eight:

| Property | Value |
| --- | --- |
| Font | SF Pro **Regular** |
| **Font size** | **14** (the names beside them are 12) |
| Height | **17** |
| Line height | `AUTO` |
| Letter spacing | 0% |
| Text align horizontal | **`CENTER`** |
| Auto-resize | `WIDTH_AND_HEIGHT` |

Per-row geometry and paint:

| Row | Node | Glyph | SF Symbol | x | w | y | Optical centre | Fill | Glow |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `83:1698` | `􀐳` | `figure.run` | **4** | 15 | **1.5** | 11.5 | `#FFFFFF` | r 1.5 |
| 2 | `83:1711` | `􁕑` | `figure.flexibility` | 3 | 19 | 0.625 | 12.5 | `#8D8D93` | — |
| 3 | `83:1727` | `􀉚` | `book` | 0.5 | 19 | 0.625 | 10 | `#8D8D93` | — |
| 4 | `83:1743` | `􀙩` | `bed.double` | **−0.5** | 21 | 0.625 | 10 | `#FFFFFF` | r 1.5 |
| 5 | `83:1750` | `􀠑` | `drop` | 4.5 | 12 | 0.625 | 10.5 | `#FFFFFF` | r 1.5 |
| 6 | `83:1765` | `􀥲` | `leaf` | 1.5 | 17 | 0.625 | 10 | `#8D8D93` | — |
| 7 | `83:1779` | `􀥲` | `leaf` | 1.5 | 17 | 0.625 | 10 | `#8D8D93` | — |
| 8 | `83:1788` | `􀆱` | `sunrise` | **−0.5** | 22 | 0.625 | 10.5 | `#8D8D93` | — |

Glow, where present, is exactly: **`DROP_SHADOW`, radius 1.5, `#FFFFFF`
α 1.0, offset (0, 0), spread 0, blend `NORMAL`, `showShadowBehindNode` false.**

Two glyphs (`bed.double`, `sunrise`) are placed at **x = −0.5**, half a point
outside the label frame. Row 8's label does not clip, so its sunrise glyph
survives; rows 1–7 clip, so any left overhang would be cut.

The optical centres cluster at **x ≈ 10–10.5**, with `figure.run` (11.5) and
`figure.flexibility` (12.5) as outliers. The icon column is effectively **0 →
24** with the name starting at 28.5, i.e. a 4.5 pt gap — matching
`WidgetMetrics.iconWidth = 24` + `iconGap = 4.5` = 28.5.

#### The habit name

| Property | Value |
| --- | --- |
| Font | SF Pro **Regular** (weight 400) |
| Font size | **12** |
| **x** | **28.5** — identical in all eight rows |
| **y** | **0.625** — identical in all eight rows |
| Height | **14** |
| Line height | `AUTO` |
| Letter spacing | 0% |
| Align | `LEFT` / `TOP` |
| Auto-resize | `WIDTH_AND_HEIGHT` |

| Row | Node | Characters | Width | Right edge | Fill | Glow |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `83:1699` | `Workout` | 48 | 76.5 | `#FFFFFF` @ 100% | r 1.5 `#FFFFFF` α 1 |
| 2 | `83:1712` | `Stretch` | 42 | 70.5 | `#8D8D93` @ 100% | — |
| 3 | `83:1728` | `Study` | 33 | 61.5 | `#8D8D93` @ 100% | — |
| 4 | `83:1744` | `Early night` | 60 | 88.5 | `#FFFFFF` @ 100% | r 1.5 `#FFFFFF` α 1 |
| 5 | `83:1751` | `Hydration` | 56 | 85 | `#FFFFFF` @ 100% | r 1.5 `#FFFFFF` α 1 |
| 6 | `83:1766` | `Touch Grass` | 71 | **99.5** | `#8D8D93` @ 100% | — |
| 7 | `83:1780` | `Touch Grass` | 71 | **99.5** | `#8D8D93` @ 100% | — |
| 8 | `83:1789` | `Watch Sunset` | 79 | **107.5** | `#8D8D93` @ 100% | — |

Rows 6 and 7 overflow the 98 pt label frame by **1.5 pt** and are clipped. Row 8
overflows by **9.5 pt** and is **not** clipped, because that one label frame has
`clipsContent = false`. See §9.2.

**Vertical placement:** a 14-tall name box at y = 0.625 in a 17.5-tall label
occupies 0.625 → 14.625. True vertical centring would put it at y = 1.75, so
**every habit name sits 1.125 pt above the row's centreline**, and therefore
above the centre of the slots beside it.

### 7.2 The track column

`track` frame — `83:1700`, `1713`, `1729`, `1745`, `1752`, `1767`, `1781`, `1790`.

| Property | Value |
| --- | --- |
| Size | **200 × 17.5** |
| Position | 113, 0 (local) / **x 128** (widget) |
| Layout mode | `HORIZONTAL` |
| **Item spacing** | **12** |
| Padding | 0 |
| Primary / counter sizing | `FIXED` / `AUTO` |
| Counter align | `MIN` (top) |
| Clips | false |

**Column pitch = 17.5 + 12 = 29.5.**

Slot positions — these seven numbers are identical in every row that uses
single-day slots:

| Col | Day | Local x | **Widget x** | Widget right | **Widget centre** |
| --- | --- | --- | --- | --- | --- |
| 1 | Mon | 0 | **128** | 145.5 | **136.75** |
| 2 | Tue | 29.5 | **157.5** | 175 | **166.25** |
| 3 | Wed | 59 | **187** | 204.5 | **195.75** |
| 4 | Thu | 88.5 | **216.5** | 234 | **225.25** |
| 5 | Fri | 118 | **246** | 263.5 | **254.75** |
| 6 | Sat | 147.5 | **275.5** | 293 | **284.25** |
| 7 | Sun | 177 | **305** | 322.5 | **313.75** |

The last slot's right edge is **322.5**, half a point past the 322 content edge
and 15.5 pt in from the widget's right side.

---

## 8. Slot state catalogue

Seven distinct visual states appear in this frame. Every one is 17.5 tall.
Every single-day one is 17.5 wide with a **corner radius of 8.75** — exactly
half the side, so a perfect circle.

### 8.1 Upcoming (`inactive`)

Nodes: `83:1704–1708`, `1720–1724`, `1736–1740`, `1758–1762`, `1772–1776`.

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75 |
| Fill | **`#8D8D93` @ 16%** → composites to ≈ rgb(23, 23, 24) on black |
| Stroke | none |
| Effects | **none** |
| Children | none |

The quietest thing in the widget and the most numerous. 26 of them.

### 8.2 Completed (dot)

Nodes: `83:1701`+`1702`, `1718`+`1719`, `1734`+`1735`, `1768`+`1769`, `1770`+`1771`.

**Outer frame** (`filled`):

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75 |
| Fill | `#8D8D93` @ **0%** — an invisible placeholder that reserves the slot |
| Effects | none |

**Inner mark** (`Rectangle 3`, a `RECTANGLE`):

| Property | Value |
| --- | --- |
| Size | **7 × 7** |
| Position | **5.5, 5.5** |
| Corner radius | **3.5** — exactly half, so a circle |
| Fill | **`#FFFFFF` @ 100%** |
| Effect | **`DROP_SHADOW`, radius 9, `#FFFFFF` α 1.0, offset (0, 0), spread 0** |

Dot : slot = 7 / 17.5 = **0.4**. Halo radius : slot = 9 / 17.5 = **0.514**.

### 8.3 Today / due (open ring)

Nodes: `83:1703`, `1757`. A single frame, no children.

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75 |
| **Fill** | **`#FFFFFF` @ 1%** — not zero; a 1% wash inside the ring |
| **Stroke** | **`#FFFFFF` @ 100%**, weight **1.5**, align **`INSIDE`** |
| Clips | false |

Four effects, in this order:

| # | Type | Radius | Colour | Alpha | Offset | Spread |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `DROP_SHADOW` | 5 | `#FFFFFF` | **0.5** | (0, **−1.25**) | 0 |
| 2 | `DROP_SHADOW` | 5 | `#FFFFFF` | **0.5** | (0, **+1.25**) | 0 |
| 3 | `INNER_SHADOW` | 2.5 | `#FFFFFF` | **1.0** | (0, **−1.25**) | 0 |
| 4 | `INNER_SHADOW` | 2.5 | `#FFFFFF` | **1.0** | (0, **+1.25**) | 0 |

A symmetric vertical pair outside and a symmetric vertical pair inside. The
outer pair is the visible halo; the inner pair thickens the stroke's apparent
brightness at the top and bottom of the ring. Ring stroke : slot = 1.5 / 17.5 =
**0.086**.

### 8.4 Missed (✕)

Nodes: `83:1714`+`1715`, `1730`+`1731`, `1753`+`1754`.

**Outer frame** (`filled`):

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5, radius 8.75 |
| Fill | `#8D8D93` @ 100% but **`visible: false`** — the paint exists and is switched off |
| Effects | none |

**The mark** (`Union`, a `BOOLEAN_OPERATION`):

| Property | Value |
| --- | --- |
| Size | **7.0713 × 7.0713** |
| Position | **5.5, 5.5** |
| **Node opacity** | **0.5** |
| Fill | `#8D8D93` @ 100% (× the 0.5 node opacity → **effective `#8D8D93` @ 50%**) |
| Effects | **none** — the miss is the only mark that does not glow |

It is built from two `RECTANGLE` children, each **1 × 9**, rotated to ±45°:

| Node | Size | Position |
| --- | --- | --- |
| `Rectangle 1` | 1 × 9 | 5.5, 6.207 |
| `Rectangle 2` | 1 × 9 | 11.864, 5.5 |

A 1 × 9 bar at 45° has a bounding box of (9 + 1)/√2 = **7.0711**, which is where
the 7.0713 comes from. So the ✕ is **1 pt thick with 9 pt arms**, not a 7 × 7
glyph — the 7.07 is a consequence, not an authored size.

Composited on black: `#8D8D93` at 50% ≈ rgb(70, 70, 74).

### 8.5 Multi-day open ring (span)

Node `83:1746`, row 4 ("Early night").

Identical to §8.3 in **every** property — fill `#FFFFFF` @ 1%, stroke `#FFFFFF`
1.5 `INSIDE`, the same four effects, corner radius 8.75 — except:

| Property | Value |
| --- | --- |
| **Width** | **76.5** |
| Height | 17.5 |
| Position | local 0, 0 |

76.5 = 3 slots (3 × 17.5 = 52.5) + 2 gaps (2 × 12 = 24). It covers **Mon–Wed
exactly**, edge to edge. With radius 8.75 on a 17.5-tall shape it renders as a
capsule.

### 8.6 Multi-day upcoming (span)

| Node | Row | Size | Local x | Covers | Fill |
| --- | --- | --- | --- | --- | --- |
| `83:1747` | 4 | **106.5** × 17.5 | 88.5 | Thu–Sun | `#8D8D93` @ 16% |
| `83:1785` | 7 | **136.5** × 17.5 | 59 | Wed–Sun | `#8D8D93` @ 16% |

Corner radius 8.75, no stroke, no effects — same paint as §8.1, just longer.

Arithmetic: 4 columns = 4 × 17.5 + 3 × 12 = **106.5** ✓ exactly.
5 columns = 5 × 17.5 + 4 × 12 = **135.5**, but `83:1785` is **136.5** — one
point long. Its right edge lands at 195.5 rather than 194.5.

The gap between row 4's two spans is 88.5 − 76.5 = **12**, one clean slot gap.

### 8.7 Completed span (bar)

Rows 7 and 8. In both, the bar lives inside a normal 17.5 × 17.5 `filled` frame
(fill `#8D8D93` @ 0%, radius 8.75) and **overflows it** — the track does not
clip, so it draws freely across the columns to its right.

| | Row 7 (`83:1783`) | Row 8 (`83:1792`) |
| --- | --- | --- |
| Type | `RECTANGLE` | `RECTANGLE` |
| Size | **36.5 × 4** | **189 × 4** |
| Position in slot | **5.5, 7** | **5.5, 7** |
| Corner radius | **4.5** | **3.5** |
| Fill | `#FFFFFF` @ 100% | `#FFFFFF` @ 100% |
| Effect | `DROP_SHADOW` r **9**, `#FFFFFF` α 1, offset (0, 0), spread 0 | identical |
| Local extent | 5.5 → 42 | 5.5 → 194.5 |
| Widget extent | x 133.5 → 170 | x 133.5 → 322.5 |

Bar thickness : slot = 4 / 17.5 = **0.229**.

Both corner radii exceed half the 4 pt height, so **both render as identical
2 pt capsules** — the 4.5 vs 3.5 difference is authoring noise with no visual
consequence.

Row 8's bar runs from the Monday dot's left edge (5.5) to the Sunday slot's
right edge (194.5) — the full week, 189 pt, exactly.

### 8.8 Invisible placeholder

Node `83:1784`, row 7 column 2.

| Property | Value |
| --- | --- |
| Name | `inactive` |
| Size | 17.5 × 17.5, radius 8.75 |
| Fill | `#8D8D93` @ 16% but **`visible: false`** |
| Effects | none |

Renders nothing. It exists purely to hold column 2's place in the auto-layout so
that the 136.5 span after it starts at x 59. Row 7 therefore has three track
children where only two are visible.

### 8.9 Mark centring — a consistent 0.25 pt bias

Every inner mark is inset **5.5** from its slot's top-left:

| Mark | Size | True centred inset | Authored inset | Bias |
| --- | --- | --- | --- | --- |
| Dot | 7 × 7 | 5.25 | **5.5** | +0.25 x, +0.25 y |
| ✕ Union | 7.0713 | 5.2144 | **5.5** | +0.286 |
| Bar | h 4 | y 6.75 | **y 7** | +0.25 y |

So **every mark in the widget sits a quarter point down and right of its slot's
true centre.** It is uniform, so it reads as correct; it is the author rounding
5.25 up to 5.5.

---

## 9. Where the file does not line up with itself

These are real, measurable inconsistencies in node `83:1676`. They are listed
because an implementation has to choose one number or the other.

### 9.1 The header grid is 0.75 pt right of the slot grid

Two independent chains produce the same column boundary and disagree:

- **Header:** left padding 15 + item spacing 108.5 = **123.5**, then cells of 28
  with 1.5 gaps. Cell centres: 137.5, 167, 196.5, 226, 255.5, 285, 314.5.
- **Rows:** left padding 15 + label 98 + gap 15 = **128**, then slots of 17.5
  with 12 gaps. Slot centres: 136.75, 166.25, 195.75, 225.25, 254.75, 284.25,
  313.75.

**Every weekday letter is 0.75 pt to the right of the column it labels.** The
pitch (29.5) matches, so the error is a constant offset, not drift. To make them
agree, either the header's item spacing becomes 113 (letters move left 4.5,
giving centres at 132.25 …) or, keeping the letters where they are, the header
gap becomes 104. Neither is what the file says.

### 9.2 One label clips and seven do not

`83:1787` (row 8, "Watch Sunset") has `clipsContent = false`; the other seven
labels have `true`. That row's name is 107.5 wide against a 98 pt frame, so the
setting is load-bearing — it is the only reason "Watch Sunset" is legible.
Rows 6 and 7 ("Touch Grass", 99.5 wide) *do* clip, losing 1.5 pt off the final
`s`.

Either the label column is 98 and long names truncate, or it is ~108 and they
do not. The file does both.

### 9.3 Two spans overshoot by half a point and a point

- `83:1785` (row 7 upcoming span) is 136.5 where 5 columns measure 135.5.
- `83:1783` (row 7 bar) is 36.5, ending at 42, where the second dot's right edge
  is 41.5.
- Row 4's spans are exact.
- Row 8's bar is exact.

### 9.4 Two bar radii for one appearance

4.5 (row 7) vs 3.5 (row 8) on a 4 pt-tall bar. Both clamp to 2.

### 9.5 Icons and names are not on the row centreline

The row frame counter-aligns `CENTER`, but the label's children are absolutely
positioned inside it, so the alignment does nothing for them. Names sit 1.125 pt
high; icons sit 0.375 pt low; row 1's icon is a further 0.875 lower than the
other seven (y 1.5 vs 0.625) and, at height 17 from y 1.5, extends 1 pt past the
clipping label frame.

---

## 10. Consolidated colour table

There are **two colours** in this frame and nothing else. No hue anywhere. No
accent. Everything is white, or grey at some strength, or the near-black
gradient.

| Value | Where it is used | Nodes |
| --- | --- | --- |
| **`#FFFFFF` @ 100%** | completion dot fill; completion bar fill; open-ring stroke; lit habit name; lit habit icon; today's weekday letter; every glow colour | 20 |
| **`#FFFFFF` @ 1%** | interior wash of the open ring (single and span) | 3 |
| **`#8D8D93` @ 100%** | resting habit name; resting habit icon; **all six non-today weekday letters**; the vestigial spacer text | 17 |
| **`#8D8D93` @ 50%** | the missed ✕ (as node opacity 0.5 on the `Union`) | 3 |
| **`#8D8D93` @ 16%** | every upcoming slot and upcoming span | 28 |
| **`#8D8D93` @ 0%** | invisible placeholder frames that reserve a slot's position | 12 |
| **`#8D8D93`, `visible: false`** | the missed slot's frame, and row 7's hidden column-2 slot | 4 |
| **`#464649` → `#000000`** @ effective 3% | the root's vertical gradient | 1 |

`#8D8D93` is rgb(141, 141, 147) = rgb(0.5529, 0.5529, 0.5765). Composited on
pure black:

| Strength | Composite |
| --- | --- |
| 100% | rgb(141, 141, 147) |
| 50% | rgb(70, 70, 74) |
| 16% | rgb(23, 23, 24) |

> **Note against `docs/design-system.md`:** that document lists `headerRest` as
> `#8D8D93` @ **60%**. In this node the six resting weekday letters are `#8D8D93`
> at **100%** — the same value as a resting habit name. There is no 60% paint
> anywhere in the subtree.

---

## 11. Consolidated type table

**One family, one weight, two sizes.** SF Pro Regular (weight 400) on every
single text node. No bold anywhere — including the habit names that are due and
today's weekday letter, which are distinguished by white plus a glow instead.

| Element | Family | Style | Size | Height | Line height | Tracking | Align | Auto-resize |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Habit name | SF Pro | Regular | **12** | 14 | `AUTO` | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| Weekday letter | SF Pro | Regular | **12** | 14 | `AUTO` | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| Spacer (vestigial) | SF Pro | Regular | 12 | 14 | `AUTO` | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| **Habit icon glyph** | SF Pro | Regular | **14** | 17 | `AUTO` | 0% | **`CENTER`**/`TOP` | `WIDTH_AND_HEIGHT` |

`textCase` is `ORIGINAL` and `textDecoration` is `NONE` on every node.

The icons being 14 while the names beside them are 12 is the only type-size
distinction in the frame.

---

## 12. Consolidated effect table

Every glow in the widget is `#FFFFFF`. There are exactly **five** distinct
effect recipes plus the container's glass.

| Recipe | Type(s) | Radius | Alpha | Offset | Applied to | Count |
| --- | --- | --- | --- | --- | --- | --- |
| **Mark glow** | `DROP_SHADOW` | **9** | 1.0 | (0, 0) | completion dots, completion bars | 7 |
| **Ring glow** | `DROP_SHADOW` ×2 | **5** | **0.5** | (0, −1.25) and (0, +1.25) | open rings and open-ring spans | 3 |
| **Ring inner** | `INNER_SHADOW` ×2 | **2.5** | 1.0 | (0, −1.25) and (0, +1.25) | open rings and open-ring spans | 3 |
| **Label glow** | `DROP_SHADOW` | **1.5** | 1.0 | (0, 0) | lit habit names and lit habit icons | 6 |
| **Today glow** | `DROP_SHADOW` | **2** | 1.0 | (0, 0) | today's weekday letter only | 1 |
| **Glass** | `GLASS` | 4 | — | — | the root frame | 1 |

Every one is `blendMode: NORMAL`, `spread: 0`, `showShadowBehindNode: false`.

Nothing carrying `#8D8D93` has an effect. **A miss does not glow, an upcoming
day does not glow, and a resting label does not glow.** Light is the only signal
of state in this design; the greys are its absence.

Ratios to the 17.5 slot, if you need to scale the grid:

| Glow | Radius / slot |
| --- | --- |
| Mark | 9 / 17.5 = **0.514** |
| Ring outer | 5 / 17.5 = **0.286** |
| Ring inner | 2.5 / 17.5 = **0.143** |
| Ring y-offset | 1.25 / 17.5 = **0.0714** |

Figma's shadow radius is roughly **half** a CSS blur, and roughly equal to a
SwiftUI `.shadow(radius:)`. The generated CSS in `get_design_context` doubles
every number above (`0 0 18px`, `0 ±2.5px 10px`, etc.) — those are CSS px, not
points.

---

## 13. What the frame actually depicts

Today is **Tuesday**. Seven columns, Monday-first.

| # | Habit | SF Symbol | Label state | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Workout | `figure.run` | **lit** | ● dot | ○ **ring** | ·  | ·  | ·  | ·  | ·  |
| 2 | Stretch | `figure.flexibility` | resting | ✕ | ● dot | ·  | ·  | ·  | ·  | ·  |
| 3 | Study | `book` | resting | ✕ | ● dot | ·  | ·  | ·  | ·  | ·  |
| 4 | Early night | `bed.double` | **lit** | ⟨— open ring span, Mon–Wed —⟩ | | | ⟨— upcoming span, Thu–Sun —⟩ | | | |
| 5 | Hydration | `drop` | **lit** | ✕ | ○ **ring** | ·  | ·  | ·  | ·  | ·  |
| 6 | Touch Grass | `leaf` | resting | ● dot | ● dot | ·  | ·  | ·  | ·  | ·  |
| 7 | Touch Grass | `leaf` | resting | ▬ bar, Mon–Tue | | *(hidden)* | ⟨— upcoming span, Wed–Sun —⟩ | | | |
| 8 | Watch Sunset | `sunrise` | resting | ▬▬▬ bar, full week Mon–Sun | | | | | | |

Legend — `●` completed dot · `○` open ring (today / due) · `✕` missed ·
`·` upcoming · `▬` completed bar

The three lit labels (Workout, Early night, Hydration) are exactly the three
rows whose Tuesday cell is **not** already satisfied: Workout and Hydration show
an open ring, Early night is mid-span. Rows 2, 3, 6, 7 and 8 have Tuesday
handled and their labels rest at grey. So **the label's brightness reports "this
one still wants you today"**, and the row's marks report history.

Two rows are both named "Touch Grass" — rows 6 and 7 are the same habit shown at
two different frequencies (daily-slots vs a spanning bar), sitting side by side
as a comparison, not two real habits.

---

## 14. Reproducing it — the derivation order

Everything in the grid falls out of the slot. If you scale, scale from there.

```
slot          = 17.5
gap           = 12                    = 0.686 × slot
pitch         = slot + gap = 29.5
rowGap        = 10
rowPitch      = slot + rowGap = 27.5

dot           = 7      = 0.400 × slot,  inset 5.5, radius 3.5
bar thickness = 4      = 0.229 × slot,  y 7, radius ≥ 2
ring stroke   = 1.5    = 0.086 × slot,  INSIDE
missed arm    = 9 long × 1 thick at ±45°, inset 5.5, opacity 0.5

span(n)       = n × slot + (n − 1) × gap
              = 17.5, 47, 76.5, 106, 135.5, 165, 194.5   for n = 1…7

label         = 98
labelGap      = 15
iconColumn    = 24        (name starts at 28.5, so the gap is 4.5)
track         = 200       (declared; content ends at 194.5)

padLeading    = 15
padTrailing   = 16        (asymmetric — do not average)
padVertical   = 16
headerGap     = 13
headerHeight  = 14
headerCell    = 28 × 14,  headerCellGap = 1.5   (same 29.5 pitch)

text          = 12        SF Pro Regular
icon          = 14        SF Pro Regular
corner        = 30
```

### Deltas against the current implementation

`GlowWidget/WidgetMetrics.swift` matches the file on every layout number —
15/16/16 padding, 13 header gap, 10 row gap, 98 label, 15 label gap, 24 + 4.5
icon column, 12 text, 14 header height. Two values differ:

| | File (`83:1676`) | `WidgetMetrics.swift` |
| --- | --- | --- |
| Gradient top | `rgb(70, 70, 73)` @ **0.03** | `rgb(70, 70, 73)` @ **0.05** |
| Gradient bottom | `rgb(0, 0, 0)` @ **0.03** | `rgb(10, 10, 15)` @ **0.15** |

The file's 0.03 is the product of a 0.15 stop alpha and a 0.20 paint opacity —
easy to miss if you read only the stop, and easy to over-read if you take
Figma's swatch at face value. Neither of the code's numbers appears anywhere in
the node.

Also absent from `WidgetMetrics`: the 30 pt corner radius, the `GLASS` effect,
and the 14 pt icon size.

---

## 15. Node index

| Node | Name | What it is |
| --- | --- | --- |
| `83:1676` | Widget — Large | root, 338 × 354, r30, gradient, glass |
| `83:1677` | content | padding + clip, vertical stack |
| `83:1678` | Frame 3 | header row |
| `83:1679` | Text | zero-width spacer |
| `83:1680` | track | header track, 7 × 28 cells @ 1.5 |
| `83:1681`–`1694` | filled / M T W T F S S | header cells and letters |
| `83:1695` | Frame 1 | row stack, 8 rows @ 10 |
| `83:1696`–`1708` | Early night | row 1 — Workout |
| `83:1709`–`1724` | Early night | row 2 — Stretch |
| `83:1725`–`1740` | Early night | row 3 — Study |
| `83:1741`–`1747` | Early night | row 4 — Early night (spans) |
| `83:1748`–`1762` | Early night | row 5 — Hydration |
| `83:1763`–`1776` | Early night | row 6 — Touch Grass |
| `83:1777`–`1785` | Early night | row 7 — Touch Grass (bar) |
| `83:1786`–`1792` | Early night | row 8 — Watch Sunset (full bar) |
