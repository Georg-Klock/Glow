# Week marks

Dated 2026-08-27. **This is a target, not shipped behaviour.** It supersedes
nothing until it lands; while it is unbuilt, `SPEC.md` and the code are what the
app does. Landing any part of it requires the `docs/decisions.md` entry named
under "Decisions this reopens".

It specifies one thing: **what a weekly habit's row draws** — the pills, the
circles and the ✕. It does not cover the glow work queued behind it (a completed
habit's icon and name going dark, today's weekday letter lighting), which is
separate and later.

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
is open, the icon and name of a habit open today, and the open mark itself. A
completion is *lit* but does not emit: an object catching light rather than a
source of it.

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
   - one **done** mark per completion, anchored on its column
   - one **dead** mark per dead day (§6), anchored on that column
   - the **open** mark, anchored on today — omitted when today is spent, is the
     rest day, or is not in this week
   - the remaining **upcoming** marks — unlit, no anchor
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
> `owed_through(d) > actionable_days_after(d)`,
> where `owed_through(d) = target − credit − completions on or before d`.

Pure, day-pinned, and computed from the record rather than from an event log —
so a backfill recomputes it away with no stored state to migrate.

**The count is always right.** Walk the week: `owed_through − days_after`
increases by exactly one on each blank day and stays flat on each completed day,
so it is monotone, and the days it is positive on are the last *k* blank days,
where *k* is `max(0, owed − days_left)` today. The pinned ✕ and the arithmetic
cannot disagree.

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
credit = max(0, target − days from the creation day to the end of the week)
```

The minimum matters. Granting every pre-creation day would collapse the
remaining reps into one wide pill, which reads as slack the habit does not have:

```
5x created Friday, credit 2       [·  ·][·  ·][○][·][·]     3 owed over 3 days
5x created Friday, credit 4       [·][·][·][·][○  ○  ○]     the pill this rule avoids
7x created Friday, credit 4       [·][·][·][·][○][·][·]     still reads as a 7x
```

Credit marks are unlit. They are arithmetic, not a claim that anything was done.

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
  it, and with `actionable_days_after` is **unsolved and deliberately out of
  scope here.** Nothing in this document should be read as having settled it.
- **Animation.** What moves when the division re-flows at midnight.
- **The glow work behind this**: a completed habit's icon and name going dark,
  today's weekday letter lighting, the open marks glowing.

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
