# Glow Up

A one-screen iPhone habit tracker. The one twist is in the name: today's slot,
while it is still incomplete, **physically glows** on an HDR-capable screen. The
glow means "unfinished, still actionable today" — it is not a reward for
finishing. It disappears the moment the habit is done, and again when the day
ends.

That single rule decides more than it looks like it does. **Every mark in this
app means *still open* when it glows.** A control that brightened on success
would be the one place contradicting it, which is why the Today ring starts full
and closes as you go rather than filling like a fitness ring.

## Read first

- `docs/vision.md` — **the target.** The product intent as three screens, dated.
  Where the code disagrees with it, the code is the backlog.
- `SPEC.md` — product truth for what exists today.
- `docs/glow.md` — how the glow actually works, and why PQ rather than gain
  maps. **Read this before touching anything HDR.** Every gain-map encoding came
  back from `UIImage.isHighDynamicRange` as false; that road is closed and the
  writeup says why.
- `docs/design-system.md` — every colour, type size, radius and effect in use.
- `docs/widget-large-spec.md` — a measured spec of the large week widget.
  Numbers here beat numbers derived from a screenshot.
- `docs/decisions.md` — questions already settled, and why. Reopening one is a
  decision, not a rediscovery.
- `docs/ARCHITECTURE.md` — current technical truth.

## Commands

- **Generate the Xcode project:** `Tools/generate.sh`

  `Glow.xcodeproj` is generated from `project.yml` and **gitignored**. Run this
  after adding or removing any file, and after switching branches when the two
  differ in which files exist — otherwise the build fails with `Build input file
  cannot be found`, which reads like a missing file rather than a stale project.
  Use the script, not `xcodegen` directly: it repairs a `SystemCapabilities`
  value that xcodegen mangles, and without that repair the App Groups
  entitlement is compiled in and then silently stripped by codesign, so the
  widget stops seeing the store.

- **Tests:** `Tools/test.sh`

  Not a hand-typed `xcodebuild test`. The script **asserts a non-zero test
  count**, so a scheme that builds no test target fails instead of exiting 0 and
  looking exactly like a pass. It also picks whichever iPhone simulator the
  machine actually has, so it behaves the same locally and on CI. It prints
  `L1 <n>/<n>`; that number goes in the PR body.

- **Regenerate the symbol picker catalog:** `Tools/make-symbol-catalog.py`
- **Read the widget's trace off a tethered phone:** `Tools/pull-widget-log.sh`
- **Check the App Group entitlement survived signing:** `Tools/check-app-group.sh`

CI runs the tests on every pull request and on merges to `main`
(`.github/workflows/ci.yml`), on a pinned macOS runner — pinned rather than
`macos-latest` because the suite reads gain-map metadata and where that metadata
lives has already been seen to differ between platform versions.

## Working rules

- **One topic branch, one PR, per unit of work.** `git checkout -b <topic>` off
  `main`. Never commit to `main`. **Never merge your own PR** — merging is
  Georg's call.
- **Commit at every working state, push often.** The remote is the backup; an
  unpushed commit exists on one SSD.
- **Claude is the `Author`, Georg is the `Committer`.** The point of this
  project is that a designer directed AI to build it, so the log says that in
  git's own terms rather than in a footnote:

  ```
  GIT_AUTHOR_NAME="Claude Opus 5" GIT_AUTHOR_EMAIL="noreply@anthropic.com" git commit -m "…"
  ```

  Use the specific model name — `Claude Opus 5`, `Claude Fable 5` — not a
  generic "AI". No `Co-Authored-By` trailer when Claude is the author; it would
  name the same party twice. **Commits Georg genuinely wrote stay his** — the
  practice only works if it is accurate in both directions.
- **Run `Tools/test.sh` before opening a PR and state the count in the body**
  ("L1 143/143"). A PR that does not state its result has not been tested.
- **Tests must exercise the real types** (`@testable import Glow`). Never
  re-implement app logic inside a test file — a mirror copy passes forever while
  the app regresses.
