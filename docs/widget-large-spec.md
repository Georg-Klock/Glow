# Widget — Large (Figma `83:1676`)

A complete measurement of the large widget frame in `Glow-Up`
(file `0m9qFcvvUrIgLmqIxE0jtj`, page **05 Widgets**, node **`83:1676`**).

Every number here is read off the node's own properties through the Figma Plugin
API — not measured off a render, not inferred from the generated CSS, not
rounded to something tidier. Where the file sits on a half point, so does this
document. §16 lists every property class that was checked and found **absent**,
so the negative space is documented too.

**Read this first:**

- The frame is authored at **1×**. It is 338 × 354, the point size of a large
  widget on a 6.1″ iPhone, so **every number below is already in points**. (This
  differs from `docs/design-system.md`, whose "File" column is 2× — that column
  describes a different frame.)
- The subtree is **117 nodes**: 77 `FRAME`, 24 `TEXT`, 13 `RECTANGLE`,
  3 `BOOLEAN_OPERATION`.
- There are **no components, no instances, no shared styles and no variables**
  anywhere in it. A sweep of `fillStyleId` / `strokeStyleId` / `effectStyleId` /
  `textStyleId` / `boundVariables` across all 117 nodes returns **zero** hits;
  `get_variable_defs` returns `{}`. Every value is a literal. **Nothing in this
  file is tokenised.**
