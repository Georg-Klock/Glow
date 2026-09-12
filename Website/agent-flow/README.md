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

Edges carry a condition or a cadence rather than nothing: green, red, picked
up, pull request, TestFlight, twice a day.

`embed.html` is the whole thing: an inline `<style>`, one SVG, and a text
stack. No script, no network calls, under Webflow's 10,000-character cap with
about 500 to spare, so keep new copy short. The SVG is `aria-hidden`; the text
stack is the screen-reader copy on a wide screen and becomes the whole picture
below 768px, so the wording only exists once.

Element id on the page: `61c6d399-3896-ca66-3115-2090fd04df8f`, the embed's
`code` setting. Paste the file's contents there after a change, minus the
leading HTML comment.
