# Vision

Dated 2026-08-20. This is the product intent, cleaned up from a brain dump and
kept short on purpose. Where it disagrees with what is built, this document is
the target and the code is the backlog.

## The idea

A minimalist habit tracker. The widget is the product; the app is where you go
when the widget is not enough.

The app had grown four screens and two ways of looking at history. That was
overcomplicated. Three screens.

## A habit is one kind or the other

Either it is done **several times a day** — water, a short walk three times, a
sitting practice morning and evening — or it has a **weekly cadence**. Not both.

That decision is what splits the first two screens, and it is what keeps each
screen answering one question. It can be revisited later; it is not a shape the
data has to be built around now.

**No streaks.** Neither screen counts consecutive days. The app shows what is
left to do, not a record to protect.

## Three screens

### Today

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

**The ring starts full and glowing, and doing the habit closes it.** At none
done the whole ring glows; each completion takes a share of it away; at the
goal the ring is quiet. This is the same rule as everywhere else in the app —
the glow is what is still open, never what is finished.

**The ring is arcs, one per repetition**, so the count is legible without
reading a number. A day's target is **1 to 12**. At 1 the ring is a single
unbroken circle, because a gap would imply a division that is not there.

**Tapping adds one.** A tap is `+1` on the counter, straight from the widget.
**Once the ring is full, the next tap resets it to zero.** That is the only way
back, and it is also the undo.

### This Week

The weekly-cadence habits. Broadly what is built today, but it should look
**closer to the widget than it currently does**. The target is literal: tapping
the widget gets you a bigger version of the same thing, not a different screen
that happens to show the same data.

**Rows: as many as fit, then a hard cut.** No "+3 more" row — a row spent
saying how much is missing is a row not showing a habit.

### Settings

Stays in the bottom bar for now. It holds the two things that are neither today
nor this week:

- **History.** The long view — what the year screen is today.
- **Export.** Send yourself your history as a CSV or JSON file.

## The widget is the main product

Both of the first two screens exist because someone tapped a widget and wanted
more room. Design the widget first and let the app follow it, rather than
designing an app and fitting a widget around it.

**The widget chooses the screen.** There is no fixed landing tab: a daily
widget opens Today, a weekly widget opens This Week. You arrive at the bigger
version of the thing you were just looking at.

This divides a widget's surface in two, and the division has to be deliberate
rather than discovered:

- **The marks act in place.** A ring arc takes `+1`; a week slot toggles. These
  do not open anything — acting without leaving the home screen is the point.
- **Everything else opens the app**, on the screen matching that widget.

**On a cold launch This Week opens**, since the app icon has no widget to ask.
It is the denser screen and Today is one tap away.

## What this changes

- **The year view stops being a tab** and becomes History inside Settings.
- **Four tabs become three.**
- **Habits gain a second kind** — a per-day count — which the data model does
  not have today.

## Deliberately later

- **Export.** Wanted, and now placed, but "might be boiling the ocean" for the
  next stretch of work. The shape is settled — a file you send yourself — so it
  can wait without the decision being reopened.
