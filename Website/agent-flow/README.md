# The agent-workflow map

One HTML Embed on georgklock.com/glow-up, above the "Agentically built" item
(page `6a88c6481cb44deb7e573ab2`, element `61c6d399-…`). It replaced a linear
strip of six cards, which drew the process as a waterfall with a loop caption.
The system is not a line, so the map draws what it is:

**The edges are the subject, not the tiles.** Every arrow carries the name of
the interaction it stands for — *writes it up*, *picks it up*, *opens a PR*,
*checks run*, *red, again*, *green, merged*, *builds and runs*, *results,
traces*, *TestFlight*, *the glow, by eye*, *reactions*, *prompts the agents*.
An unnamed arrow says two things are connected; a named one says how. The map
is read by following them, so nothing on it is joined without a word.

Three loops, two of them small and one of them large:

- **The test loop.** The agents build and run the change on two kinds of
  machine and read what comes back. Two arrows, *builds and runs* down and
  *results, traces* up, minutes at a time.
- **The gate loop.** The pull request and the gates, *checks run* down and
  *red, again* up, until it is green. Both of these close inside the machine
  half of the picture and neither of them needs a person.
- **The feedback loop**, the large one, twice a day and 45 minutes long. `main`
  to TestFlight to **my iPhone**, then Georg, then Claude, then back into the
  issues. Its four edges are drawn brighter and heavier than everything else,
  because it is the loop that a person is standing in.

**The crossing.** A simulator has no headroom, so no gate can judge the glow.
That question leaves the machines and goes to a person — the brightened edge
from My iPhone to Georg.

Two phones, deliberately distinct. The **debug phone** is an old iPhone
tethered to the laptop, where agents install debug builds and read the widget
trace; it sits inside the test loop. **My iPhone** runs TestFlight and is
where the app is actually lived with; it sits inside the feedback loop.

**The glow is judged on Georg's own phone, never on the debug phone.** That is
why the emphasised edge runs from My iPhone up to Georg, and why the debug
phone only sends results back to the agents. The debug phone verifies what can
be measured; the glow is not one of those things.

**Testing is a group, not a node.** The simulators on the laptop and the debug
phone are two kinds of the same thing, so they share a container: dozens of
runs with no hardware on one side, one real device on the other. Both take
work from the agents and send results back.

**GitHub is a place, not a step.** The code lives there, so it is the tallest
element on the map: a container holding Issues, the pull request, the gates
and `main`. Work leaves it for the agents and comes back, and two of the
three loops close inside it. The plan for a change lands in the issue's own
comments, which is why the Claude tile says so.

**Two words for the agents, not five.** The map says **Claude** and **Codex**
and nothing finer. Which Claude or which Codex model is running is a decision
that changes by the week — Fable, Opus, Terra were all on this map at one point
— and a drawing that has to be redrawn when a model is swapped is a drawing
that will go stale. The tiles say what each vendor's model does here: Claude
plans the change in the issue and writes most of the code, Codex takes the
heavy implementation and the cheaper long sessions.

**Claude appears twice, on purpose.** Once in the feedback loop, where it
interviews Georg and writes the issues, and once in the agents group, where it
plans and codes. Two different jobs in two different loops, and the group
headers are what tell them apart.

Drawing rules, after several rounds of review:

- **Straight lines only**, single horizontal or vertical runs with one elbow
  where a column change is unavoidable.
- **The site's own type sizes, nothing invented.** 17px for a node's name and
  15px for everything else, both taken from `Body Copy` and the site's
  caption and nav styles. For those numbers to be literal, the SVG is drawn
  one to one with the column it sits in: the viewBox is `10 0 940 720`,
  cropping 10px of slack from each side of a 960-wide coordinate space so the
  drawing renders at exactly 940. If the column width ever changes, change
  the viewBox width to match or the type will no longer be 17 and 15.
- **Three columns of nodes, two of them grouped.** At 17 and 15 in a 940px
  column, the left stack, the GitHub container and the right-hand containers
  are what fits — and the labelled edges need roughly 100px of corridor
  between them. Depth beyond that is bought with nesting, not with more
  columns.