- **Decision logic lives in `Glow/Logic/`, pure and testable** — no views, no
  store, no `Date()`. `WeekGrid`, `WeekSpans` and `Frequency` are the pattern.
  Do not grow decision logic inline in a view.
- **When behaviour changes, update the docs in the same session.** Drifted docs
  are worse than none.
- **Machine-local values are never committed.** `Tools/local.env`,
  `Local.xcconfig` and `Signing.xcconfig` hold signing team and device
  identifiers; they are gitignored and a script that needs one reads it from
  there and fails with instructions when it is missing.
- **Anything durable but not shipping goes in `private/`** (gitignored): seed
  prompts, drafts, notes to self. It is the answer to "worth keeping, does not
  belong in the repo", so that the answer is never "commit it and delete it
  later".
- **`MARKETING_VERSION` is Georg's call.** `project.yml` holds both it and
  `CURRENT_PROJECT_VERSION`; do not move the marketing version on your own.

## Verify before you claim

This project has lost more time to confidently-reported non-changes than to any
actual bug. Every line here is something that already happened.

- **Look at the screen.** Build to the simulator, screenshot it, and *read the
  screenshot* before writing that a visual change landed. A diff that looks
  right is not evidence.
- **`simctl launch` on an already-running app does not reload it.** Terminate
  first, or you will screenshot the previous build and believe it.
- **Confirm your file writes happened.** A Python heredoc whose `assert` fails
  skips the write and exits quietly; twice, a change was reported as done that
  never touched the file.
- **Distrust your own measurement scripts.** A pixel-scanning script here had
  its baseline off by four points and produced three real code changes chasing
  an artifact. If a measurement disagrees with the screenshot, suspect the
  measurement.
- **The simulator has no EDR headroom, so the glow does not render there.**
  Geometry, layout, colour and animation are verifiable in the simulator. Glow
  is not — that needs a device. Say which one was checked.
- **A device build needs the phone unlocked.** A locked iPhone reports as
  "unavailable", which looks identical to "not plugged in".

## Traps already paid for

- **The glow modifier uses `.overlay`, not `ZStack`.** The HDR tile is
  `resizable()`, and inside a `ZStack` it expands and centres — which renders as
  glowing text in the wrong place. There is a comment saying so; believe it.
- **Greys are white with alpha, not a hue.** Accented widget rendering
  (Clear/Tinted) strips the background and keeps only alpha, so a grey with a
  colour in it loses its hierarchy. `GlowPalette` is the single source.
- **A widget's background can be removed by the user.** The measurement that
  said otherwise held for `fullColor` rendering only. Handle
  `widgetRenderingMode`.
- **`navigationDestination` attached to the `NavigationStack` itself** compiles,
  renders nothing, and leaves a dead tap target. It must be *inside*.
- **`@Environment(\.editMode)` read by a view that *contains* the
  `NavigationStack` is always inactive.** `EditButton` toggles the value in the
  stack's own environment, below where the outer view reads, so the button
  animates to Done while every tap still does the non-editing thing. Own the
  state (`@State var editMode: EditMode`) and inject it with
  `.environment(\.editMode, $editMode)`.
- **`Color.clear.frame(height:)` is greedy horizontally** and will eat a layout.
- **A root `.tint()` beats `role: .destructive`.** Colour destructive controls
  explicitly.
- **Figma's radius ≈ SwiftUI's radius.** The CSS that design tools emit doubles
  blur radii; do not halve an already-doubled number.

## Writing in public

Issues and PR descriptions are pushed with Georg's credentials, so every word
is published as his.

- **Write in the project's voice.** Describe the code, the evidence and the
  decision. Do not narrate the session, and never refer to Georg in the third
  person from his own account.
- **Keep the corrections, drop the confession.** "This claim was wrong, here is
  the measurement that shows it" is the most credible thing in an engineering
  record. Narrating the mistake-making itself is not. State what was wrong, what
  is true, and what changed.
