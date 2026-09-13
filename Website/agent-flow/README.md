# The agent-workflow map

One HTML Embed on georgklock.com/glow-up, above the "Agentically built" item
(page `6a88c6481cb44deb7e573ab2`, element `61c6d399-…`). The current drawing was
laid out by Georg in Figma (node 4:2 of the file below) and implemented from
there; the coordinates in `embed.html` are that node's coordinates, so the two
can be diffed.

**Four panels, read anticlockwise.** *Human reacts* on the left, *GitHub* in the
middle, *Agents work all Night* on the right with a nested *Swift Code* group
holding the two test machines. Work leaves GitHub for the agents, comes back as
a tested pull request, passes the gates, merges to main, and ships to the phone
each morning — which closes the one loop a person is in.

**The type scale here is 15 and 12**, not the site's 17 and 15. The tiles are
150px wide in this layout and the site's sizes do not fit them. 12px is not on
the site's scale, so it is a deliberate exception rather than a number to copy
elsewhere; grey #8f8f8f on the #151515 tile measures 5.65:1, which clears AA.

**The edges are the subject, not the tiles.** Every arrow carries the name of
the interaction it stands for — *writes issues*, *prompts the agents*, *pulls in
the issue backlog*, *tested builds, PR to main*, *Agents tests as they build*,
*ships the latest build to my phone each morning*. An unnamed arrow says two
things are connected; a named one says how.

**Two phones, deliberately distinct.** The **Debug Phone** is an old iPhone
tethered to the laptop, tested against by the agents all night. **TestFlight on
my iPhone** is where the app is actually lived with. The glow is judged on
Georg's own phone and never on the debug phone — that is the whole reason the
left panel exists.

**GitHub is a place, not a step.** The code lives there, so it is the tallest
element on the map: a container holding Issues, the pull request, the gates and
main. Work leaves it for the agents and comes back.

**Two words for the agents, not five.** The map says **Claude** and **Codex**
and nothing finer. Which model is running changes by the week — Fable, Opus and
Terra have each been on this map inside a day — and a drawing that has to be
redrawn when a model is swapped is a drawing that will go stale. Terra is a
Codex model; Sonnet is a Claude one. The tiles say what each vendor's models do
here rather than naming them.

**Claude appears twice, on purpose.** Once on the left, where the lower models
interview Georg and write the issues, and once in the agents panel, where the
higher models plan and the lower ones code.

Drawing rules, after several rounds of review:

- **Straight lines only**, single horizontal or vertical runs with one elbow
  where a column change is unavoidable.
- **Headings stay at the site's 17px**, and the tiles use 15 and 12 (see
  above). For any of those numbers to be literal, the SVG is drawn
  one to one with the column it sits in: the viewBox is `0 0 940 752`,
  matching the Figma frame one to one so the
  drawing renders at exactly 940. If the column width ever changes, change
  the viewBox width to match or the stated sizes stop being literal.
- **Three columns of panels.** The labelled edges need roughly 90px of
  corridor between them. Depth beyond three columns is bought with nesting —
  the testing group sits inside the agents group — not with more columns.
- **Every edge is labelled**, and the label sits along the edge rather than
  inside a tile. This is what sets the corridor widths: the columns are sized
  so that a two- or three-word label fits between them without touching
  either side.
- **The panels are named** above themselves, centred, and the naming carries
  the cadence: *all Night* against *each morning*.
- **Group headings are centred** over their containers.
- **Two corner radii and one inset.** Outer containers are 28, inner tiles 18,
  and every tile sits 10px inside its container on each side it touches, with
  5px between siblings. The tiles carry no stroke — the fill step from #0e0e0e
  to #151515 is what separates them. Because the containers keep the heights
  from the Figma file, honouring a 10px inset makes the tile heights differ
  slightly between groups: 111 in the left and agent groups, 106 in the testing
  group, 96 in the GitHub column.
- **Arrows are white at two opacities**, not two colours. Full strength for the
  three edges a person is on — writes issues, tested builds back to the pull
  request, and the build shipping to the phone — and 40% for the machine
  traffic. That is how the Figma file does it: one white stroke, `opacity` on
  the node. In SVG the element's `opacity` dims its marker too, so both weights
  share a single arrowhead definition.
- **The shared top rail is two paths, not one.** The grey rail and the white
  branch overlap from the Claude tile up and along to the branch point; drawing
  them separately with the white last is what puts the white on top, the same
  as the file.
- **Marks, not emoji**, except for Georg, who is an emoji by request. Both
  Claude tiles carry the Claude mark, Codex the OpenAI mark, the middle panel
  the GitHub mark, and the Swift Code heading the Swift bird. The device icons
  are SF Symbols — `iphone`, `laptopcomputer.and.iphone` and `macwindow` —
  which sits outside Apple's licence for them, the same call made for the
  widget's icons.

  Two of those sit in 26×26 boxes in the Figma file with the glyph hanging
  over the edge. The implementation keeps the glyph's own size (30×22 and
  34×21) and drops the clip, because clipping an SF Symbol cuts its corners.
- **No crossings.** The layout is chosen so that no two edges cross.
- **One arrowhead shape**, an open chevron, drawn as a single SVG marker at
  `markerUnits="userSpaceOnUse"` so it does not scale with the 2px stroke.
