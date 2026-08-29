# Glow Up

An iPhone habit tracker: three tabs — Widgets, This Week, Settings — around
one weekly grid. The one twist is in the name: a mark **physically glows** on
an HDR-capable screen.

**Light marks the habit; what stays dark is what never happened.** Today's open
slot is lit because it is still actionable, and every completion is lit too,
whatever day it fell on — SPEC §1 has said so from the start. What stays dark is
absence: a missed day, a day still to come, a rep that ran out of days.

**Light has two tiers, and the top one is reserved for what is still
actionable** (#334, 2026-08-27). The HDR emission — the physical glow — goes to
today's weekday letter while any habit is still open, to the icon and name of a
habit open today, and to the open mark itself. A completion is *lit but does not
emit*: an object catching light rather than a source of it.

That reverses the corollary this paragraph used to draw. It read that **light
cannot also be what separates open from done** — so shape carried that instead,
a ring for open and a dot for done, both lit. Under two tiers light is exactly
what separates them, and shape keeps the job as well: the two say the same thing
twice rather than one of them carrying it alone.

**This is not #75 returning.** Nothing here paints a completion grey; a
completion is bright, on every surface. What moved is the *ceiling* — a
completion no longer reaches the emitting tier — and #75's reasoning was written
against a one-tier world, so it needs re-reading rather than citing.

The rule was settled on a surface that is no longer here. This paragraph used to
say the glow was "not a reward for finishing", and the Today ring was built to
match: it painted a logged repetition grey and was the one surface in the app
where a completion went dark. The rule it was reaching for is real — brightness
must not mean *well done* — but grey for a completion overshot it into
contradicting §1. See #75 and docs/decisions.md. The ring itself went to
`feature/daily-habits-2.0` with the rest of the per-day kind (#209); what it
settled did not go with it.

## What outranks what

When two sources disagree, the higher one on this list is the one to follow —
and the disagreement is worth fixing in the same session, because a
contradiction left standing reads as an instruction to whoever finds it next.

1. **Founder invariants** — the settled product and safety rules: local-only,
   no telemetry, nothing leaves the device unless a person sends it; SPEC §1's
   light rule; the working rules in this file.
2. **Current code, with `SPEC.md` and `docs/ARCHITECTURE.md`** — shipped
   behaviour. Where the code and those two disagree, one of them is a bug; say
   which.
3. **`docs/vision.md`** — the dated target. Aspirational unless a section says
   it shipped; it does not describe what the app does today.
4. **`docs/decisions.md`** — historical, append-only. The latest entry that
   explicitly supersedes an earlier one wins; an early entry is what was
   decided then, not necessarily what is true now.
5. **Closed issues** — snapshots of the moment they were written.
6. **Open issues and PRs** — backlog hypotheses. Verify their claims against
   the current code before acting on them; file:line references and counts in
   an issue body go stale.

## Read first

- `docs/vision.md` — **the dated target.** The product intent as three screens.
  Where the code disagrees with it, that is backlog to raise, not a licence to
  move the app back toward the prose — a stale line there once left the Widgets
  tab one reading away from being filed for removal (#235). The authority order
  above is the rule.
- `SPEC.md` — product truth for what exists today.
- `docs/glow.md` — how the glow actually works, and why PQ rather than gain
  maps. **Read this before touching anything HDR.** Every gain-map encoding came
  back from `UIImage.isHighDynamicRange` as false; that road is closed and the
  writeup says why.
- **There is no design-system document, on purpose.** Colour, type, geometry and
  effects live in the code that draws them and nowhere else: `GlowPalette`,
  `GlowShape`, `WidgetMetrics`, `SlotLayout`. Read those. Two
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

  Not a hand-typed `xcodebuild test`. It picks whichever iPhone simulator the
  machine actually has, so it behaves the same locally and on CI, and it runs
  the suite once into `Artifacts/<run>/` — result bundle, log, attachments and
  a structured verdict, unique per run and gitignored. It prints `L1 <n>/<n>`;
  that number goes in the PR body.

  **A green `xcodebuild` is not the verdict.** After the run,
  `Tools/validate-test-result.py` reads the `.xcresult` and fails the command
  when a declared test bundle did not run, when one ran fewer tests than its
  floor in `Tools/test-inventory.json`, when anything was skipped, when the
  build carries an undeclared warning, or when the render baseline left no
  evidence. All of those exit 0 from `xcodebuild`; one of them was observed on
  this repository the day the check landed. See #138.

  Adding tests never touches the inventory — the floors are minima. **Lowering
  one is the reviewable event**, and it belongs in the same change as the
  deletion that caused it.

  It also switches accessibility on for the simulator it chose, because
  `EmptyStateAccessibilityTests` hosts a live view and walks the tree UIKit
  hands the accessibility server — and UIKit builds no tree at all in a process
  on a device where accessibility was never enabled. A fresh phone is such a
  device, so that suite passed wherever a session had once turned VoiceOver on
  and failed on every CI run, which erases its phone. See #245.

  It holds a lock on the simulator it chose, so two checkouts testing at once
  queue instead of installing competing bundles onto one device. That collision
  does not read as a device conflict — it reads as a dead host, a bundle under
  its floor, or a failure naming a file that is clean in your checkout, and it
  can produce a green run that is partly someone else's. Set
  `GLOW_SIMULATOR_UDID` to give a run its own phone instead of waiting. See
  #221.

  When the render baseline moves, the script prints the one command that
  approves it — for the runtime it just ran on. There are two committed
  baselines, so prefer `Tools/approve-baseline.sh` below, which does both.
  Approving is a decision: say in the pull request what moved.

  It picks the newest installed runtime by default. A lane that exists to test
  a *specific* one sets `GLOW_EXPECTED_RUNTIME_MAJOR` (e.g. `18`), which
  restricts the selection to that iOS major and then asserts the chosen device
  matches — a pinned `GLOW_SIMULATOR_UDID` included — so the minimum-iOS lane
  fails loudly instead of falling forward to a newer runtime (#286). What ran
  is recorded either way: runtime and device on the console, in
  `<run>/simulator.txt`, and at the end of `summary.md`.

- **Approve both render baselines:** `Tools/approve-baseline.sh` (and `--check`)

  A visual change moves two committed files: `render-signatures.json`, measured
  on the newest runtime here, and `render-signatures-ios<major>.json`, measured
  on the one the minimum-iOS lane pins (#286). They are two measurements of the
  same change. This renders on both and approves both, and **refuses to approve
  either when the run failed for any reason beyond the signatures moving** — an
  "actual" copied out of a broken run is how a real failure becomes a committed
  baseline that every later run agrees with. `--check` renders both and writes
  nothing, exiting non-zero if either is out of date; that is the pre-pull-request
  check, because the lane that would otherwise catch it now reports after merge.

- **Regenerate the symbol picker catalog:** `Tools/make-symbol-catalog.py`
- **Render the website's HDR word images:** `Tools/make-glow-word.swift`

  The glow technique applied to type, for the brightness slider on the project
  page. See the end of `docs/glow.md` for what was measured, including the one
  trap: a screen without headroom tone-maps the result to grey, so the page has
  to test for headroom before showing it at all.
- **Shut down simulators nothing is testing on:** `Tools/reap-simulators.sh`

  A booted runtime is not free — ten booted devices with two in use measured
  1,770 CoreSimulator processes and a load average of 797, well past where this
  machine kills a test host during bootstrap. Devices accumulate because
  `GLOW_SIMULATOR_UDID` runs create their own and nothing reaps them, so the
  escape hatch from #221's queue feeds the load that kills the next run. Spares
  anything a live `xcodebuild` names; shuts down rather than deletes, so the
  next run pays one boot. See #247.
- **Read the widget's trace off a tethered phone:** `Tools/pull-widget-log.sh`
- **Check the App Group entitlement survived signing:**
  `Tools/check-app-group.sh [path/to/Glow.app]`
- **Validate a built product before it ships:**
  `Tools/check-release-build.py <Glow.app | Glow.xcarchive | Glow.ipa>`

  Host and widget agreeing on both version keys, the appex being there at all,
  the declared bundle identifiers, the privacy manifests, and — with
  `--require-signing` — the App Group as codesign left it and the embedded
  profile's expiry. None of those is a build failure; the answer used to arrive
  from App Store Connect after the upload. CI runs it on the Release build for
  the device SDK and `Tools/ship-testflight.sh` runs it on the archive and on
  the exported `.ipa`, so the gate and the release path cannot disagree about
  what "matching" means. What it checks is declared in
  `Tools/test-inventory.json`. See #133. With `--require-signing` it also
  rejects the six iCloud/ubiquity entitlement keys and anything outside its
  entitlement allowlist in what the signature grants — the artifact half of
  the local-only invariant (#281).
- **Validate the generated project on its own:** `Tools/check-project.py`
  (and `--self-test`). Besides App Groups and extension-only API, it rejects
  iCloud/ubiquity entitlements and any capability or entitlement outside its
  allowlist — the requested half of the local-only invariant (#281), whose
  source half is `LocalOnlyContractTests` (`cloudKitDatabase: .none` at every
  production store, and no network/CloudKit API spellings outside a reviewed
  allowlist).
- **Check whether a checkout may ship, without shipping:**
  `Tools/ship-testflight.sh --preflight-only`

  The release path refuses a dirty tree, a `HEAD` that is not fetched
  `origin/main` (or a pushed annotated tag), and a SHA without a successful CI
  verdict — before credentials are read — and records source SHA, ref, CI
  verdict, Xcode build and versions into `private/provenance/`. The one narrow
  override is `--allow-unverified-ci`, for the CI-verdict proof only, and it is
  recorded. See #287.
- **Validate the workflows' pinning and permissions policy:**
  `Tools/check-workflows.py` (and `--self-test`). Every `uses:` in a tracked
  workflow is a full commit SHA with its release named beside it, and
  `permissions:` is explicit and no broader than the checker's allowlist.
- **Validate a kept result bundle on its own:**
  `Tools/validate-test-result.py --xcresult Artifacts/latest/Glow.xcresult`
- **Check the documentation for known contradictions:** `Tools/check-docs.py`

  Fails when a contradiction this repository has already paid to remove comes
  back into a normative document: a literal `L1 n/n` count, the app described
  as a single screen, the week start described as fixed to one weekday rather
  than as a setting, or the week widget's dropped small family stated as
  current. Narrow on purpose — it scans for those reintroductions, not for
  prose it dislikes, and `docs/decisions.md` is exempt because a history is
  allowed to say what used to be true. See #288.
- **Check the gates themselves:** `--self-test` on
  `Tools/check-workflows.py`, `Tools/validate-test-result.py`,
  `Tools/check-release-build.py`, `Tools/check-project.py` and
  `Tools/check-docs.py`. All five run on every push, on a Linux runner: a
  checker nobody checks can weaken silently.

CI runs the tests on every pull request and on merges to `main`
(`.github/workflows/ci.yml`), on a pinned macOS runner — pinned rather than
`macos-latest` because the suite reads gain-map metadata and where that metadata
lives has already been seen to differ between platform versions. Two lanes run
the suite: the current runtime, and the declared minimum — an iOS 18 simulator
runtime the lane installs and pins with `GLOW_EXPECTED_RUNTIME_MAJOR` so it
cannot silently fall forward (#286). The deployment target stays 18.0 because
that lane gates it; raising it is a product decision.

**The two lanes do not run at the same times.** The current runtime gates every
pull request and every push. The minimum-iOS lane runs **nightly at 06:00 UTC**,
on `workflow_dispatch`, and on a pull request only when it carries the `ios18`
label. It is a 40-minute job against the current lane's 12, and while it sat in
front of every merge it *was* this repository's pull-request feedback latency;
without it, that feedback measured 9m13s. Measured and decided in
`docs/decisions.md`.

It ran on `push: main` for about an hour in between, and that did not work:
GitHub holds only one pending run per concurrency group, so on a busy night each
merge evicted the previous pending main run before it started — including the
one for the change that introduced it. Do not put it back on `push` without
reading that entry; the failure is silent and it is worst exactly when the most
is landing.

Two consequences to keep in mind. **An iOS 18 failure now appears at 06:00 UTC,
not on the pull request that caused it** — the likeliest cause is a render
baseline approved on one runtime and not the other, which
`Tools/approve-baseline.sh` exists to prevent, and `--check` is the pre-push
habit that closes it. And **a change that genuinely needs the answer before it
merges asks for it**, with the `ios18` label or `workflow_dispatch`.

## Working rules

- **One topic branch, one PR, per unit of work.** `git checkout -b <topic>` off
  `main`. Never commit to `main`. **Merging is Georg's call**, and the default
  is that Claude opens the pull request and stops there.

  He can delegate it, and has — the rule said *never merge your own PR* while
  the person it reserved the button for was asking for the button to be pressed,
  which is a file arguing with the room. A delegation covers the session it was
  given in and does not carry to the next one: the next session opens PRs and
  stops, until it is told otherwise.

  **What is delegable is the waiting, not the decision.** `gh pr merge --auto`
  (auto-merge is enabled on the repository) lands a pull request the moment its
  checks go green, so a delegation does not mean sitting and watching CI — which
  is the part that was never his call to begin with.

  `main` is protected: `Gate self-test` and `Build and test` must pass before
  anything lands. The minimum-iOS check is deliberately *not* required, because
  it no longer runs on pull requests and requiring it would block every one of
  them forever. "Up to date before merging" is deliberately off too — it would
  force a rebase and a fresh full run on every merge, which is the latency this
  setup just removed. Administrators are not included, so there is still a way
  through when one is needed.
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
- **Run `Tools/test.sh` before opening a PR and paste its verdict in the body**
  — the `L1 <passed>/<ran>` line the script itself printed, verbatim, never a
  number remembered or copied from an earlier PR. A PR that does not state its
  result has not been tested. `Tools/check-docs.py` fails on a literal count
  written into this file or the PR template, because every one that was ever
  written here went stale.
- **Tests must exercise the real types** (`@testable import Glow`). Never
  re-implement app logic inside a test file — a mirror copy passes forever while
  the app regresses.
- **Decision logic lives in `Glow/Logic/`, pure and testable** — no views, no
  store, no `Date()`. `WeekGrid`, `WeekSpans` and `Frequency` are the pattern.
  Do not grow decision logic inline in a view.

  A preference a rule depends on **arrives as a parameter**, the way `calendar:`
  and `restDay:` do, read once at the view, widget or store boundary. The rest
  day was the exception and cost four issues in one night (#105, #168, #175,
  #179) before #181 removed it; `TestIsolationTests` now scans for the read.

  **So does "today".** `WeekCalendar.today()` reads the clock and the App Group
  — the debug override (#204) lives there — so it is declared in
  `Glow/Store/DebugToday.swift`, not beside the rest of `WeekCalendar`, and
  `TestIsolationTests` scans `Glow/Logic/` for `Date()` as well. The spelling is
  still `WeekCalendar.today()`; only the declaration sits at the boundary.

- **Per-day habits are on `feature/daily-habits-2.0`, not in the app** (#209).
  `Frequency.timesPerDay`, the Today screen, the Today ring and the two Today
  widget families were built, shipped, and pulled back to 2.0 scope. The branch
  is the snapshot; do not reconstruct them from `git log`.

  **"Daily" is two different things and only one of them left.**
  `Frequency.daily` is a *weekly* cadence due all seven days — seven columns on
  the week grid, Gratitude and Early night in the seed set — and it is
  untouched. Anything that reads like removing week-grid behaviour is the wrong
  one.
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
- **The widget extension does run in the simulator, and almost all of it is
  verifiable there.** Place the widget on the simulator's Home Screen and the
  real paths run: the extension registers, the gallery lists it under its
  `configurationDisplayName`, the provider builds timelines, and `WidgetTrace`
  records them into the App Group where `plutil -p` can read them straight out
  of the device's container. #254 crash-looped the extension on a phone for a
  day and reproduces in the simulator in seconds — nobody had placed a widget
  there. What genuinely needs hardware is the glow, and per-widget
  *configuration*, where chronod serves stale configurations (see
  `docs/decisions.md`).
- **A device build needs the phone unlocked.** A locked iPhone reports as
  "unavailable", which looks identical to "not plugged in".

## Traps already paid for

- **The glow modifier uses `.overlay`, not `ZStack`.** The HDR tile is
  `resizable()`, and inside a `ZStack` it expands and centres — which renders as
  glowing text in the wrong place. There is a comment saying so; believe it.
- **One hex at three steps, and white above them** (#335, 2026-08-28; before it
  #111, #194, #240 and the 2026-08-24 retirement — all in `docs/decisions.md`).
  `#FFFFFF` with a halo emits, `#D9D9D9` at 100% is lit but not emitting, and
  `#D9D9D9` at 50% is at rest.
  **Not a grey ramp** — the palette used to stack opacities into four steps for
  one distinction and the grid read as a grey scale. These are three different
  claims: *do this now*, *this happened*, *nothing is asked here*. The middle
  one exists only because #334 gave light a ceiling a completion does not reach.
  `GlowPalette` is the single source, and `GlowPalette.grey` is a `ShapeStyle`,
  not a `Color`, because two of its three answers are the system's: **accented
  widget rendering (Clear/Tinted) strips the background and keeps only alpha**,
  where an opaque grey comes back as a lit mark and the hierarchy collapses into
  one tone, and Increase Contrast, which since #335 resolves to the `lit` step
  at 14.9:1. Reached through `resolve(in:)` rather than at the call site either
  way. **The resting step is 4.0:1 on purpose** — dimmer than the default was on
  2026-08-24, which is only defensible because it is now the third of three
  rather than the only one; that reasoning is the decisions entry, and moving
  either end of the scale without it is how this gets undone by accident.
- **A widget's background can be removed by the user.** The measurement that
  said otherwise held for `fullColor` rendering only. Handle
  `widgetRenderingMode`.
- **Never pass an interpolated string literal to `configurationDisplayName` or
  `description`** (#254). Those take a `LocalizedStringKey` *or* a
  `StringProtocol`; a bare literal picks the first, and a `LocalizedStringKey`
  holding an interpolated segment is formatted text, which WidgetKit refuses —
  `WidgetKit/Text.swift` traps with ``Formatted text for `…` is not
  supported``, inside its own evaluation of the widget's body, before any
  provider runs. The extension crash-loops and then drops out of the widget
  gallery entirely, which reads as a signing or registration fault and is not
  one. #210 turned two literals into interpolated ones and killed the widget in
  every build that shipped after it. Pass a `String` property —
  `WidgetKind.galleryName` — and `WidgetPlacementTests` scans for the
  interpolated form.
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
