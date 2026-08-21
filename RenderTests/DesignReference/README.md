# The design export the render diff is waiting for

`WidgetRenderDiffTests` renders the real `WeekWidgetView` at the design frame's
own 338 × 354 and diffs it against a flat export of the frame. The render half
runs tonight and always; the diff half waits for one file that only the design
file's owner can mint:

- **Node:** the large-widget frame in file `0m9qFcvvUrIgLmqIxE0jtj`, page
  **05 Widgets** — `58:52` at 1x, `83:1486` at 2x. It depicts the Tuesday the
  harness fixture renders.
- **Export:** PNG at **2x**, giving **676 × 708** pixels.
- **Filename:** `widget-large-338x354@2x.png`, committed in this directory.

Once the file is here, `Tools/test.sh` starts printing a report on every run:
how many pixels disagree beyond a small tolerance, and which grid rows carry
the disagreement, plus a difference map written to the test's temporary
directory.

Some disagreement is expected and is not a bug: every glow is HDR against the
file's clipped 255 white, the container's Figma `GLASS` effect has no SwiftUI
equivalent, and the app's marks are absolute 3pt dots and 2pt lines where the
file draws 17.5pt discs. The reasons live in `GlowWidget.swift` and `GlowShape`
beside the code that makes those choices. The harness deliberately has no
pass/fail threshold — it reports, and deciding what a disagreement means is a
person's job.
