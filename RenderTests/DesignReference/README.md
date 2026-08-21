# The design export the render diff is waiting for

`WidgetRenderDiffTests` renders the real `WeekWidgetView` at the design frame's
own 338 × 354 and diffs it against a flat export of the frame. The render half
runs tonight and always; the diff half waits for one file that only the design
file's owner can mint:

- **Node:** `83:1676` — the large-widget frame `docs/widget-large-spec.md` is
  measured from. It depicts the Tuesday of §14, which is exactly the fixture
  the harness renders.
- **Export:** PNG at **2x**, giving **676 × 708** pixels.
- **Filename:** `widget-large-338x354@2x.png`, committed in this directory.

Once the file is here, `Tools/test.sh` starts printing a report on every run:
how many pixels disagree beyond a small tolerance, and which grid rows carry
the disagreement, plus a difference map written to the test's temporary
directory.

Two disagreements are expected and documented rather than bugs: every glow is
HDR against the file's clipped 255 white, and the container's Figma `GLASS`
effect is not reproduced (docs/design-system.md, "Not in the file"). The
harness deliberately has no pass/fail threshold — it reports, and deciding
what a disagreement means is a person's job.
