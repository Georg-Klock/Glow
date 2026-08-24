# Vision

Dated 2026-08-20, revised 2026-08-22, 2026-08-23 and 2026-08-24. This is the
product intent, cleaned up from a brain dump and kept short on purpose. Where it
disagrees with what is built, this document is the target and the code is the
backlog.

**One section below is the exception to that sentence, and says so on purpose**
(#235, 2026-08-24). `## Three screens` used to be Today, This Week and Settings;
the shipped app has Widgets, This Week and Settings. The question that raised —
whether the Widgets tab is part of the target, or a tenant of Today's slot until
the per-day kind comes back — was answered rather than tidied away: **it is part
of the target**, and so is the tab order it sits in. That section was therefore
brought up to the code, rather than the code being brought up to it. Nothing
else here changed direction. Left unmarked, the update would be
indistinguishable from drift, and the next reader would be right to file the
Widgets tab for removal.

**Today and the per-day habits are 2.0, not MVP** (#209, 2026-08-23). They were
built exactly as `## Deliberately later` describes them and then taken out of
the shipped app — the screen, the two widget families, `Frequency.timesPerDay`
and the five seeded habits — and preserved whole on `feature/daily-habits-2.0`.
Nothing is withdrawn: the screen is still wanted, which is why its description
moved down the page rather than off it. What changed is the order, and this note
is here so that a later reader does not have to wonder whether it was ever
built.

That is why the revision dates exist rather than a footnote. A stale line here
does not read as stale — it reads as an instruction — so when the Today ring's
rule was reversed and this document was not, it was one grep away from being
faithfully re-implemented as a regression. Kept in sync, dated, or deleted;
there is no fourth option for a document that outranks the code.

## The idea

A minimalist habit tracker. The widget is the product; the app is where you go
when the widget is not enough.

The app had grown four screens and two ways of looking at history. That was
overcomplicated. Three screens.

## A habit is one kind or the other

Either it is done **several times a day** — water, a short walk three times, a
sitting practice morning and evening — or it has a **weekly cadence**. Not both.

**Only the weekly kind ships** (#209). The per-day kind was built and pulled
back to 2.0, so this is currently a distinction with one side in it: every habit
in the app has a weekly cadence, and nothing in the app asks which kind a habit
is. The rule stands for when the other side returns.

What the split decided was which screen a habit belonged on, and that is the
sentence to be careful with now. The first two screens are no longer two kinds
of habit — they are the widgets and the week. Today is a third, and the split
comes back when it does.

It can be revisited later; it is not a shape the data has to be built around
now.

**No streaks.** No screen counts consecutive days. The app shows what is left to
do, not a record to protect.

## Three screens

**Widgets, This Week, Settings**, in that order in the tab bar (#238), with This
Week as the landing tab.

### Widgets

Every widget the app ships, drawn by the code that ships it, over the person's
own habits — with the sizes already on the Home Screen marked, and one block of
instructions for adding the rest (#210, #225, #237).

**This is the section below made literal.** If the widget is the main product,
then what a new person most needs from the app is a widget on their Home Screen,
and nowhere in iOS shows them what they would be getting: the gallery offers a
name and one sentence. Leading the tab bar with the widgets is that argument
stated in the tab bar — the first tab is what the app says it is about.

It is not the stronger claim, and should not be allowed to grow into it. **The
app is not a widget installer.** This Week is where the work happens and where
every launch lands; the Widgets screen is where the product introduces itself,
and somebody who has placed what they want will rarely open it again. A screen
can be the purest statement of what the product is and still be the least
visited one.

- **The previews are the shipping views**, laid out at the size the family
  really gets and then scaled to fit — not illustrations, and not a fixture. A
  preview of somebody else's week is a mockup with extra steps.
- **"Added" is per size, not per widget.** The week widget is small, medium and
  large, each placed independently; having one says nothing about the others.
- **Placed widgets stay on the page**, marked, rather than dropping off it. What
  is already on the Home Screen belongs beside what is not.
- **The instructions are said once, above everything.** No API places a widget
  or opens the gallery, so the page is built around a long-press the person
  performs. That constraint is the page's shape rather than something it works
  around, which is why the steps are the loudest text on it.
- **Nothing else on the page is prose** (#237). A card carries the widget's name
  and its size; the widget itself is drawn directly under them, over real
  habits, which is the same sentence said better.

### This Week

The weekly-cadence habits, and **where the app opens**. Broadly what is built
today, but it should look **closer to the widget than it currently does**. The
target is literal: tapping the widget gets you a bigger version of the same
thing, not a different screen that happens to show the same data.

**Rows: as many as fit, then a hard cut.** No "+3 more" row — a row spent
saying how much is missing is a row not showing a habit.

**A row says *when*, not just *how many*.** A habit due three times a week is
drawn as three shapes stretched across the seven days, and a lit dot sits on
each day it actually happened. The shapes answer "what is left"; the dots
answer "when did I do this" — which is the question a week view is for, and the
one a row of pills alone cannot answer.

### Settings

Stays in the bottom bar, trailing. It holds the app's preferences and the two
things that are neither a widget nor this week:

- **History.** The long view. The year grid lives in here rather than being a
  tab of its own.
- **Export.** Send yourself your history as a CSV or JSON file.

## The widget is the main product

Every screen exists because of a widget. Two of them are where you go when the
widget is not enough; the third is how you get one in the first place. Design
the widget first and let the app follow it, rather than designing an app and
fitting a widget around it.

**The widget chooses the screen.** A widget that opens the app opens it on that
widget's own screen rather than on one fixed screen. With only the weekly
widgets shipping, every such link currently lands on This Week — and
`glow://today`, which was the other one, is deliberately left unmapped rather
than pointed somewhere else (#209): landing somebody on a screen they did not
ask for is worse than doing nothing when nothing can be done.

This divides a widget's surface in two, and the division has to be deliberate
rather than discovered:

- **The marks act in place.** A week slot toggles where it stands. It does not
  open anything — acting without leaving the home screen is the point.
- **Everything else opens the app**, on the screen matching that widget.

**On a cold launch This Week opens**, since the app icon has no widget to ask.
It is the denser screen and the one there is work to do on.

**The landing tab and the first tab are not the same tab, on purpose.** This
Week is what the app opens to; Widgets is what it leads with. `RootTabView`
holds the two separately — the landing screen is the selection's default, not a
consequence of declaration order — so the bar can say what the app is about
while still opening on the screen you came to use. Read together they look
contradictory; they are answering two different questions.

## What this changes

- **The year view stops being a tab** and becomes History inside Settings.
- **Four tabs become three.**
- **Habits gain a second kind** — a per-day count — which the data model did
  not have when this was written.

All three landed. They are kept here rather than deleted because the point of
the list is what the vision *asked for*, and a target with nothing left to hit
is worth being able to see.

The third has since been taken back out of the shipped app and held for 2.0
(#209). It landed; it is not shipping. See the note at the top.

The second held through a change of *which* three. Today's slot in the bar was
left empty rather than collapsed when the screen came out, and the Widgets tab
took it (#210); the order was then looked at on its own terms and Widgets moved
to the front (#238). The count never moved.

## Deliberately later

Anything under this heading is deferred **with the reason written down**, so
that deferring stays a decision rather than a silence.

### Today, and the per-day kind

**Built, shipped, and held for 2.0** (#209). It is preserved whole on
`feature/daily-habits-2.0` — the branch is the snapshot, and this is the
description of what comes back. It is here rather than in the section above
because the app does not have this screen; it is here rather than deleted
because the app is meant to.

The several-times-a-day habits, and nothing else. This screen is the small and
medium widget at app size:

- **Small** — one habit: an icon inside a ring. The user picks which habit, per
  widget, so several small widgets can sit on a home screen showing different
  habits.
- **Medium** — up to **three** habits: three icons, three rings, all the same
  size. Like the WHOOP widget, but with no size hierarchy between them.
- **No large.** There is nothing to put in it that three rings do not already
  say, and offering a size in order to fill it is how a minimal app stops being
  one.

**The ring is the day, and doing the habit closes it.** A repetition still to
do is an outlined band; one that is done is a line drawn through the middle of
where that band was. **Both glow.** Consecutive completions merge into one run
rather than staying a row of ticks, so the ring reads as a single closing
gesture, and at the goal it is one unbroken glowing circle.

This is the same rule as everywhere else in the app, and it is worth stating in
the direction that keeps being got wrong: **light marks the habit; what stays
dark is what never happened.** Brightness is not a score and not a reward — a
completion is not something to hide. What separates *still open* from *done* is
shape, because it cannot also be light.

**The ring is arcs, one per repetition**, so the count is legible without
reading a number. A day's target is **1 to 12**. At 1 the ring is a single
unbroken circle, because a gap would imply a division that is not there.

**Tapping adds one.** A tap is `+1` on the counter, straight from the widget.
**Once the ring is full, the next tap resets it to zero.** That is the only way
back, and it is also the undo.

The `+1` is the only thing on this screen that moves: the line sweeps clockwise
to its new end, crossing the gap it is closing. Everything else — the reset, a
day turning over, an edit — snaps, because animating a correction dresses a
mistake up as an achievement.

Two Today widget families went with it, and the deep link that opened it. When
the screen returns, so do they, and so does the sentence above about which
screen a habit belongs on.

### Export — no longer deferred

Export was this section's only entry for a while — wanted, placed, and put off
as "might be boiling the ocean". It shipped instead: CSV or JSON, written when
a person asks for it and sent where that person sends it, with no upload and no
sync anywhere. The settled shape turned out to be small enough to just build.
Kept here rather than deleted, for the same reason `## What this changes` keeps
what it asked for.
