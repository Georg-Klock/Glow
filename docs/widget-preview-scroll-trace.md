# Widget preview scroll trace (#479)

This is the repeatable physical-device gate for the scrolling copy of Glow's
production widget views. Simulator timing is useful for regression diagnosis,
but it cannot fill this table or close #479.

## Fixed setup

- Build: Release, exact PR head; record the SHA below.
- Device: a physical 60 Hz iPhone. On a ProMotion phone, enable **Settings →
  Accessibility → Motion → Limit Frame Rate** and record that choice.
- Instruments: Core Animation plus SwiftUI, with Points of Interest included.
- Fixtures: first 8, then 30 non-spacer habits named `Trace 01`…`Trace 30`, in
  numeric sort order, alternating Daily and 3 Times per Week. Use a disposable
  local store. Completion history is held constant between the before and
  after builds; for the combined #478 run, seed 730 completed days per habit.
- Begin on **Glow → Widgets** at the top, let the first frame settle for two
  seconds, scroll once to the bottom and back to warm the realized cards, then
  return to the top before recording.

## Gesture and capture

For each fixture and power/motion condition, start recording and perform eight
full-speed flicks, alternating down and up so the eighth returns to the top.
Keep the finger inside the widget column and do not pause between settled
flicks. Stop after the final frame settles. Repeat one trace if a notification,
debugger stop or unrelated process interrupts it.

Run all six cells: 8 and 30 habits under Normal, Low Power Mode, and Reduce
Motion. For each trace record Core Animation frame durations after the warm-up,
the p95, the largest hitch attributable to preview rendering, and whether
SwiftUI/Time Profiler shows off-screen socket shadow/filter or card-body work
scaling with the full catalog.

Pass criteria at 60 Hz:

- median frame time ≤ 16.7 ms;
- p95 frame time ≤ 33.3 ms;
- no preview-rendering hitch > 50 ms;
- controls remain tappable, speak their current label and hint, flip
  optimistically, and reconcile in every power/motion condition;
- work follows the realized scroll neighborhood, not all monthly cards.

## Recorded result

- PR head: **pending physical connection**
- Device / OS: **pending physical connection**
- Instruments version: **pending physical connection**
- Trace archive: **pending physical connection**

| Habits | Condition | Median | p95 | Largest attributable hitch | Off-screen scaling | Controls |
| ---: | --- | ---: | ---: | ---: | --- | --- |
| 8 | Normal | pending | pending | pending | pending | pending |
| 8 | Low Power Mode | pending | pending | pending | pending | pending |
| 8 | Reduce Motion | pending | pending | pending | pending | pending |
| 30 | Normal | pending | pending | pending | pending | pending |
| 30 | Low Power Mode | pending | pending | pending | pending | pending |
| 30 | Reduce Motion | pending | pending | pending | pending | pending |

Do not replace `pending` with simulator measurements. Store the `.trace` under
`Artifacts/manual/479/` and link its relative path here; do not commit a trace
that contains personal habit names or other private store data.