- **Elbows are rounded to 15px**, the per-vertex corner radius set on the
  Figma vectors. SVG has no corner-radius on a polyline, so each turn is a
  quarter-arc written into the path — `L233 69 A15 15 0 0 1 248 54`. Every
  turn on this map is clockwise on screen, so the sweep flag is 1 throughout.
  The two paths Figma overlaps on the shared top rail are merged into one
  rail plus a branch that peels off it with its own arc, which draws the
  same picture in fewer characters.
- **Nothing below the map.** The explanatory caption that used to sit under
  it is gone; the picture carries its own labels and the paragraph beneath
  the embed says the rest.

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
| `6aa5dff443db9787bc13897d_gu-logo-swift.png` | 24 × 22 |

SF Symbols keep their own aspect ratio, so each is drawn at the ratio of the
pixels that came out of the renderer; giving them a square box distorts them.

## The Figma source

`https://www.figma.com/design/2f1FOh6vW6BT04slOANEA3` — "Glow Up — agent
workflow map", in the ME team's drafts. Node 4:2 is the live layout at 940 × 752;
the frame rebuilds the embed one to one: same coordinates, same two type sizes, the real marks as
image fills. Each of the three containers holds its own tiles, so a container
drags as one unit; the arrows are plain vectors rather than connectors, so a
tile that moves leaves its arrows behind. A Spec frame beside the map carries
the width, type and colour notes.

Figma is where the layout is decided and this directory is what ships. A change
made there has to be written back into `embed.html` by hand — read the node
with `get_design_context`, then take exact geometry off the vector networks
with `use_figma`, because the exported reference code rounds and duplicates.

## The width ceiling is 940px

Measured on the published page, not assumed. The embed's own `max-width` of
960px never applies: the Webflow wrapper it sits in (`.faq`) is 980px wide with
20px of padding on each side, so the column resolves to exactly 940. That is
also why the SVG's viewBox is 940 wide — at any other number the 17px and 15px
type stops being 17 and 15. Widening the map means widening that wrapper, which
moves every other block on the page with it.

## The copy under the map has to agree with it

The "Agentically built" block below the embed is separate Webflow copy, and it
drifted the moment the map changed: it still named Sonnet after the map had
moved to vendor-level names, and it still said morning *and* evening after the
map said each morning. Neither is visible from inside the embed, so nothing
catches it.

The elements, so the next pass does not have to hunt for them. The body is one
`Body Copy` paragraph, `03864b86-…`, whose lines are separate String children
separated by breaks — `set_text` on the paragraph itself would flatten those,
so write each String child instead. Its lines are `3a716e4a-…` (the setup),
`f744b55c-…43` (the morning slot) and `c5a47560-…aa` (how a change travels).
The kicker beside the heading is `19b9d9c5-…36`, inside span `7349ee17-…`.
The two contact lines after them are not ours to touch.

**Match the vocabulary, not just the facts.** The map says Claude and Codex,
Issues one per change, one branch per change, the suite and CI, merges when
green. The paragraph now uses those same words, so a reader moving from the
picture to the prose is not asked to learn two names for one thing.

## Below 768px

The SVG is hidden and a visually-hidden prose stack takes over, which is also
what a screen reader gets at every width — the map itself is `aria-hidden`.
Keep the two in step: a node added to the picture and not to the stack is a
node that does not exist on a phone.

## Spacing audit, 2026-09-12

Measured on the published page at a 1487px viewport, ink edge to ink edge.

**The page has three content columns, not one.** All three are centred on the
same axis, so the mismatch shows as ragged left and right edges between
sections rather than as anything being off-centre.

| Block | Width | Left edge | Set by |
| --- | --- | --- | --- |
| Page heading | 980 | 254 | `.section-heading` max-width 980 |
| Stats, hero widget, body copy, widget stills | 960 | 264 | `.section` max-width 960 |
| App Store stills | 980 | 254 | `.project-image` max-width 980, uncapped inside `.video-section` |
| This map, FAQ items | 940 | 274 | `.faq` 980 wide with 20px of side padding |

**And no single vertical unit.** The gaps between blocks, in document order:
40, 40, 64, 88, 34, 128, 130, 56, 156. Two things cause most of it.
`.project-image` carries `padding: 24px 0` *and* a stray `margin-bottom: 10px`,
which is why the gap below a stills row (34) is less than half the gap above it
(88). And each container spaces its children differently: `.section` uses
`padding-bottom`, `.faq` uses `row-gap: 56`, `.video-section` uses `padding: 40`.

**What was fixed here:** this embed's own canvas. The Figma frame is 752 tall
but the drawing ends at 623, so the map was shipping 130px of empty SVG that
padded the page. The viewBox is now `0 0 940 651` — 28px of slack above the
first ink and 28px below the last, matched.

**What was not:** every other number above comes from a class shared with five
other project pages (`.section`, `.section-heading`, `.project-image`,
`.video-section`) or, for `.faq`, with one. Changing them here changes them
everywhere, and several carry larger-breakpoint overrides on top of their base
values — the live `.faq` reads 980 while its base is 960. That is a decision
about the portfolio's layout system, not about this page, so it is written
down rather than applied.