- **Every edge is labelled**, and the label sits along the edge rather than
  inside a tile. This is what sets the corridor widths: the columns are sized
  so that a two- or three-word label fits between them without touching
  either side.
- **The loops are named** at the foot of each half, each with its cadence, and
  the large loop is drawn in a brighter stroke so it reads as one ring rather
  than four separate arrows.
- **Group headings are centred** over their containers.
- **Marks, not emoji**, except for Georg, who is an emoji by request. Both
  Claude tiles carry the Claude mark, Codex the OpenAI mark, and the
  container the GitHub mark. The device icons are SF Symbols too:
  `iphone`, `laptopcomputer.and.iphone` and `macwindow`, which sits
  outside Apple's licence for them, the same call made for the widget's icons.
- **No crossings.** The layout is chosen so that no two edges cross. The one
  that forced it was the red return from the gates: sent back to the agents it
  has to cross the corridor twice, so it is drawn where it actually lands — on
  the pull request, as another commit — which turns a crossing into a visible
  loop.

## The 10,000-character cap

Every Webflow custom-code block, this embed included, caps at 10,000
characters, and the map has been over it twice. Two things bought the room
back, both worth keeping:

- The Claude mark is declared once in `<defs>` and placed with `<use>`, rather
  than repeating a 104-character CDN URL at every tile that carries it.
- `text-anchor` is a class (`.m` for middle, `.e` for end) rather than an
  attribute on each of the 40-odd labels.

The GitHub mark used to be an inline path of about 830 characters; it is now
an uploaded PNG like the others. Brand SVGs are rasterised with
`qlmanage -t -s 192` by rendering **black on white** and then inverting
(`alpha = 255 - luminance`), because QuickLook renders white-on-white.

Assets in use, under
`https://cdn.prod.website-files.com/620d05babdddc967daa0780a/`:

| File | Drawn at |
| --- | --- |
| `6aa5c2d5ec475c215f50ebd9_gu-logo-claude.png` | 26 × 26 |
| `6aa5c2d5c46b3e61cedcc6ea_gu-logo-openai.png` | 26 × 26 |
| `6aa5c72066e38c411ad07ca0_gu-logo-github.png` | 26 × 25 |
| `6aa5bc845f5e745c5ce6e8fd_gu-sym-iphone.png` | 22 × 26 |
| `6aa5bc84d2239e4e497dd198_gu-sym-laptopcomputer-and-iphone.png` | 34 × 21 |
| `6aa5c72066e38c411ad07c82_gu-sym-macwindow.png` | 30 × 22 |

SF Symbols keep their own aspect ratio, so each is drawn at the ratio of the
pixels that came out of the renderer; giving them a square box distorts them.

## The Figma source

`https://www.figma.com/design/2f1FOh6vW6BT04slOANEA3` — "Glow Up — agent
workflow map", in the ME team's drafts. The frame is 940 × 720 and rebuilds the
embed one to one: same coordinates, same two type sizes, the real marks as
image fills. Each of the three containers holds its own tiles, so a container
drags as one unit; the arrows are plain vectors rather than connectors, so a
tile that moves leaves its arrows behind. A Spec frame beside the map carries
the width, type and colour notes.

It is a scratchpad for trying arrangements, not the source of truth — this
directory still is. A change made in Figma has to be written back into
`embed.html` by hand.

## The width ceiling is 940px

Measured on the published page, not assumed. The embed's own `max-width` of
960px never applies: the Webflow wrapper it sits in (`.faq`) is 980px wide with
20px of padding on each side, so the column resolves to exactly 940. That is
also why the SVG's viewBox is 940 wide — at any other number the 17px and 15px
type stops being 17 and 15. Widening the map means widening that wrapper, which
moves every other block on the page with it.

## Below 768px

The SVG is hidden and a visually-hidden prose stack takes over, which is also
what a screen reader gets at every width — the map itself is `aria-hidden`.
Keep the two in step: a node added to the picture and not to the stack is a
node that does not exist on a phone.
