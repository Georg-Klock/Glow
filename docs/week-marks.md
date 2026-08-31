# Week marks

Dated 2026-08-27, status updated 2026-08-28. It specifies two things: **what a
weekly habit's row draws** — the pills, the circles and the ✕ (§1–§7) — and, in
§8, **the large widget's visual geometry**, read off Figma node `228:10690` and
reconciled against the code.

**§1–§5 and §7 have shipped.** #339–#342, #344 and #345 landed as #350–#354; the
behaviour those sections describe is `main`, not a target, and `SPEC.md` should
be read alongside them rather than in place of them. §6 (creation credit, #343)
landed as #355, and #415 corrected its formula for a week with a completion
before the creation day. §8 is unbuilt in full — #331, #332, #333 and
#335 are open issues, tracked under #338 — and remains **a target, not shipped
behaviour**: while it is unbuilt, the code's existing dot-and-bar marks are what
the widget draws. Landing any part of §8 still requires the `docs/decisions.md`
entry named under "Decisions this reopens" in the same change.

Emission is fully settled (§2, §8.5, §8.7) — both the open mark's construction
and the appearance of emitting text were resolved against Figma nodes `228:11106`
and `228:11107` and are no longer open questions, only unbuilt ones.

---

## 1. The rule

A habit due N times a week draws **N marks across seven columns**. A mark is one
repetition. The columns are weekdays and never move.

> **A mark spans from the end of the previous mark through its own anchor day.**

That single sentence is the whole layout, and it is also the forgiveness
mechanism. A day that goes by unused has no mark of its own, so it is swallowed
by whatever mark comes next — it is never a hole, and never an accusation. The
app shows a failure only when one has become arithmetically unavoidable, and
then it shows exactly as many as are unavoidable.

The bias is toward acting early: the week divides with **the remainder to the
right**, so the near days are single columns and the slack collects at the end
of the week. Singles are pacing, not obligation — missing one costs nothing but
room.

Columns run from the user's configured week start. Every example below uses a
Monday start for legibility only.

---

## 2. Vocabulary

| Term | Meaning |
| --- | --- |
| **Row** | One habit's week. |
| **Column** | One weekday. Always seven. |
| **Mark** | One repetition's shape. A row draws exactly `target` of them. |
| **Anchor** | The column a mark ends on. |
| **`target`** | Reps per week. 1–7. |
| **`credit`** | Reps granted to a habit created part-way into the week (§5). |
| **`owed`** | `target − credit − completions`, floored at zero. |

Mark states:

| State | Light | Shape |
| --- | --- | --- |
| **done** | lit, but not emitting | filled |
| **open** | emitting | at most one per row, today only |
| **upcoming** | unlit | outline |
| **dead** | unlit | outline, with a ✕ glyph on its anchor column |

**Light comes in two tiers, and that is new** (2026-08-27). The HDR glow is
reserved for what is still actionable — today's weekday letter while any habit
is open, the name of a habit open today, its SF Symbol when it has one, and the
open mark itself. An emoji remains full colour while the name beside it emits
(#457). A completion is *lit* but does not emit: an object catching light rather
than a source of it.

That reverses the corollary `CLAUDE.md` opens with — "light cannot also be what
separates open from done — so shape carries that instead" — because under two
tiers it is exactly what separates them. It is not #75 returning: a completion
is bright, and nothing here paints one grey. What changed is that brightness now
has a top step a completion does not reach. `CLAUDE.md` and `SPEC.md` still
carry the one-tier rule and are the contradiction to settle next.

---

## 3. Invariants

1. A row draws exactly `target` marks. Always — however late in the week, however
   the goal is going.
2. The marks tile all seven columns: contiguous, no gaps, no overlaps.
3. Every mark is at least one column wide.
4. At most one mark is `open`, and only when today is in this week and unspent.
5. A day holds at most one completion. Days are binary.
6. No mark ever carries two ✕ glyphs.

Invariant 1 is what makes the row readable: a 5x row is five shapes whether you
are ahead, behind or finished, so its silhouette says what the habit *is*
without being read.

---

## 4. Layout

Notation for the worked states below — one character per column, brackets are
mark boundaries:

```
█ done (lit, filled)    ○ open today (emitting)
· upcoming (unlit)      ✕ dead rep, drawn on its anchor column
```

A done mark that spans several columns is lit uniformly across all of them. A
dead mark that spans several columns is unlit track with the ✕ on its anchor;
the columns before it are the days it swallowed.

### 4.1 Procedure

1. Compute `credit` (§5), `completions` (days logged this week), and
   `owed = max(0, target − credit − completions)`.
2. **If `owed == 0` the goal is met.** Draw `target` marks: the credit marks pack
   left, then one mark per completion anchored on the day it was logged, and the
   last mark runs to the final column. Every mark is lit. Completions past the
   target have no mark of their own — they fall inside the last one, which
   already runs to the end. The record keeps them; the row simply has nothing
   left to say.
3. **Otherwise**, build the mark list in this order:
   - `credit` credit marks — unlit, no anchor
   - every **anchored** mark in day order: one **done** mark per completion on
     its column, one **dead** mark per dead day (§6) on that column, and the
     **open** mark on today — omitted when today is spent, is the rest day, or
     is not in this week
   - the remaining **upcoming** marks — unlit, no anchor

   **The open mark sorts by its anchor like every other anchored mark** (#382).
   It used to be listed after the done and dead marks instead, which is the same
   order only while every completion is in the past. A completion logged *after*
   today — reachable through `SlotEditing.week(allowingFuture:)` — is an anchor
   to the right of the open mark's, so in a list read left to right the two
   swapped: the ring was drawn on a day that is not today and the completion's
   mark ended before the day it was logged on. A spent today has no anchor, so
   it keeps its place after the completions: it is not an event on a day, it is
   the arithmetic that divides what they leave.

   What a week *should* look like once you have logged ahead is a separate
   question and is not settled here — see #382. This is the anchor rule applied
   to one more mark, not an answer to it.
4. Assign columns left to right. An anchored mark ends on its anchor. A run of
   unanchored marks divides the free columns between its neighbours as evenly as
   whole days allow, **remainder to the right**. The last mark in the row always
   ends on the final column.

### 4.2 The open mark ends at today

It starts wherever the previous mark ended — reaching back over any blank days —
and ends **on today**, not at the end of its share. The exception is when it is
the last mark in the row: then it runs to the end of the week, because there is
nothing after it to divide.

So the open mark is a single lit ring on most rows, and stretches only when it
has swallowed dead days behind it, or when it is the last rep owed.

### 4.3 Worked states

**Week start, nothing logged.** The remainder-right division, and the open mark
ending at today:

```
      M  T  W  T  F  S  S
7x   [○][·][·][·][·][·][·]
6x   [○][·][·][·][·][·  ·]
5x   [○][·][·][·  ·][·  ·]
4x   [○][·  ·][·  ·][·  ·]
3x   [○][·  ·  ·][·  ·  ·]
2x   [○][·  ·  ·  ·  ·  ·]
1x   [○  ·  ·  ·  ·  ·  ·]      last mark: runs to the end
```

**Monday logged, still Monday.** Today is spent, so no row has an open mark:

```
      M  T  W  T  F  S  S
7x   [█][·][·][·][·][·][·]
5x   [█][·][·][·  ·][·  ·]
3x   [█][·  ·  ·][·  ·  ·]
1x   [█  █  █  █  █  █  █]      met
```

**Mon done, Tuesday skipped, Wed done — Wednesday, spent.** Tuesday is swallowed
by Wednesday's mark on every row that can still afford it. Only 7x, where every
rep owns a day, has an unavoidable miss:

```
      M  T  W  T  F  S  S
7x   [█][✕][█][·][·][·][·]      5 owed, 4 days -> one dead
6x   [█][█  █][·][·][·][·]      4 owed, 4 days -> clean
5x   [█][█  █][·][·][·  ·]
4x   [█][█  █][·  ·][·  ·]
3x   [█][█  █][·  ·  ·  ·]
2x   [█][█  █  █  █  █  █]      met -> last mark runs to the end
```

**3x, Mon and Tue done, Saturday.** One rep owed and it is the last mark, so it
takes everything from Tuesday onward — Wednesday through Friday went by unused
and cost nothing:

```
      M  T  W  T  F  S  S
3x   [█][█][○  ○  ○  ○  ○]
```

**3x, only Monday done, Saturday.** Two owed, two days: Saturday and Sunday are
both now mandatory. The open mark still reaches back, but Sunday keeps its
column:

```
      M  T  W  T  F  S  S
3x   [█][○  ○  ○  ○  ○][·]
```

**5x, nothing logged, Thursday.** One rep died when Wednesday ended; Monday and
Tuesday are unaccused, inside the dead mark:

```
      M  T  W  T  F  S  S
5x   [·  ·  ✕][○][·][·][·]
```

**3x, nothing logged, Saturday.** The week broke on Friday:

```
      M  T  W  T  F  S  S
3x   [·  ·  ·  ·  ✕][○][·]
```

---

## 5. The dead-rep rule

> A **blank past day `d`** carries a dead rep when
> `owed_through(d) > capacity_after(d)`,
> where `owed_through(d) = target − credit − completions on or before d` and
> `capacity_after(d)` is the days after `d` that can still carry one of those
> reps: the blank actionable ones, **plus the ones already completed**.

Pure, day-pinned, and computed from the record rather than from an event log —
so a backfill recomputes it away with no stored state to migrate.

**A completed day is capacity, not a free day** (#381). It counted
`actionable_days_after` — every day after `d` that is not the rest day, blank or
not — and that is right only while every completion is in the past and off the
rest day. Neither is guaranteed: the week view opens the days *after* today on a
demo-seeded store, and moving the rest day in Settings turns a day that was
logged into a day nothing may be logged on. In the first case a completion after
`d` was counted as a free day *and* not subtracted from `owed_through`, so its
rep was owed twice; in the second the day was dropped from both sides at once.
Either way the walk stopped agreeing with `max(0, owed − days_left)`, and
`WeekSpans` asked for a negative number of ✕ marks — `EXC_BREAKPOINT`, on every
redraw of the week.

**The count is always right.** Walk the week: `owed_through − capacity_after`
increases by exactly one on each blank actionable day, stays flat on each
completed day — which moves both sides by one — and stays flat on a blank rest
day, which is in neither set. So it is monotone, and the days it is positive on
are the last *k* blank days, where *k* is `max(0, owed − days_left)` today. The
pinned ✕ and the arithmetic cannot disagree.

**It never warns and never predicts.** A miss becomes a ✕ at the moment the day
ends and the arithmetic tips, and not before. A 3x row stays clean until Friday
ends; do Monday, Tuesday and Wednesday then stop and the only ✕ lands on
Saturday, which is exactly the day the week broke.

**A ✕ is not final.** Tapping it logs that day and the ✕ recomputes away —
possibly from a different column than the one tapped, since the rule re-derives
the whole week. Past days are editable **in the app only**; the widget draws the
✕ and cannot answer it.

### 5.1 Pinning is possible except after an upward edit

Pinning needs one blank past column per dead rep. With `c` = the column a habit
was created on, that requires `target − credit + c ≤ 7`, and since
`credit = max(0, target − (7 − c))` the two sides are equal — pinning fits
exactly, always.

The one exception is an upward target edit on a habit created part-way into the
week, where `credit` stays frozen (§6) while `target` grows and the inequality
breaks. A dead rep with no blank column to pin to **loses its anchor and
floats**: it keeps its place in the mark order and takes the leftmost free
column. It never doubles up — invariant 6 stands.

---

## 6. Creating a habit part-way into the week

A habit made on Friday has not failed the Monday it did not exist for. It is
granted **the minimum credit that avoids a ✕, and not one more**:

```
capacity = days from the creation day to the end of the week
         + days before it that already carry a completion
credit   = max(0, target − capacity)
```

The minimum matters. Granting every pre-creation day would collapse the
remaining reps into one wide pill, which reads as slack the habit does not have:

```
5x created Friday, credit 2       [·  ·][·  ·][○][·][·]     3 owed over 3 days
5x created Friday, credit 4       [·][·][·][·][○  ○  ○]     the pill this rule avoids
7x created Friday, credit 4       [·][·][·][·][○][·][·]     still reads as a 7x
```

Credit marks are unlit. They are arithmetic, not a claim that anything was done.

**A day before creation that carries a completion is not a day that was
forgiven** (#415). It is a day a rep landed on, so it counts toward what the
target can be met out of exactly as a remaining day does — which is why
`capacity` has two terms rather than one. Back-filling one is reachable:
`DemoHistory.seed` hands every habit to `SeededHistory.completions` with no
bound from `createdDay`, so the demo writes ten weeks of past onto a habit made
this morning, and #265 leaves a daily row's pre-creation day tappable on purpose.

Counting it is not politeness, it is what makes the row fit. `credit` is at most
the creation day's column — `target ≤ 7` is the whole proof — so the grant's marks
take the columns before creation and the completions take the ones after, and
the open mark still reaches today. A completion *before* creation puts one more
mark into the columns the grant has already claimed, and §4.1's step 4 clamps a
mark's end **up** as well as down, because a mark cannot end before the marks
ahead of it have somewhere to be. Six a week made on Wednesday with Monday and
Tuesday logged drew:

```
6x created Wednesday, credit 1    [·][█][█][○][·][·  ·]   the ring on Thursday
6x created Wednesday, credit 0    [█][█][○][·][·][·  ·]   today is Wednesday
```

— breaking §3 invariant 4 and §4.2 while `actionDay` stayed on today, so a tap
did the right thing and only the drawing lied. Capacity there is seven against a
target of six: nothing was unavoidable, so the minimum grant was none.

The smaller grant can let a ✕ through that the over-grant was hiding, and it is a
true one. Three a week made on Saturday with Monday logged has capacity three
and is granted nothing; on Sunday the blank Saturday is a day the week genuinely
broke on, and the ✕ lands there. A habit is still never born already failing:
what is owed on the creation day is at most `capacity` minus what is already
done, which is at most the days it has left.

**Credit is frozen at creation, and can only shrink.** On any target edit:

```
credit = min(frozen, max(0, new target − days from creation to week end))
```

| Edit | Result | Why |
| --- | --- | --- |
| 5x → 7x | `min(2, 4) = 2`, unchanged | An edit gets no amnesty. |
| 5x → 3x | `min(2, 0) = 0`, gone | Otherwise the row meets its goal off unearned credit. |
| 5x → 2x | `min(2, 0) = 0`, gone | Same. |

Over-shooting the target with **real** reps reads as met — the work happened.
Over-shooting it with credit would be the app claiming work that did not.

---

## 7. Refresh

The row is a function of the record and of today, so it changes on exactly two
events:

- **the instant a completion is logged or undone**, and
- **midnight**, when the division re-flows and any newly dead rep appears.

The widget therefore needs a scheduled timeline entry at the next local midnight.
Without it the Home Screen row is a day stale — showing yesterday's open ring on
a day it is no longer actionable, which is the one thing SPEC §1 says light must
never do.

---

---

## 8. The large widget, visually

Measured from Figma `228:10690` — "Week Widget — Large — harness fixture
(Tuesday)" — with the deviations named in §8.6 corrected. Every number is
authored at 1x, in points.

**This section is temporary.** When it lands, these values belong in
`WidgetMetrics`, `SlotLayout`, `GlowShape` and `GlowPalette`, each beside the
reasoning those files already carry, and this section goes. There is no
design-system document in this repository on purpose, and this is not the start
of one.

### 8.1 Frame and insets

| | |
| --- | --- |
| Size | 338 × 354 |
| Corner radius | 24, uniform, clipped |
| Fill | **dark glass material** — `.ultraThinMaterial` at the 18.0 deployment target; Liquid Glass is iOS 26 and unavailable |
| Insets | left **6**, right **14**, top **10**, bottom **14** |

The insets are a deliberate optical adjustment, not derived: neither axis is
centred, and 6/10/14 sit outside the 8/4 spacing the rest of the frame uses.
Recorded so they are not "corrected" later.

### 8.2 Columns and rows

The track is 216 × 312 at (108, 28). No fill; it carries one inner shadow over
its contents — see §8.4.

- **Columns** — 7 × slot **24**, gap **8**, pitch **32**. `x = 108 + 32i`.
- **Rows** — 10 × height **24**, gap **8**, pitch **32**. `y = 28 + 32j`.
  `9 × 32 + 24 = 312` exactly.
- **Span width** for *n* columns — `32n − 8`: 56, 88, 120, 152, 184, 216.
- Label column → track: **4**. Weekday row → track: **4**.

### 8.3 Marks

Every mark is a **socket**, optionally with an **inner shape** inside it. The
socket is a `#000000 @ 15%` fill under its bevel — #427 supersedes the "no fill
at all" this section was written with, and §8.6 with it. The inner shape is the
socket inset 1pt on all four sides with its radius reduced by 1, and it is what
carries the state: filled for a completion, stroked for an open slot. Pill
widths are always `32n − 8`.

| | Socket | Inner |
| --- | --- | --- |
| Circle | 24 × 24, r 12 | 22 × 22, r 11 |
| Pill — done or open | h **24**, r 12 | h **22**, r 11 |
| Pill — upcoming | h **24**, r 12 | none |

Every mark is centred in the 24pt row, and **every mark is the same 24pt recess
holding the same 22pt inner** — a pill is a circle drawn long. #426 replaced the
14/12 pill this section was transcribed with, and the file (node `248:12822`)
still draws spanning marks thinner; the app deliberately does not follow it
there. The two-tier rule that the pill height used to carry — an open pill 2pt
taller than an upcoming one, its inner exactly the track it replaced — went with
#332 and is not coming back.

**The dead mark is the same 22pt inner.** Its ✕ measures `22.0007 × 22.0006`
in node `260:2819`, centred dead in the slot — `11/12` — so it is an instance of
the one-inner rule rather than an exception to it (#427). The bar is `6.7592`
thick (`9/32`) with a `0.8450` corner radius, and that radius is the same number
as the ✕'s own bevel offset.

### 8.4 Effects

Four recipes, and nothing else in the frame — no blurs, no blend modes.

```
Socket          fill                       #000000 @ 15%
                inner  0 / −1.5  blur 1.5  #FFFFFF @ 13%
                inner  0 / +1.5  blur 1.5  #000000 @ 100%

Lit fill        inner  0 / +1    blur 1    #FFFFFF @ 100%
                inner  0 / −1    blur 1    #000000 @ 30%

Missed ✕        fill                       #000000 @ 15%
                inner  0 / +0.845 blur 0.845  #000000 @ 100%
                inner  0 / −0.845 blur 0.845  #FFFFFF @ 25%
                inner  0 / +4    blur 3     #000000 @ 48%

Emitting        drop   0 / 0     blur 1                #FFFFFF @ 100%
                inner  0 / 0     blur 1   spread −1    #FFFFFF @ 100%

Track container inner  0 / +6    blur 6    #000000 @ 25%
```

**The socket's fill and the ✕'s three shadows are #427**, read out of node
`260:2819`'s own SVG filter definitions rather than off a screenshot. Two of
them are reversals of what this section shipped with: the socket gained a fill
where §8.6 called one a slip, and the track container's shade *left* the socket
— `260:2819` draws no third inner shadow on an open mark. It stays on a
completion's lit fill and arrives on the ✕ at 48% rather than 25%. That
asymmetry is the file's; `docs/decisions.md` records it so the obvious later
cleanup does not unify them back.

The emitting pair is a tight white bloom either side of a 1pt stroke, and it is
for **marks only** — emitting text takes none of it (§8.5). Figma's stand-in for
the real thing. **The HDR glow is a code-side effect scaled by
`GlowSettings`** and cannot be drawn in Figma at all, so the 1pt blur is a
placeholder for its shape, not a specification of its size. The app also drew an
SDR halo around a lit mark until #394; nothing spreads outside a mark's own
silhouette now.

Socket and lit fill invert each other's light direction: a socket is pressed in,
a lit mark stands proud. **The socket bevel was drawn against a 7–10% white
ground**, which the glass material replaces — `#000000 @ 100%` will read heavier
against it than Figma shows, and wants checking on a device.

### 8.5 Type, colour and emission

One face throughout: **SF Pro Regular, 12pt**, `wdth 100`, line-height normal,
single line, truncating with an ellipsis.

- **Habit label** — 98 × 18, vertically centred on its row. Icon column 24 wide
  at x 0; the shipped glyph is 12pt, matching the name (#455). Name at x 26.25,
  max width **69.5** — `98 − 24 − 2.25 − 2.25`. The second gap is the
  `HStack` spacing before the trailing spacer; keeping both in the derivation
  prevents the name from reaching the grid.

  The Figma glyph is 14pt. #404 first corrected it to 10pt, two points smaller
  than the name; the phone read that as too small, so #455 makes equality the
  rule. The column remains 24pt, so changing the glyph does not move the name.
- **Weekday letter** — cell 24 × 14 at the column's own x, text centred.

Colour is one hex and three steps of it, and it says what is still asked of you:

| | Weekday letter | Habit label |
| --- | --- | --- |
| `#FFFFFF` + emitting glow | today, any habit open | this habit open today |
| `#D9D9D9` @ 100% | today, everything closed | handled today |
| `#D9D9D9` @ 50% | any other day | at rest |

An SF Symbol carries the **same value as its name** in every state; the two dim
and emit together. An emoji is already a full-colour picture, not type: it
keeps those colours in every tier while only the name beside it dims or emits.
The emitting mask therefore excludes emoji (#457). A done mark is `#D9D9D9`
under the lit bevel of §8.4 — lit, but not emitting, per §2.

**Emitting text carries no drawn effect at all** — no drop shadow, no inner
shadow. It is `#FFFFFF` and nothing else, and what makes it emit is the HDR
headroom behind that white rather than a bloom painted around it. The emitting
pair in §8.4 belongs to marks: its inner half has a −1 spread, which lines the
inside of a 1pt ring and would erode a 12pt glyph to nothing.

### 8.6 Corrected on the way in

Six deviations from an otherwise regular system, taken as slips:

| Found in the file | Corrected to |
| --- | --- |
| Two long done pills drawn socket 12 / inner 10 (rows 2x and 1x) | socket 14 / inner 12, like every other done pill — **socket 24 / inner 22 since #426**, which took every pill to the circles' height |
| Weekday letter cells 17.455 wide — the *old* slot — on a 32pt pitch, landing 0.27 left of centre | 24 wide, on the column |
| Name max width 84.5, derived from the old 15pt label gap, overrunning the track by 11 | 73.5 in the transcribed design; **69.5 in the shipped arrangement since #455**, after both gaps halved |
| Socket fill `#D9D9D9 @ 1%` | no fill; the socket is its bevel — **superseded by #427**, which gives it `#000000 @ 15%`. Not this slip returning: black at 15% presses the recess in where near-white at 1% would lift it out |
| SF Symbol pure white beside a `#D9D9D9` name | symbol takes the name's value |
| Emoji sent through the emitting mask | emoji stays full colour; only its name emits |
| Four zero-size boolean nodes; one fully authored but hidden row | file detritus, dropped |

### 8.7 The open mark

From Figma `228:11106` (pill) and `228:11107` (circle, drawn beside a done one).
An open mark is the done mark's construction with the fill swapped for a ring,
so §8.3 carries the geometry and this adds only what the ring is:

| | Socket | Ring |
| --- | --- | --- |
| Pill, 2 col | 56 × **24**, r 12 | 54 × **22**, r 11 |
| Circle | 24 × 24, r 12 | 22 × 22, r 11 |

| | |
| --- | --- |
| Stroke | **1pt, inside-aligned, `#FFFFFF`** — outer edge flush with the ring box |
| Fill | none; the socket's bevel shows through the middle |
| Glow | the emitting pair of §8.4 |

**The stroke is 1pt at both sizes.** It is a constant, not a fraction of the
mark — the same weight rings a 12pt pill and a 22pt circle, so `ringWeight`'s
`3 / 35` goes. That `3 / 35 × 12` lands on 1.03 is a coincidence and reading a
rule out of it would have given the circle a 2pt stroke it does not have.

Since a one-column mark is a circle at every frequency (§4.3), this is also the
open mark for a weekly row whose open slot happens to be one column wide, not
only for a daily row's today.

### 8.8 What this moves in the code

Visual only; §"Seven changes" below covers the behavioural half.

| | Now | Target |
| --- | --- | --- |
| Slot / gap / pitch | 17.455 / 11.969 / 29.424 | **24 / 8 / 32** |
| gap ÷ slot | 0.686 (24 ⁄ 35) | **0.333** |
| Track | 194 | **216** |
| Insets | 15 / 16 / 15 | **6 / 14 / 10 / 14** |
| Label → track | 15 | **4** |
| Header → track | 13 | **4** |
| Rows | 11 | **10** |
| Unlit day | 3pt dot in the socket | **22pt disc** |
| Unlit span | 2pt line | **22pt lozenge** (10pt when transcribed; #332 then #426) |
| Background | none, removed deliberately | **dark glass material** |
| Resting grey | `#8D8D8D`, opaque | **`#D9D9D9` @ 50%** |

Two of those carry a cost worth stating. `nameMaxWidth` is derived from the
label gap and must be re-derived with it, or a long name runs under the grid.
And the resting grey becoming translucent reverses what #111, #194 and #240
settled: accented rendering discards colour and keeps alpha, so a weekday letter
that was opaque on a Clear or Tinted home screen will now render at half
strength there.


# PRD

## What changes in the shipped code

`WeekSpans` already produces most of this shape. Seven changes, roughly in
dependency order:

1. **`divide` gives the remainder to the right**, not the left. Today a 6x week
   ships as a pill across Mon–Tue then five singles; the target is five singles
   then a weekend pill. One line, and it is the whole early bias.
2. **A filled span draws lit.** `SlotSpan.mark` currently maps `.filled` to
   `.upcoming` — the same unlit line an upcoming span draws. This is the change
   that reopens #47 (below).
3. **The completed block anchors on real days.** It currently divides the
   columns before today evenly among the completions. It must instead give each
   completion a mark ending on the day it was logged, reaching back to the
   previous mark.
4. **Dead reps pin.** `placeLost` currently parks them immediately left of the
   open span. Replace with the §5 rule, plus the float fallback of §5.1.
5. **The met-goal state stops collapsing.** It currently returns one span across
   the whole week; it must keep each completion on its day and let the last mark
   run to the end.
6. **Creation credit** — a new concept. `HabitSnapshot.existed(on:)` already
   knows the creation date; the frozen value needs the target *at creation*,
   which is a stored field and a migration.
7. **A midnight timeline entry** in the widget provider.

Unchanged: the open mark's extent (`openLast` already ends at today and already
runs to the end when it is the last mark) and the seven-column covering
invariant (#81).

**`Frequency.daily` needs no change and must stay consistent.** A 7x row is
day-pinned through `WeekGrid`, not `WeekSpans`. Check that the two agree: for
`target == 7` the §5 rule fires on any blank past day, which is exactly
`WeekGrid`'s per-day miss. If they ever disagree, one of them is wrong.

## Decisions this reopens

**#47, "a span is structure, not a mark."** That decision made an achieved span
draw the same unlit line as an upcoming one, on the grounds that a division of
the week does not change when a share of it is achieved — and that the lit dot
`WeekDots` places on the real weekday is what says a rep happened, so the row
"stops being a progress bar and becomes a record of when". Lighting the filled
mark reverses that: the row becomes a progress bar again, and a mark that has
reached back over a blank day no longer says which of its columns the rep landed
on.

That cost was weighed and accepted. The mark's **left edge** still carries when,
the row's job is *how much is left*, and the alternative — an unlit track with a
lit dot inside it — leaves the swallowed day visible as a gap, which is the
thing this model exists to remove.

Consequences to carry with it:

- **`WeekDots` loses its visual job.** Its dots become redundant with the lit
  marks. `spokenDays` does not — it is the only way VoiceOver reaches which days
  were logged, and it becomes *more* valuable once the visual stops saying it.
  Keep the accessibility string; drop the dots.
- **`docs/decisions.md` needs an entry that explicitly supersedes #47**, per the
  authority order in `CLAUDE.md`. A reversal left unrecorded reads as drift.
- **The Today-ring precedent (#75) is not what this touches.** Nothing here
  paints a completion grey; every completed mark is lit, on every surface. What
  the two tiers above change is the *ceiling* — a completion no longer reaches
  the glow — and #75's reasoning was written against a one-tier world, so it
  needs re-reading rather than citing.

## Risks

- **The row now reads as fuller than the work done.** A 1x habit completed on
  Monday lights the whole week; a 7x habit completed on Monday lights one
  column. That is intended — a met goal is a lit row whatever the target — but it
  should be looked at on a device before it is called finished, because it is a
  perceptual claim and the simulator has no headroom to test it with.
- **A wide open mark reads as slack it may not have.** 3x with only Monday done,
  on Saturday, draws a five-column open ring at the moment both remaining days
  became mandatory. The shape says room; the arithmetic says none.
- **Credit is invisible.** A 5x created on Friday asks for three reps and gives
  no on-screen account of the two it forgave.
- **The float case (§5.1) is the only place the ✕ lies about its day.** It is
  reachable only by editing a mid-week habit's target upward.

## Deferred, on purpose

- **The rest day.** It still exists as a setting and still subtracts a column
  (#72, #73, #100). How it interacts with pinning a ✕, with reaching back across
  it, and with `capacity_after` is **unsolved and deliberately out of
  scope here.** Nothing in this document should be read as having settled it.
- **Animation.** What moves when the division re-flows at midnight.
- **The glow work behind this**: a completed habit's SF Symbol and name going
  dark, today's weekday letter lighting, the open marks glowing. Emoji remain
  full-colour content while their names take the tier (#457).

## Tests

All of it is pure and belongs in `Glow/Logic/`, exercised through the real types.
Property tests for the invariants of §3 across every `target` × every weekday ×
every completion pattern:

- exactly `target` marks;
- the marks tile all seven columns, contiguous and non-overlapping;
- ✕ count equals `max(0, owed − days_left)` — the §5 monotonicity claim, checked
  rather than trusted;
- no mark carries two ✕;
- at most one open mark, and it contains today;
- backfilling any day never increases the ✕ count.

Plus the worked states of §4.3 as fixtures, and `Tools/test.sh` before the PR
with its own printed verdict in the body.
