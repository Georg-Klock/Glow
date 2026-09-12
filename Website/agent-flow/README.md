# The agent-workflow map

One HTML Embed on georgklock.com/glow-up, above the "Agentically built" item.
It replaced a linear strip of six cards, which drew the process as a waterfall
with a loop caption. The system is not a line, so the map draws what it is:

- **The machine loop**, minutes, around the clock, with no person in it.
  Issues, then the agents, then the gates, then `main`, then the debug phone,
  and back to the agents. The agents are a cluster, not a box: **Fable** reads
  the issue and plans the change, **Codex** takes the heavy implementation when
  it is heavy, and that hand-off is a conditional edge rather than a stage.
- **The human loop**, twice a day. `main` to TestFlight to **my iPhone**, then
  Georg, then Sonnet, then back to the issues.
- **The crossing.** A simulator has no headroom, so no gate can judge the glow.
  That one question leaves the debug phone and goes to a person, drawn as the
  only dashed line and the only thing that crosses the middle of the picture.

Two phones, deliberately distinct. The **debug phone** is an old iPhone
tethered to the laptop, where agents install debug builds and read the widget
trace; it sits inside the machine loop. **My iPhone** runs TestFlight and is
where the app is actually lived with; it sits inside the human loop.

**The glow is judged on Georg's own phone, never on the debug phone.** That is
why the emphasised edge runs from My iPhone up to Georg, and why the debug
phone only sends traces. The debug phone verifies what can be measured; the
glow is not one of those things.

**GitHub is a place, not a step.** The code lives there, so it is the tallest
element on the map: a container holding Issues, the pull request, the gates
and `main`. Work leaves it for the agents and comes back. Fable's plan lands
in the issue's comments, which is why its tile says so.

**Sonnet writes twice.** It interviews Georg and then produces both the GitHub
issues and the prompts the agents run, so it has an edge into GitHub and a
second one, along the top, into the agent cluster.

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
- **Two type sizes is also the limit of the columns.** At 17 and 15 in a 940px
  column there is room for four columns, not six: the left pair, Sonnet,
  GitHub, and the agents. More columns would mean smaller type.
- **The loops are named** at the foot of each half: the review loop and the
  build loop, each with its cadence.
- **Marks, not emoji**, except for Georg, who is an emoji by request. Sonnet
  and Fable carry the Claude mark, Codex the OpenAI mark, and the container
  the GitHub mark. The GitHub path is inline; the other two were rasterised
  white from their official SVGs and uploaded as assets, because inlining all
  three would have blown the 10,000-character cap. The two device icons are
  SF Symbols, `iphone` and `laptopcomputer.and.iphone`, which sits outside
  Apple's licence for them, the same call made for the widget's icons.
- **Few labels.** Only the ones carrying a condition or a cadence survive.
