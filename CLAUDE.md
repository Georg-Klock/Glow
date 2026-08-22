# Glow Up

A one-screen iPhone habit tracker. The one twist is in the name: a mark
**physically glows** on an HDR-capable screen.

**Light marks the habit; what stays dark is what never happened.** Today's open
slot glows because it is still actionable, and every completion glows too,
whatever day it fell on — SPEC §1 has said so from the start. What does not glow
is absence: a missed day, a day still to come, a rep that ran out of days.

That single rule decides more than it looks like it does, and the corollary is
that **light cannot also be what separates open from done** — so shape carries
that instead. A slot open today is a ring and a completion is a dot; a
repetition still open on the Today ring is an outlined band and a logged one is
a line. Both lit, different silhouettes.

This paragraph used to say the glow was "not a reward for finishing", and the
Today ring was built to match: it painted a logged repetition grey and was the
one surface in the app where a completion went dark. The rule it was reaching
for is real — brightness must not mean *well done* — but grey for a completion
overshot it into contradicting §1. See #75 and docs/decisions.md.

## Read first

- `docs/vision.md` — **the target.** The product intent as three screens, dated.
  Where the code disagrees with it, the code is the backlog.
- `SPEC.md` — product truth for what exists today.
- `docs/glow.md` — how the glow actually works, and why PQ rather than gain
  maps. **Read this before touching anything HDR.** Every gain-map encoding came
  back from `UIImage.isHighDynamicRange` as false; that road is closed and the
  writeup says why.
- **There is no design-system document, on purpose.** Colour, type, geometry and
  effects live in the code that draws them and nowhere else: `GlowPalette`,
  `GlowShape`, `WidgetMetrics`, `SlotLayout`, `DayRing`. Read those. Two
  documents used to publish the same numbers and both drifted — see
  `docs/decisions.md`.
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

  The generator itself is pinned in `Tools/xcodegen.pin` by version *and* by
  the digest of its release archive, and fetched by `Tools/install-xcodegen.sh`
  into a gitignored cache — the generated project is a function of `project.yml`
  and of the generator, so a floating generator floats the project. After
  generating, `Tools/check-project.py` reads the project back as a property list
  and **fails the generation** if App Groups, the entitlement or the widget's
  `APPLICATION_EXTENSION_API_ONLY` is not really there. The textual repair fixes
  what it recognises; the validator is what notices when it recognises nothing.

- **Tests:** `Tools/test.sh`

  Not a hand-typed `xcodebuild test`. The script **asserts a non-zero test
  count**, so a scheme that builds no test target fails instead of exiting 0 and
  looking exactly like a pass. It also picks whichever iPhone simulator the
  machine actually has, so it behaves the same locally and on CI. It prints
  `L1 <n>/<n>`; that number goes in the PR body.

- **Regenerate the symbol picker catalog:** `Tools/make-symbol-catalog.py`
- **Render the website's HDR word images:** `Tools/make-glow-word.swift`

  The glow technique applied to type, for the brightness slider on the project
  page. See the end of `docs/glow.md` for what was measured, including the one
  trap: a screen without headroom tone-maps the result to grey, so the page has
  to test for headroom before showing it at all.
- **Read the widget's trace off a tethered phone:** `Tools/pull-widget-log.sh`
- **Check the App Group entitlement survived signing:** `Tools/check-app-group.sh`
- **Validate the generated project on its own:** `Tools/check-project.py`

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
- **Two colours, both opaque: glow white and `#171717`** (#111). Not a grey
  ramp — the palette used to stack opacities into four steps and the grid read
  as a grey scale. `GlowPalette` is the single source, and `GlowPalette.grey` is
  a `ShapeStyle`, not a `Color`, because two of its three answers are the
  system's: Increase Contrast lifts it to `#8D8D8D`, and **accented widget
  rendering (Clear/Tinted) strips the background and keeps only alpha**, where
  an opaque grey comes back as a lit mark and the hierarchy collapses into one
  tone. That is why the alpha-stored grey still exists and why it is reached
  through `resolve(in:)` rather than at the call site.
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
- **A root `.tint()` beats anything that derives a colour from it.** This tint
  is pure white, so any control that fills with it and draws its label in "the
  contrasting colour" renders white on white. Three instances so far:
  `role: .destructive`, `Toggle` (#124), and `.borderedProminent` (#162), where
  both empty-state buttons measured 8077 interior pixels of a single colour
  with no label in them. Draw prominent controls explicitly — a `Text` over a
  filled `Capsule` — rather than styling them and hoping.
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