- Coordinates are given two ways. **Local** = the node's `x`/`y` inside its
  parent (what Figma's inspector shows). **Widget** = resolved against the root
  frame's top-left. Where only one is given, it is local.
- **Bounding box vs render bounds.** A node's box is its geometry; its *render
  bounds* is the pixels it actually paints, including glow spill and excluding
  the empty side-bearings of text. Both are given wherever they differ — that is
  §13, and it is where the glows are really measured.

---

## 1. At a glance

| | |
| --- | --- |
| Node | `83:1676` — `Widget — Large` |
| Type | `FRAME` |
| Size | **338 × 354** pt |
| Canvas position | x `4636`, y `2272` |
| Rotation | `0` |
| Corner radius | **30** pt, uniform on all four corners |
| **Corner smoothing** | **`0`** — a plain circular arc, **not** an iOS squircle |
| Clips content | **false** |
| Strokes | none |
| Export settings | none |
| Prototype reactions | none |
| Locked | no |
| Mask | no |
| Blend mode | `PASS_THROUGH` |
| Parent | page `05 Widgets` |
| Page background | `#191919` — rgb(24.64, 24.64, 24.64) |
| **Render bounds** | **338 × 354 — identical to the box.** Nothing escapes the frame. |

Aspect ratio 338 : 354 = 0.955. Slightly taller than wide.

**Corner smoothing is 0 on all 93 corner-bearing nodes in the subtree.** Figma
offers iOS-style continuous corners via `cornerSmoothing` (0.6 is the "iOS"
preset) and the file uses none of it. Every rounded corner here — the 30 pt
container, the 8.75 pt slots, the 3.5 pt dot — is a true circular arc. On device
the system masks a widget to a continuous-corner squircle regardless, so the
container's 30 pt circular corner is a design-file approximation of a shape the
OS will override. The interior corners are not overridden and should be built as
plain circular radii.

---

## 2. Layer tree

Indentation is the real hierarchy. Sizes are `w × h`, positions local.

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
a leftover from the row that was duplicated to make the others. The real habit
identity is in the two `TEXT` children of its `label`.

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
| Visible | `true` |
| `gradientTransform` | `[[6.123e-17, 1, 0], [-1, 6.123e-17, 1]]` |

That transform is a 90° rotation, so the gradient runs **straight down**, top
edge to bottom edge, over the full 354 pt.

| Stop | Position | Colour | Stop alpha | **Effective alpha** (stop × paint) |
| --- | --- | --- | --- | --- |
| 0 | `0.0` | `#464649` — rgb(70, 70, 73) | `0.15` | **0.03** |
| 1 | `1.0` | `#000000` — rgb(0, 0, 0) | `0.15` | **0.03** |

Rendered:

```
top     rgba(70, 70, 73, 0.03)
bottom  rgba( 0,  0,  0, 0.03)
```

Both ends carry the same 3% alpha; only the hue changes, from a near-black warm
grey to true black. On a black wallpaper the whole thing amounts to lightening
the top edge by about 2 levels out of 255 — which is the point: it separates the
widget's corner from the wallpaper without reading as a panel.

Neither stop is bound to a variable (`boundVariables: {}` on both).

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
| Bound variables | none |

This is Figma's liquid-glass effect, not a background blur and not a shadow. It
has no direct SwiftUI equivalent; the nearest analogue is `.glassEffect(…)` /
`Material`, and neither reproduces the refraction, dispersion, or the −45°
directional light. In the flat PNG export it contributes the faint bright
hairline along the top-left corner arc.

### 3.3 Strokes

**None.** `strokes: []`. The widget has no border. The corner is defined entirely
by the 30 pt radius against the wallpaper.

### 3.4 `content` (`83:1677`)

A full-bleed child frame that carries the padding and does the clipping.

| Property | Value |
| --- | --- |
| Size | 338 × 354 (identical to the root) |
| Position | 0, 0 |
| Fill | none |
| Corner radius | 0 |
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
| Counter axis spacing | `0` (inert — only applies when wrapping) |
| Strokes included in layout | `false` |

**The padding is not symmetric: 15 left, 16 right.** Deliberate; do not average.
The last slot's right edge lands at x = 322.5 (§7.2), half a point past the 322
content edge — the extra point on the right is what keeps the last column off the
rounded corner.

Content box: **307 × 322**, spanning x 15 → 322, y 16 → 338.

Because `content` clips and the root does not, this frame is the only thing
bounding the glows. It is why the root's render bounds equal its box exactly:
**nothing spills outside the widget.** The nearest approach is row 8's bar glow,
which reaches x 331.5 — 6.5 pt clear of the 338 edge.

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
| Wrap | `NO_WRAP` |
| Counter axis spacing | `0` (inert) |
| Strokes included in layout | **`true`** — non-default, but the frame has no strokes, so inert |
| **Render bounds** | **316.5 × 218.75 @ 15, 36.75** (glow spill: T 6.25, R 3.5, B 2.5) |

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

Space available to the row stack is 322 − 14 − 13 = **295**.

`n × 17.5 + (n − 1) × 10 ≤ 295` → `n ≤ 11.09`, so the widget holds **11 rows** at
this pitch (11 rows measure 292.5). Eight are drawn. The **85 pt of empty space**
below the last row is unclaimed capacity, not a designed gutter — the row stack
hugs its content, so it simply stops.

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

The **track frame is declared 200 wide but its content ends at 194.5** (last slot
at local x 177 + 17.5). The frame therefore overhangs its own children by 5.5 and
the content box by 6. Nothing renders in that overhang. **Do not derive column
positions from the track's declared width — derive them from the pitch.**

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
| Counter axis spacing | `0` (inert) |
| Clips | false |

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
| **`layoutAlign`** | **`STRETCH`** — this is what makes it fill the content width |
| Align | `MIN` / `MIN` |
| Wrap | `NO_WRAP` |
| Counter axis spacing | `0` (inert) |
| Strokes included in layout | **`true`** — non-default, inert (no strokes) |
| Clips | false |
| **Render bounds** | **322.5 × 15.5 @ 15, 16** (spill: R 15.5, B 1.5) |

The 15.5 right spill is the header track frame's own empty overhang reaching
x 337.5; the 1.5 bottom spill is today's glowing "T".

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
| Render bounds | none (paints nothing) |

Figma measures the trailing spaces as **zero width**, so this node contributes
nothing to the layout. It is a vestigial placeholder standing in for the label
column. All of the header's leading offset comes from the parent's 108.5 gap.

**Consequence:** the header's horizontal registration is governed by `108.5`,
while the rows' is governed by `98 + 15 = 113`. Two independent numbers for the
same column boundary, and they disagree — §9.1.

### 6.3 Header track (`83:1680`)

| Property | Value |
| --- | --- |
| Size | 214 × 14 @ 108.5, 0 (local) / **123.5, 16** (widget) |
| Layout mode | `HORIZONTAL` |
| **Item spacing** | **1.5** |
| Padding | 0 |
| Primary / counter sizing | `FIXED` / `FIXED` |
| Counter axis spacing | `0` (inert) |
| Render bounds | 214 × 15.5 @ 123.5, 16 |

Content check: 7 cells × 28 + 6 gaps × 1.5 = 196 + 9 = **205**. The frame is
declared 214, so it overhangs its content by 9.

**Header column pitch = 28 + 1.5 = 29.5** — identical to the slot pitch
(17.5 + 12 = 29.5). This is the one number the two grids agree on.

### 6.4 Header cells (`83:1681`, `1683`, `1685`, `1687`, `1689`, `1691`, `1693`)

All seven identical apart from the letter inside.

| Property | Value |
| --- | --- |
| Type | `FRAME` |
| Size | **28 × 14** |
| Corner radius | **7**, uniform (a 28 × 14 capsule — never visible, the fill is transparent) |
| Corner smoothing | 0 |
| Fill | `#8D8D93` @ **0% opacity** — invisible |
| Stroke | none |
| Effects | none |
| Clips | false |
| Name | `filled` (copied from the slot; misleading here) |

The cell is **wider than a slot (28 vs 17.5) with almost no gap (1.5 vs 12)**
because a letter needs the width and a slot does not. The pitch comes out the
same either way.

### 6.5 Header letters

All: SF Pro Regular (weight 400), **12 pt**, line height `AUTO` (resolving to
**14**, ratio 1.167), letter spacing 0%, text align `LEFT`/`TOP`, auto-resize
`WIDTH_AND_HEIGHT`, constraints `CENTER`/`CENTER`, box height 14, **y = 2.5**
inside the 14-tall cell. Single uniform text run — no mixed segments anywhere.

| Node | Char | x | box w | Fill | Effect |
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

#### Measured ink, not boxes

The box is the em box; the ink is what paints. Widget coordinates:

| Char | Box (w × h) | **Ink (w × h)** | Ink x | Ink y | Ink centre x | Cell centre | Δ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M | 11 × 14 | **8.332 × 8.455** | 133.578 | 21.045 | 137.744 | 137.5 | +0.244 |
| T *(glowing)* | 8 × 14 | **10.504 × 12.455** | 161.551 | 19.045 | 166.803 | 167 | −0.197 |
| W | 12 × 14 | **10.559 × 8.455** | 191.527 | 21.045 | 196.807 | 196.5 | +0.307 |
| T | 8 × 14 | **6.504 × 8.455** | 222.551 | 21.045 | 225.803 | 226 | −0.197 |
| F | 7 × 14 | **5.133 × 8.455** | 253.078 | 21.045 | 255.645 | 255.5 | +0.145 |
| S | 8 × 14 | **6.299 × 8.854** | 281.674 | 20.846 | 284.824 | 285 | −0.176 |
| S | 8 × 14 | **6.299 × 8.854** | 311.174 | 20.846 | 314.324 | 314.5 | −0.176 |

Cap height for SF Pro Regular at 12 pt measures **8.455** (ratio 0.705). `S`
measures 8.854 — the standard round-letter overshoot, 0.4 pt above cap on both
sides. Every letter's ink top sits at y ≈ 21.045; the glowing T's ink box is
larger in every direction because it includes the 2 pt halo.

Ink is not centred on the cell, but it is close — within ±0.31. The
misregistration that matters is the frame-level one in §9.1.

**Vertical overflow:** a 14-tall glyph box at y = 2.5 in a 14-tall cell extends to
y = 16.5 — 2.5 past the cell and the header frame. Nothing between here and
`content` clips, so it renders. In widget coordinates the **ink** occupies
y 20.85 → 29.7 (or 19.05 → 31.5 including the glowing T's halo), leaving a
5.25 pt gap to the first row's topmost glow at y 36.75.

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
| Corner radius | 0 |
| Clips content | **true** — except `83:1787` (row 8), which is **false** |

Because there is no auto-layout inside the label, the row's `CENTER` counter-axis
alignment does nothing for its children. They sit exactly where their `y` says.

#### The icon glyph

An **SF Symbol rendered as a text glyph in SF Pro**, not a vector and not an
image. Common properties for all eight:

| Property | Value |
| --- | --- |
| Font | SF Pro **Regular** (weight 400) |
| **Font size** | **14** (the names beside them are 12) |
| Box height | **17** — `AUTO` line height, ratio 1.214 |
| Letter spacing | 0% |
| Text align horizontal | **`CENTER`** |
| Text align vertical | `TOP` |
| Auto-resize | `WIDTH_AND_HEIGHT` |
| Text case / decoration | `ORIGINAL` / `NONE` |

Per-row geometry and paint:

| Row | Node | Glyph | **Codepoint** | SF Symbol | x | box w | y | Optical centre | Fill | Glow |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `83:1698` | `􀐳` | **U+100433** | `figure.run` | **4** | 15 | **1.5** | 11.5 | `#FFFFFF` | r 1.5 |
| 2 | `83:1711` | `􁕑` | **U+101551** | `figure.flexibility` | 3 | 19 | 0.625 | 12.5 | `#8D8D93` | — |
| 3 | `83:1727` | `􀉚` | **U+10025A** | `book` | 0.5 | 19 | 0.625 | 10 | `#8D8D93` | — |
| 4 | `83:1743` | `􀙩` | **U+100669** | `bed.double` | **−0.5** | 21 | 0.625 | 10 | `#FFFFFF` | r 1.5 |
| 5 | `83:1750` | `􀠑` | **U+100811** | `drop` | 4.5 | 12 | 0.625 | 10.5 | `#FFFFFF` | r 1.5 |
| 6 | `83:1765` | `􀥲` | **U+100972** | `leaf` | 1.5 | 17 | 0.625 | 10 | `#8D8D93` | — |
| 7 | `83:1779` | `􀥲` | **U+100972** | `leaf` | 1.5 | 17 | 0.625 | 10 | `#8D8D93` | — |
| 8 | `83:1788` | `􀆱` | **U+1001B1** | `sunrise` | **−0.5** | 22 | 0.625 | 10.5 | `#8D8D93` | — |

Each glyph is a **single character** in SF Pro's Private Use Area — plane 16,
which is where Apple maps SF Symbols. The codepoints are the ground truth: the
SF Symbol names above are Figma's codegen resolving those codepoints, and the
file itself stores only the character.

Glow, where present, is exactly: **`DROP_SHADOW`, radius 1.5, `#FFFFFF` α 1.0,
offset (0, 0), spread 0, blend `NORMAL`, `showShadowBehindNode` false.**

Measured ink, widget coordinates:

| Row | Glyph | Box (w × h) | **Ink (w × h)** | Ink x | Ink y |
| --- | --- | --- | --- | --- | --- |
| 1 | `􀐳` | 15 × 17 | 14.519 × 16.976 | 19.258 | 43.524 |
| 2 | `􁕑` | 19 × 17 | 14.738 × 13.904 | 20.145 | 72.210 |
| 3 | `􀉚` | 19 × 17 | 15.183 × 12.694 | 17.405 | 100.339 |
| 4 | `􀙩` | 21 × 17 | 20.161 × 14.532 | 15.000 | 126.920 |
| 5 | `􀠑` | 12 × 17 | 12.475 × 16.843 | 19.263 | 153.265 |
| 6 / 7 | `􀥲` | 17 × 17 | 14.485 × 12.749 | 17.754 | 182.928 / 210.428 |
| 8 | `􀆱` | 22 × 17 | 17.521 × 14.267 | 16.736 | 237.053 |

Two glyphs (`bed.double`, `sunrise`) are placed at **x = −0.5**, half a point
outside the label frame — but their *ink* starts at x 15.0 and 16.736 widget,
i.e. at or inside the frame's left edge, so nothing is lost.

The optical box centres cluster at **x ≈ 10–10.5**, with `figure.run` (11.5) and
`figure.flexibility` (12.5) as outliers. The icon column is effectively **0 → 24**
with the name starting at 28.5, a 4.5 pt gap — matching
`WidgetMetrics.iconWidth = 24` + `iconGap = 4.5` = 28.5.

#### The habit name

| Property | Value |
| --- | --- |
| Font | SF Pro **Regular** (weight 400) |
| Font size | **12** |
| **x** | **28.5** — identical in all eight rows |
| **y** | **0.625** — identical in all eight rows |
| Box height | **14** — `AUTO` line height, ratio 1.167 |
| Letter spacing | 0% |
| Align | `LEFT` / `TOP` |
| Auto-resize | `WIDTH_AND_HEIGHT` |
| Truncation / max lines | `DISABLED` / none |
| Text case / decoration | `ORIGINAL` / `NONE` |

| Row | Node | Characters | Box w | Box right (widget) | **Ink right (widget)** | Fill | Glow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `83:1699` | `Workout` | 48 | 91.5 | 91.793 *(incl. halo)* | `#FFFFFF` @ 100% | r 1.5 |
| 2 | `83:1712` | `Stretch` | 42 | 85.5 | 83.924 | `#8D8D93` @ 100% | — |
| 3 | `83:1728` | `Study` | 33 | 76.5 | 76.008 | `#8D8D93` @ 100% | — |
| 4 | `83:1744` | `Early night` | 60 | 103.5 | 104.402 *(incl. halo)* | `#FFFFFF` @ 100% | r 1.5 |
| 5 | `83:1751` | `Hydration` | 56 | 99.5 | 99.275 *(incl. halo)* | `#FFFFFF` @ 100% | r 1.5 |
| 6 | `83:1766` | `Touch Grass` | 71 | **114.5** | **113.000** | `#8D8D93` @ 100% | — |
| 7 | `83:1780` | `Touch Grass` | 71 | **114.5** | **113.000** | `#8D8D93` @ 100% | — |
| 8 | `83:1789` | `Watch Sunset` | 79 | **122.5** | **121.172** | `#8D8D93` @ 100% | — |

The label frame's right edge is at widget x **113**.

- Rows 6 and 7 overflow the *box* by 1.5 pt, but their **ink ends at exactly
  113.000** — flush with the clip edge, to three decimals. **Nothing is lost.**
  The 1.5 pt overflow is the final `s`'s right side bearing, which is whitespace.
- Row 8's ink reaches **121.172**, i.e. **8.172 pt past the clip edge**. That row
  is the only one whose label does not clip, and it is the only one that needed
  not to. Its ink still stops 6.83 pt short of the track at x 128, so it does not
  collide with the grid.

**Vertical placement:** a 14-tall name box at y = 0.625 in a 17.5-tall label
occupies 0.625 → 14.625. True vertical centring would put it at y = 1.75, so
**every habit name's box sits 1.125 pt above the row's centreline.** Measured
ink for a resting name runs y ≈ 2.176 → 11.199 local (height 9.023), whose centre
is 6.69 against a row centre of 8.75 — the ink sits **2.06 pt high**.

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
| Wrap | `NO_WRAP` |
| Counter axis spacing | `0` (inert) |
| Clips | **false** — this is what lets the bars and glows overflow |

**Column pitch = 17.5 + 12 = 29.5.**

Slot positions — identical in every row that uses single-day slots:

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

Eight distinct states appear. Every one is 17.5 tall. Every single-day one is
17.5 wide with a **uniform corner radius of 8.75** — exactly half the side, so a
perfect circle — and **corner smoothing 0**.

Ten of these slot frames carry **`isAsset: true`** (`83:1701`, `1714`, `1718`,
`1730`, `1734`, `1753`, `1768`, `1770`, `1782`, `1791`) — Figma has flagged them
as single-purpose exportable graphics. This is why `get_design_context` exports
the ✕ slots as SVG rather than describing them as shapes.

### 8.1 Upcoming (`inactive`)

Nodes: `83:1704–1708`, `1720–1724`, `1736–1740`, `1758–1762`, `1772–1776` (25 of
them, plus 2 spans and 1 hidden — see below).

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75, uniform, smoothing 0 |
| Fill | **`#8D8D93` @ 16%** |
| Stroke | none |
| Effects | **none** |
| Children | none |
| Render bounds | equal to box — paints nothing outside itself |

The quietest thing in the widget and the most numerous.

### 8.2 Completed (dot)

Nodes: `83:1701`+`1702`, `1718`+`1719`, `1734`+`1735`, `1768`+`1769`, `1770`+`1771`.

**Outer frame** (`filled`):

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75 |
| Fill | `#8D8D93` @ **0%** — an invisible placeholder that reserves the slot |
| Effects | none |
| `isAsset` | true |

**Inner mark** (`Rectangle 3`, a `RECTANGLE`):

| Property | Value |
| --- | --- |
| Size | **7 × 7** |
| Position | **5.5, 5.5** |
| Corner radius | **3.5**, uniform, smoothing 0 — exactly half, so a circle |
| Rotation | 0 |
| Fill | **`#FFFFFF` @ 100%** |
| Effect | **`DROP_SHADOW`, radius 9, `#FFFFFF` α 1.0, offset (0, 0), spread 0** |
| **Render bounds** | **25 × 25** — 9 pt of spill on all four sides |

Dot : slot = 7 / 17.5 = **0.4**. Halo radius : slot = 9 / 17.5 = **0.514**.
The painted footprint (25 × 25) is 1.43× the slot and 0.85× the 29.5 pitch.

### 8.3 Today / due (open ring)

Nodes: `83:1703`, `1757`. A single frame, no children.

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5 |
| Corner radius | 8.75, uniform, smoothing 0 |
| **Fill** | **`#FFFFFF` @ 1%** — not zero; a 1% wash inside the ring |
| **Stroke** | **`#FFFFFF` @ 100%**, weight **1.5**, align **`INSIDE`** |
| Per-side stroke weight | 1.5 / 1.5 / 1.5 / 1.5 — uniform |
| Stroke cap / join / miter | `NONE` / `MITER` / 4 (all defaults) |
| Dash pattern | none |
| Clips | false |
| **Render bounds** | **27.5 × 30** — spill L 5, R 5, T 6.25, B 6.25 |

Four effects, in this order:

| # | Type | Radius | Colour | Alpha | Offset | Spread |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `DROP_SHADOW` | 5 | `#FFFFFF` | **0.5** | (0, **−1.25**) | 0 |
| 2 | `DROP_SHADOW` | 5 | `#FFFFFF` | **0.5** | (0, **+1.25**) | 0 |
| 3 | `INNER_SHADOW` | 2.5 | `#FFFFFF` | **1.0** | (0, **−1.25**) | 0 |
| 4 | `INNER_SHADOW` | 2.5 | `#FFFFFF` | **1.0** | (0, **+1.25**) | 0 |

A symmetric vertical pair outside and a symmetric vertical pair inside. The outer
pair is the visible halo; the inner pair thickens the stroke's apparent brightness
at the top and bottom. The vertical spill (6.25 = radius 5 + offset 1.25) exceeds
the horizontal (5) — the ring's glow is a slight vertical oval, not a circle.

Ring stroke : slot = 1.5 / 17.5 = **0.086**.

### 8.4 Missed (✕)

Nodes: `83:1714`+`1715`, `1730`+`1731`, `1753`+`1754`.

**Outer frame** (`filled`):

| Property | Value |
| --- | --- |
| Size | 17.5 × 17.5, radius 8.75 |
| Fill | `#8D8D93` @ 100% but **`visible: false`** — the paint exists and is switched off |
| Effects | none |
| `isAsset` | true |

**The mark** (`Union`):

| Property | Value |
| --- | --- |
| Type | `BOOLEAN_OPERATION` |
| **Operation** | **`UNION`** |
| Size | **7.0713 × 7.0713** |
| Position | **5.5, 5.5** |
| Rotation | 0 (the *children* are rotated) |
| **Node opacity** | **0.5** |
| Fill | `#8D8D93` @ 100% (× the 0.5 node opacity → **effective `#8D8D93` @ 50%**) |
| Effects | **none** — the miss is the only mark that does not glow |
| Render bounds | equal to box |

Built from two `RECTANGLE` children, **measured rotations**:

| Node | Size | Position | **Rotation** | Corner radius |
| --- | --- | --- | --- | --- |
| `Rectangle 1` | 1 × 9 | 5.5, 6.207 | **+45°** | 0 |
| `Rectangle 2` | 1 × 9 | 11.864, 5.5 | **−45°** | 0 |

A 1 × 9 bar at 45° has a bounding box of (9 + 1)/√2 = **7.0711**, which is where
the 7.0713 comes from. So the ✕ is **1 pt thick with 9 pt arms**, not a 7 × 7
glyph — the 7.07 is a consequence, not an authored size.

Composited on the page's `#191919`: `#8D8D93` at 50% ≈ rgb(83, 83, 86).
Composited on pure black: ≈ rgb(70, 70, 74).

### 8.5 Multi-day open ring (span)

Node `83:1746`, row 4 ("Early night").

Identical to §8.3 in **every** property — fill `#FFFFFF` @ 1%, stroke `#FFFFFF`
1.5 `INSIDE` uniform on all four sides, the same four effects, corner radius 8.75,
smoothing 0 — except:

| Property | Value |
| --- | --- |
| **Width** | **76.5** |
| Height | 17.5 |
| Position | local 0, 0 |
| **Render bounds** | **86.5 × 30** — spill L 5, R 5, T 6.25, B 6.25 |

76.5 = 3 slots (3 × 17.5 = 52.5) + 2 gaps (2 × 12 = 24). Covers **Mon–Wed
exactly**, edge to edge. With radius 8.75 on a 17.5-tall shape it renders as a
capsule.

### 8.6 Multi-day upcoming (span)

| Node | Row | Size | Local x | Covers | Fill |
| --- | --- | --- | --- | --- | --- |
| `83:1747` | 4 | **106.5** × 17.5 | 88.5 | Thu–Sun | `#8D8D93` @ 16% |
| `83:1785` | 7 | **136.5** × 17.5 | 59 | Wed–Sun | `#8D8D93` @ 16% |

Corner radius 8.75, no stroke, no effects — same paint as §8.1, just longer.

Arithmetic: 4 columns = 4 × 17.5 + 3 × 12 = **106.5** ✓ exactly.
5 columns = 5 × 17.5 + 4 × 12 = **135.5**, but `83:1785` is **136.5** — one point
long, right edge at 195.5 rather than 194.5.

The gap between row 4's two spans is 88.5 − 76.5 = **12**, one clean slot gap.

### 8.7 Completed span (bar)

Rows 7 and 8. In both, the bar lives inside a normal 17.5 × 17.5 `filled` frame
(fill `#8D8D93` @ 0%, radius 8.75, `isAsset: true`) and **overflows it** — the
track does not clip, so it draws freely across the columns to its right.

| | Row 7 (`83:1783`) | Row 8 (`83:1792`) |
| --- | --- | --- |
| Type | `RECTANGLE` | `RECTANGLE` |
| Size | **36.5 × 4** | **189 × 4** |
| Position in slot | **5.5, 7** | **5.5, 7** |
| Corner radius | **4.5**, uniform | **3.5**, uniform |
| Corner smoothing | 0 | 0 |
| Rotation | 0 | 0 |
| Fill | `#FFFFFF` @ 100% | `#FFFFFF` @ 100% |
| Effect | `DROP_SHADOW` r **9**, `#FFFFFF` α 1, offset (0, 0), spread 0 | identical |
| Box extent (widget) | x 133.5 → 170, y 215 → 219 | x 133.5 → 322.5, y 242.5 → 246.5 |
| **Render bounds** | **54.5 × 22 @ 124.5, 206** | **207 × 22 @ 124.5, 233.5** |

Bar thickness : slot = 4 / 17.5 = **0.229**.

Both corner radii exceed half the 4 pt height, so **both render as identical 2 pt
capsules** — the 4.5 vs 3.5 difference is authoring noise with no visual
consequence.

Row 8's bar runs from the Monday dot's left edge (5.5) to the Sunday slot's right
edge (194.5) — the full week, 189 pt, exactly. Its glow reaches x **331.5**,
which is the widest point anything paints in the whole widget: 6.5 pt clear of
the 338 edge.

### 8.8 Invisible placeholder

Node `83:1784`, row 7 column 2.

| Property | Value |
| --- | --- |
| Name | `inactive` |
| Size | 17.5 × 17.5, radius 8.75 |
| Fill | `#8D8D93` @ 16% but **`visible: false`** |
| Effects | none |

Renders nothing. It exists purely to hold column 2's place in the auto-layout so
that the 136.5 span after it starts at local x 59. Row 7 therefore has three
track children where only two are visible.

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

Real, measurable inconsistencies in node `83:1676`, listed because an
implementation has to pick one number or the other.

### 9.1 The header grid is 0.75 pt right of the slot grid

Two independent chains produce the same column boundary and disagree:

- **Header:** left padding 15 + item spacing 108.5 = **123.5**, then cells of 28
  with 1.5 gaps. Cell centres: 137.5, 167, 196.5, 226, 255.5, 285, 314.5.
- **Rows:** left padding 15 + label 98 + gap 15 = **128**, then slots of 17.5 with
  12 gaps. Slot centres: 136.75, 166.25, 195.75, 225.25, 254.75, 284.25, 313.75.

**Every weekday letter's cell is 0.75 pt right of the column it labels.** The
pitch (29.5) matches, so the error is a constant offset, not drift. Measured
against *ink* rather than boxes (§6.5) the per-letter offset ranges +0.55 to
+1.06, averaging ≈ 0.77 — corroborating the 0.75.

To reconcile, either the header's item spacing becomes 113 or the header cells
move left 4.5. Neither is what the file says.

### 9.2 One label clips and seven do not

`83:1787` (row 8, "Watch Sunset") has `clipsContent = false`; the other seven
labels have `true`.

Measured against ink rather than boxes:

| Row | Name | Ink right edge | Label edge | Verdict |
| --- | --- | --- | --- | --- |
| 6, 7 | Touch Grass | **113.000** | 113 | **flush — nothing lost even though it clips** |
| 8 | Watch Sunset | **121.172** | 113 | 8.172 pt would be cut — and this is the one row that doesn't clip |

So the setting on row 8 is load-bearing: it is the only reason "Watch Sunset" is
legible. Rows 6 and 7 land on the boundary to three decimals, which is either
very careful or very lucky. Either the label column is 98 and names longer than
"Touch Grass" truncate, or it is ~108 and they do not. The file does both, and
happens to get away with it.

### 9.3 Two spans overshoot

- `83:1785` (row 7 upcoming span) is 136.5 where 5 columns measure 135.5.
- `83:1783` (row 7 bar) is 36.5, ending at 42, where the second dot's right edge
  is 41.5.
- Row 4's spans are exact. Row 8's bar is exact.

### 9.4 Two bar radii for one appearance

4.5 (row 7) vs 3.5 (row 8) on a 4 pt-tall bar. Both clamp to 2.

### 9.5 Icons and names are not on the row centreline

The row frame counter-aligns `CENTER`, but the label has no auto-layout, so its
children are absolutely positioned and the alignment does nothing for them.

- Name boxes sit **1.125 pt** above centre; measured ink sits **2.06 pt** above.
- Icon boxes sit 0.375 pt below centre.
- Row 1's icon is a further 0.875 lower than the other seven (y 1.5 vs 0.625).
  Its box extends 1 pt past the clipping label frame — but its **ink stops at
  exactly y 60.5**, the label's bottom edge, so nothing is actually cut.

### 9.6 Two inert non-default layout flags

`strokesIncludedInLayout: true` on `83:1678` (header) and `83:1695` (row stack).
Neither frame has strokes, so both are no-ops. `counterAxisSpacing: 0` is set on
all 20 auto-layout frames and is likewise inert, since every one is `NO_WRAP`.

---

## 10. Consolidated colour table

Complete paint census across all 117 nodes: **89 paints total — 88 `SOLID` and
1 `GRADIENT_LINEAR`.** No image fills, no video fills, no pattern fills, no other
gradient types. **No node anywhere carries more than one paint**, so there is no
layered-fill compositing to unpick. Only **3 nodes have strokes** (`83:1703`,
`1746`, `1757` — the three open rings), all three identical: one `SOLID` white
paint, weight 1.5 uniform on all four sides, `INSIDE`, cap `NONE`, join `MITER`,
miter limit 4, no dash. Every paint has `blendMode: NORMAL` and
`boundVariables: {}`.

There are **two colours** in this frame and nothing else. No hue anywhere. No
accent. Everything is white, or grey at some strength, or the near-black gradient.

| Value | Where it is used | Node count |
| --- | --- | --- |
| **`#FFFFFF` @ 100%** | completion dot fill; completion bar fill; open-ring stroke; lit habit name; lit habit icon; today's weekday letter; every glow colour | 20 |
| **`#FFFFFF` @ 1%** | interior wash of the open ring (single and span) | 3 |
| **`#8D8D93` @ 100%** | resting habit name; resting habit icon; **all six non-today weekday letters**; the vestigial spacer text | 17 |
| **`#8D8D93` @ 50%** | the missed ✕ (as node opacity 0.5 on the `Union`) | 3 |
| **`#8D8D93` @ 16%** | every upcoming slot and upcoming span | 28 |
| **`#8D8D93` @ 0%** | invisible placeholder frames that reserve a slot's position | 12 |
| **`#8D8D93`, `visible: false`** | the missed slot's frame, and row 7's hidden column-2 slot | 4 |
| **`#464649` → `#000000`** @ effective 3% | the root's vertical gradient | 1 |

`#8D8D93` is rgb(141, 141, 147) = rgb(0.5529, 0.5529, 0.5765).

Composites — **the Figma page background is `#191919`, not black**, so the
render you see and the phone you ship to differ:

| Strength | on `#191919` (as seen in Figma) | on pure black (a black wallpaper) |
| --- | --- | --- |
| 100% | rgb(141, 141, 147) | rgb(141, 141, 147) |
| 50% | rgb(83, 83, 86) | rgb(70, 70, 74) |
| 16% | rgb(43, 43, 44) | rgb(23, 23, 24) |

The 16% upcoming slot nearly doubles in luminance between the two backgrounds.
Anything matched by eye off a Figma screenshot will be too light on device.

> **Note against `docs/design-system.md`:** that document lists `headerRest` as
> `#8D8D93` @ **60%**. In this node the six resting weekday letters are `#8D8D93`
> at **100%** — the same value as a resting habit name. There is no 60% paint
> anywhere in the subtree.

---

## 11. Consolidated type table

Complete census of all 24 `TEXT` nodes:

| Dimension | Distinct values found |
| --- | --- |
| Font family | **`SF Pro`** — one, exactly |
| Font style | **`Regular`** — one, exactly |
| Font weight | **`400`** — one, exactly |
| Font size | **`12`** and **`14`** — two, exactly |
| Line height | **`AUTO`** — one, exactly; never an explicit value |
| Letter spacing | **`0%`** — one, exactly |
| Text case | `ORIGINAL` | 
| Text decoration | `NONE` |
| Truncation / max lines | `DISABLED` / unset |
| Styled segments per node | **1** on all 24 — no mixed-format ranges anywhere |
| Fill paints per node | **1** on all 24, every one at `opacity: 1` |
| Node opacity | **1** on all 24 |
| Text strokes | **none** — not one text node has a stroke |

**One family, one style, one weight, two sizes.** No bold anywhere — including
the habit names that are due and today's weekday letter, which are distinguished
by white plus a glow instead. Nothing is italic, condensed, or expanded.

| Element | Family | Style | Weight | Size | Box height | Line-height ratio | Tracking | Align | Auto-resize |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Habit name | SF Pro | Regular | 400 | **12** | 14 | **1.167** | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| Weekday letter | SF Pro | Regular | 400 | **12** | 14 | **1.167** | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| Spacer (vestigial) | SF Pro | Regular | 400 | 12 | 14 | 1.167 | 0% | `LEFT`/`TOP` | `WIDTH_AND_HEIGHT` |
| **Habit icon glyph** | SF Pro | Regular | 400 | **14** | 17 | **1.214** | 0% | **`CENTER`**/`TOP` | `WIDTH_AND_HEIGHT` |

Line height is `AUTO` on every node. The ratios above are the resolved results
(12 → 14, 14 → 17), given because `lineHeight: AUTO` does not survive translation
to another platform and these are the numbers that reproduce the box heights.

Measured cap height at 12 pt: **8.455** (0.705 × size). Round-letter overshoot
(`S`): **8.854**, i.e. 0.4 pt above cap on each side.

### The family, and what was available but unused

Figma reports **45 installed styles** for `SF Pro`:

> Thin · Ultralight · Light · Regular · Medium · Semibold · Bold · Heavy · Black,
> each with an Italic; plus Compressed, Condensed and Expanded width variants of
> the nine weights.

The file uses **one of the 45**. Width is exposed by this install as *named
styles* (Compressed / Condensed / Expanded), not as an axis, so choosing
`Regular` is what selects normal width. `SF Pro Rounded` is also installed and is
not used.

> **Correcting a detail in the generated code:** `get_design_context` emits
> `fontVariationSettings: '"wdth" 100'` on every text node. That is codegen
> boilerplate, not a property of the file — `listAvailableFontsAsync` reports
> **no variation axes at all** (`variationAxes: {}`) for this SF Pro install.
> There is nothing variable-font-related to reproduce.

---

## 12. Consolidated effect table

Complete census. **27 effects across 18 nodes, forming 5 unique effect arrays.**
By type: **20 × `DROP_SHADOW`, 6 × `INNER_SHADOW`, 1 × `GLASS`.** No
`LAYER_BLUR`, no `BACKGROUND_BLUR`, no `NOISE`, no `TEXTURE`.

Every glow colour is `#FFFFFF`. The four shadow recipes, plus glass:

| Recipe | Type(s) | Radius | Colour | Alpha | Offset | Spread | Nodes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Mark glow** | `DROP_SHADOW` | **9** | `#FFFFFF` | 1.0 | (0, 0) | 0 | 7 |
| **Ring** | `DROP_SHADOW` ×2 | **5** | `#FFFFFF` | **0.5** | (0, −1.25), (0, +1.25) | 0 | 3 |
| ” *(same array)* | `INNER_SHADOW` ×2 | **2.5** | `#FFFFFF` | 1.0 | (0, −1.25), (0, +1.25) | 0 | ” |
| **Label glow** | `DROP_SHADOW` | **1.5** | `#FFFFFF` | 1.0 | (0, 0) | 0 | 6 |
| **Today glow** | `DROP_SHADOW` | **2** | `#FFFFFF` | 1.0 | (0, 0) | 0 | 1 |
| **Glass** | `GLASS` | 4 | — | — | — | — | 1 |

The ring's four effects are **one array on one node**, in this order: outer −y,
outer +y, inner −y, inner +y. Order matters for compositing and is preserved
here.

Exactly which nodes carry which:

| Recipe | Node IDs |
| --- | --- |
| Mark glow (r 9) | `83:1702`, `1719`, `1735`, `1769`, `1771` (dots) · `83:1783`, `1792` (bars) |
| Ring (4-effect array) | `83:1703`, `1746`, `1757` |
| Label glow (r 1.5) | `83:1698`, `1699` (Workout) · `83:1743`, `1744` (Early night) · `83:1750`, `1751` (Hydration) |
| Today glow (r 2) | `83:1684` only |
| Glass | `83:1676` only |

Verified on **every** one of the 27: `visible: true`, `blendMode: NORMAL`,
`spread: 0`, `boundVariables: {}`. Verified on every one of the 20 drop shadows:
`showShadowBehindNode: false`. (`INNER_SHADOW` has no such property — correctly
absent, not omitted.)

Five radii — **1.5, 2, 2.5, 5, 9** — are the entire vocabulary. There is no
stacking: no node carries two shadows of different radii to fake a long tail.
The only node with more than one effect is the ring, and its four are two
symmetric pairs.

Nothing carrying `#8D8D93` has an effect. **A miss does not glow, an upcoming day
does not glow, a resting label does not glow.** Light is the only signal of state;
the greys are its absence.

Ratios to the 17.5 slot, if you need to scale the grid:

| Glow | Radius / slot |
| --- | --- |
| Mark | 9 / 17.5 = **0.514** |
| Ring outer | 5 / 17.5 = **0.286** |
| Ring inner | 2.5 / 17.5 = **0.143** |
| Ring y-offset | 1.25 / 17.5 = **0.0714** |

Figma's shadow radius is roughly **half** a CSS blur and roughly equal to a
SwiftUI `.shadow(radius:)`. The generated CSS in `get_design_context` doubles
every number above (`0 0 18px`, `0 ±2.5px 10px`) — those are CSS px, not points.

---

## 13. Measured glow extents (render bounds)

What the effects actually cost in space. Render bounds minus bounding box, in
points, per side.

| Element | Box | **Painted footprint** | L | T | R | B |
| --- | --- | --- | --- | --- | --- | --- |
| Completion dot | 7 × 7 | **25 × 25** | 9 | 9 | 9 | 9 |
| Completion bar (row 7) | 36.5 × 4 | **54.5 × 22** | 9 | 9 | 9 | 9 |
| Completion bar (row 8) | 189 × 4 | **207 × 22** | 9 | 9 | 9 | 9 |
| Open ring | 17.5 × 17.5 | **27.5 × 30** | 5 | 6.25 | 5 | 6.25 |
| Open-ring span | 76.5 × 17.5 | **86.5 × 30** | 5 | 6.25 | 5 | 6.25 |
| Upcoming slot / span | any | equal to box | 0 | 0 | 0 | 0 |
| Missed ✕ | 7.0713² | equal to box | 0 | 0 | 0 | 0 |
| Lit name "Workout" | 48 × 14 | 49.266 × 11.936 | 0.973 | −0.676 | 0.293 | −1.389 |
| Lit name "Early night" | 60 × 14 | 61.324 × 14.168 | 0.422 | −0.559 | 0.902 | 0.727 |
| Today's letter "T" | 8 × 14 | 10.504 × 12.455 | 1.449 | −0.545 | 1.055 | −1 |

Negative values mean the ink falls *inside* the em box — normal for text, where
the box includes side bearings and full line height.

### Per-row painted height

| Row content | Row box | **Row render** | Spill T | Spill B |
| --- | --- | --- | --- | --- |
| Dots only (rows 2, 3, 6) | 313 × 17.5 | **313 × 25** | 3.5 | 4 |
| Contains an open ring (rows 1, 4, 5) | 313 × 17.5 | **313 × 30** | 6.25 | 6.25 |
| Bars (rows 7, 8) | 313 × 17.5 | **313 × 22** | 2 | 2.5 |

### Clearances that matter

| Between | Measured |
| --- | --- |
| Row 1 glow bottom (66.75) and row 2 glow top (67) | **0.25 pt** |
| Two adjacent dot glows horizontally (25 wide on a 29.5 pitch) | **4.5 pt** |
| Two adjacent ring glows horizontally (27.5 wide on a 29.5 pitch) | **2 pt** |
| Header ink bottom (31.5) and row 1 glow top (36.75) | 5.25 pt |
| Row 8 bar glow right (331.5) and widget right edge (338) | 6.5 pt |
| Row 8 label ink right (121.172) and track left (128) | 6.83 pt |
| Row stack painted extent | y 36.75 → 255.5, x 15 → 331.5 |

**Adjacent rows' glows come within a quarter of a point of touching.** The 10 pt
row gap is not slack — it is almost exactly consumed by the ring halo's 6.25 pt
of vertical spill above and the dot halo's 3.5 pt below. Reduce the row gap and
the glows will overlap; that is the constraint that sets the 27.5 pitch.

---

## 14. What the frame actually depicts

Today is **Tuesday**. Seven columns, Monday-first.

| # | Habit | SF Symbol | Label state | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Workout | `figure.run` | **lit** | ● dot | ○ **ring** | · | · | · | · | · |
| 2 | Stretch | `figure.flexibility` | resting | ✕ | ● dot | · | · | · | · | · |
| 3 | Study | `book` | resting | ✕ | ● dot | · | · | · | · | · |
| 4 | Early night | `bed.double` | **lit** | ⟨— open-ring span, Mon–Wed —⟩ | | | ⟨— upcoming span, Thu–Sun —⟩ | | | |
| 5 | Hydration | `drop` | **lit** | ✕ | ○ **ring** | · | · | · | · | · |
| 6 | Touch Grass | `leaf` | resting | ● dot | ● dot | · | · | · | · | · |
| 7 | Touch Grass | `leaf` | resting | ▬ bar, Mon–Tue | | *(hidden)* | ⟨— upcoming span, Wed–Sun —⟩ | | | |
| 8 | Watch Sunset | `sunrise` | resting | ▬▬▬ bar, full week Mon–Sun | | | | | | |

Legend — `●` completed dot · `○` open ring (today / due) · `✕` missed ·
`·` upcoming · `▬` completed bar

The three lit labels (Workout, Early night, Hydration) are exactly the three rows
whose Tuesday cell is **not** already satisfied: Workout and Hydration show an
open ring, Early night is mid-span. Rows 2, 3, 6, 7 and 8 have Tuesday handled
and their labels rest at grey. So **the label's brightness reports "this one
still wants you today"**, and the row's marks report history.

Two rows are both named "Touch Grass" — rows 6 and 7 are the same habit shown at
two different frequencies (daily slots vs a spanning bar), sitting side by side
as a comparison, not two real habits.

---

## 15. Reproducing it — the derivation order

Everything in the grid falls out of the slot. If you scale, scale from there.

```
slot          = 17.5
gap           = 12                    = 0.686 × slot
pitch         = slot + gap = 29.5
rowGap        = 10                    (set by glow spill, not taste — §13)
rowPitch      = slot + rowGap = 27.5

dot           = 7      = 0.400 × slot,  inset 5.5, radius 3.5,  glow r9  → 25×25
bar thickness = 4      = 0.229 × slot,  y 7, radius ≥ 2,        glow r9  → +9 all sides
ring stroke   = 1.5    = 0.086 × slot,  INSIDE, fill #FFF @1%,  glow r5 α.5 ±1.25y
missed arm    = 9 long × 1 thick at ±45°, inset 5.5, opacity 0.5, no glow

span(n)       = n × slot + (n − 1) × gap
              = 17.5, 47, 76.5, 106, 135.5, 165, 194.5   for n = 1…7

label         = 98
labelGap      = 15
iconColumn    = 24        (name starts at 28.5, so the gap is 4.5)
track         = 200       (declared; content ends at 194.5 — do not use it)

padLeading    = 15
padTrailing   = 16        (asymmetric — do not average)
padVertical   = 16
headerGap     = 13
headerHeight  = 14
headerCell    = 28 × 14,  headerCellGap = 1.5   (same 29.5 pitch)

text          = 12        SF Pro Regular, line height 14
icon          = 14        SF Pro Regular, line height 17
corner        = 30,  cornerSmoothing 0
```

### Deltas against the current implementation

`GlowWidget/WidgetMetrics.swift` matches the file on every layout number —
15/16/16 padding, 13 header gap, 10 row gap, 98 label, 15 label gap, 24 + 4.5 icon
column, 12 text, 14 header height. Two values differ:

| | File (`83:1676`) | `WidgetMetrics.swift` |
| --- | --- | --- |
| Gradient top | `rgb(70, 70, 73)` @ **0.03** | `rgb(70, 70, 73)` @ **0.05** |
| Gradient bottom | `rgb(0, 0, 0)` @ **0.03** | `rgb(10, 10, 15)` @ **0.15** |

The file's 0.03 is the product of a 0.15 stop alpha and a 0.20 paint opacity —
easy to miss if you read only the stop, and easy to over-read if you take Figma's
swatch at face value. Neither of the code's numbers appears anywhere in the node.

Absent from `WidgetMetrics`: the **30 pt corner radius**, `cornerSmoothing 0`,
the **`GLASS` effect**, and the **14 pt icon size**.

---

## 16. Verified absent

Checked across all 117 nodes and found **not present**. Listed so the negative
space is documented and nobody has to re-derive it.

**Structure**
- Components, component sets, instances — none
- Shared styles: `fillStyleId`, `strokeStyleId`, `effectStyleId`, `textStyleId` — **0 hits**
- Variables / `boundVariables` — **0 hits**, on nodes, paints and effects alike
- Masks (`isMask`) — none
- Locked nodes — none
- Export settings — none, on any node
- Prototype reactions — none
- `constrainProportions` — false everywhere

**Geometry**
- **`cornerSmoothing`** — `0` on all 93 corner-bearing nodes
- Per-corner radii — all 90 radius-bearing nodes are uniform on all four corners
- Rotation — `0` on 111 of 117 nodes; the only six are the ✕ rectangles at ±45°
- Layout grids — none
- `minWidth` / `maxWidth` / `minHeight` / `maxHeight` — unset everywhere
- `layoutGrow` — `0` everywhere
- `layoutWrap` — `NO_WRAP` on all 20 auto-layout frames
- `overflowDirection` — `NONE` everywhere
- Mixed `itemSpacing` — none

**Strokes** (only 3 nodes have any: `83:1703`, `1746`, `1757`)
- Dash patterns — none
- `strokeCap` — `NONE` (default); `strokeJoin` — `MITER` (default); `strokeMiterLimit` — `4` (default)
- Per-side stroke weights — uniform 1.5 on all four sides of all three

**Paint & effects**
- Non-`NORMAL` blend modes — none, on any node, any fill, or any effect
- Image fills, video fills, pattern fills — none; 88 `SOLID` + 1 `GRADIENT_LINEAR`, and nothing else
- Nodes with more than one paint — **none**, all 117
- `LAYER_BLUR`, `BACKGROUND_BLUR`, `NOISE`, `TEXTURE` effects — none
- Non-zero effect `spread` — none, on all 27 effects
- `showShadowBehindNode: true` — none, on all 20 drop shadows
- Invisible effects (`visible: false`) — none
- Effects bound to variables — none
- Effects on anything grey — none

**Text** (all 24 nodes)
- Font families other than `SF Pro` — none (`SF Pro Rounded` is installed, unused)
- Font styles other than `Regular` — none, out of **45 installed styles**
- Font weights other than **400** — none
- Font sizes other than **12** and **14** — none
- Italic, condensed, compressed or expanded styles — none
- Variable-font axes — the family reports **none**; the `wdth 100` in Figma's generated CSS is codegen boilerplate
- Mixed styled segments — none; every node is a single uniform run
- Text strokes — none
- Text nodes with more than one fill paint, or a fill opacity below 1 — none
- Text node opacity below 1 — none
- Explicit line heights — none; all `AUTO`
- Letter spacing other than **0%** — none
- `textTruncation` other than `DISABLED`, or any `maxLines` — none
- `paragraphSpacing` / `paragraphIndent` — `0`
- `hangingPunctuation` / `hangingList` — false
- `leadingTrim` — `NONE`
- `listOptions` — `NONE`
- OpenType feature overrides — none
- `textCase` / `textDecoration` — `ORIGINAL` / `NONE`

**Non-default flags that *are* set** (all inert)
- `strokesIncludedInLayout: true` on `83:1678`, `83:1695` — neither has strokes
- `counterAxisSpacing: 0` on all 20 auto-layout frames — only applies when wrapping
- `layoutAlign: STRETCH` on `83:1678` — this one is real; it is what fills the header to the content width
- `isAsset: true` on 10 slot frames — Figma's export hint, no visual effect

---

## 17. Node index

| Node | Name | What it is |
| --- | --- | --- |
| `83:1676` | Widget — Large | root, 338 × 354, r30 smoothing 0, gradient, glass |
| `83:1677` | content | padding + clip, vertical stack |
| `83:1678` | Frame 3 | header row, `layoutAlign: STRETCH` |
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
| `83:1786`–`1792` | Early night | row 8 — Watch Sunset (full-week bar) |
