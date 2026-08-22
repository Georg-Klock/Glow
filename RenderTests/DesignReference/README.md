# The design export the render diff compares against

`WidgetRenderDiffTests` renders the real `WeekWidgetView` at the design frame's
own 338 × 354 and diffs it against the flat export committed here.

**This diff is a report, not a gate.** The number below is large on purpose and
would be a bad threshold; the gate that fails CI on an unapproved visual change
is `RenderTests/Baselines/render-signatures.json`, which compares the widget
against a committed signature of itself rather than against a flat mockup of an
HDR app. See #138 and `RenderBaselineTests`.

- **Source:** Figma file `0m9qFcvvUrIgLmqIxE0jtj` ("Glow Up"), page **05 Widgets**.
- **Node:** `83:1486` — "Widget — Large", authored at **2x**, 676 × 708. The same
  frame exists at 1x as `58:52`.
- **Filename:** `widget-large-338x354@2x.png` (committed).

**Which weekday this frame is.** It is the **Friday** frame (issue #4's
`83:1485` composite): today is F, and Early night's open span runs Mon–Fri.
That is the frame whose span *follows* `WeekSpans`' rule, so the diff below is
not contaminated by the one row where the file disagrees with itself.

## What the first run reported

```
render-diff: 402296/478608 pixels differ (84.06%) beyond ±8
```

**That number is expected, and it is the harness working.** It is dominated by
two departures the code has already made deliberately and documented:

1. **The container.** The file draws a near-black gradient (~`#08080D` at the
   corners); the app draws pure black. The gradient was followed for a while and
   removed because on a real home screen it read as a panel sitting on the
   wallpaper rather than marks floating on it (see `GlowWidget.swift`). Every
   background pixel therefore differs by ~13, just over the ±8 tolerance — which
   alone accounts for most of the 84%.
2. **The mark vocabulary.** The file draws a 17.5pt dark disc for an upcoming
   day and a ~7pt dot for a completion; the app draws a 3pt dot and a 2pt line,
   absolute rather than proportional, so that "a dot for one day does not grow
   because the grid got wider" (`GlowShape`). The upcoming *span* is a full-height
   lozenge in the file and a thin line in the app.

Neither is a regression, and the harness deliberately has **no pass/fail
threshold** — a gate here would either fail forever or hide behind a number
nobody derived. What the harness is for is catching the *third* kind of
difference: the one nobody meant. Read the band report and the difference map,
not the percentage.

A third, smaller departure is visible and also known: the file's `GLASS` effect
on the container is not reproduced, because SwiftUI has no equivalent.

All three reasons live next to the code that chose them — `GlowWidget.swift` for
the container, `GlowShape` for the mark vocabulary — rather than in a design
document. There is no longer a design document; see docs/decisions.md, "The code
is the source of truth for design".

## Re-exporting

Via the Figma MCP: `get_screenshot` with `fileKey 0m9qFcvvUrIgLmqIxE0jtj`,
`nodeId 83:1486`, `maxDimension 708`. Save over the file above at exactly
676 × 708 — the test asserts the dimensions match the render.
