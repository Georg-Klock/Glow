# The agent-workflow map

One HTML Embed on georgklock.com/glow-up, above the "Agentically built" item
(page `6a88c6481cb44deb7e573ab2`, element `61c6d399-…`). It replaced a linear
strip of six cards, which drew the process as a waterfall with a loop caption.
The system is not a line, so the map draws what it is:

- **The build loop**, minutes, around the clock, with no person in it. Issues,
  then the agents, then the test machines, then the pull request, then the
  gates, then `main` — and red goes straight back to the agents.
- **The review loop**, twice a day, 45 minutes. `main` to TestFlight to **my
  iPhone**, then Georg, then Sonnet, then back to the issues and the prompts.
- **The crossing.** A simulator has no headroom, so no gate can judge the glow.
  That question leaves the machines and goes to a person, drawn as the only
  brightened line on the map.

Two phones, deliberately distinct. The **debug phone** is an old iPhone
tethered to the laptop, where agents install debug builds and read the widget
trace; it sits inside the build loop. **My iPhone** runs TestFlight and is
where the app is actually lived with; it sits inside the review loop.

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
and `main`. Work leaves it for the agents and comes back. Fable's plan lands
in the issue's comments, which is why its tile says so.

**Four agents, drawn as a 2×2 grid inside one container.** Fable reads the
issue and plans the change, Opus writes most of the code, Codex takes the heavy
implementation, and Terra runs the long sessions where cheaper tokens matter.
They are peers on one job rather than four stages, so no edges are drawn
between them.

**Sonnet writes twice.** It interviews Georg and then produces both the GitHub
issues and the prompts the agents run, so it has an edge into GitHub and a
second one, along the top, into the agent container.

Drawing rules, after several rounds of review:

- **Straight lines only**, single horizontal or vertical runs with one elbow
  where a column change is unavoidable.
- **The site's own type sizes, nothing invented.** 17px for a node's name and
  15px for everything else, both taken from `Body Copy` and the site's
  caption and nav styles. For those numbers to be literal, the SVG is drawn
  one to one with the column it sits in: the viewBox is `10 0 940 680`,
  cropping 10px of slack from each side of a 960-wide coordinate space so the
  drawing renders at exactly 940. If the column width ever changes, change
  the viewBox width to match or the type will no longer be 17 and 15.
- **Three columns of nodes, two of them grouped.** At 17 and 15 in a 940px
  column, the left stack, the GitHub container and the right-hand containers
  are what fits. Depth beyond that is bought with nesting, not with more
  columns, which is why the agents and the test machines sit two-up inside
  their groups.
- **The loops are named** at the foot of each half, each with its cadence.
- **Marks, not emoji**, except for Georg, who is an emoji by request. Sonnet,
  Fable and Opus carry the Claude mark, Codex the OpenAI mark, and the
  container the GitHub mark. Terra carries the `cpu` SF Symbol rather than a
  brand mark, because whose model it is has not been established — replace it
  with the right mark once that is settled. The device icons are SF Symbols
  too: `iphone`, `laptopcomputer.and.iphone` and `macwindow`, which sits
  outside Apple's licence for them, the same call made for the widget's icons.
- **Few labels.** Only the ones carrying a condition or a cadence survive:
  reactions, the glow by eye, prompts for the agents, and red.

## The 10,000-character cap

Every Webflow custom-code block, this embed included, caps at 10,000
characters, and the map has been over it twice. Two things bought the room
back, both worth keeping:

- The Claude mark is declared once in `<defs>` and placed with `<use>`, rather
  than repeating a 104-character CDN URL three times.
- `text-anchor="middle"` is a class (`.m`) rather than an attribute on each of
  the 39 centred labels.

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
| `6aa5c88cdaba644a600e8c11_gu-sym-cpu.png` | 26 × 24 |
| `6aa5bc845f5e745c5ce6e8fd_gu-sym-iphone.png` | 22 × 26 |
| `6aa5bc84d2239e4e497dd198_gu-sym-laptopcomputer-and-iphone.png` | 34 × 21 |
| `6aa5c72066e38c411ad07c82_gu-sym-macwindow.png` | 30 × 22 |

SF Symbols keep their own aspect ratio, so each is drawn at the ratio of the
pixels that came out of the renderer; giving them a square box distorts them.

## Below 768px

The SVG is hidden and a visually-hidden prose stack takes over, which is also
what a screen reader gets at every width — the map itself is `aria-hidden`.
Keep the two in step: a node added to the picture and not to the stack is a
node that does not exist on a phone.
