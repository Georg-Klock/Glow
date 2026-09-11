# This Week hero for the project page

A browser recreation of the app's week grid, scaled up, as a Webflow embed.
Today's open marks, the name and icon of a habit still open today, and today's
weekday letter **physically glow** on a screen with headroom, by the technique
in `docs/glow.md`: the emitting tier is a set of PQ-encoded AVIF plates with
the halo baked in, shown over live CSS twins. Everything else — the lit
`#D9D9D9` marks and text, the sockets, the ✕ — is ordinary CSS and SVG.

Clicking an open ring marks it done, live, in the visitor's browser: the glow
goes, the mark and its label drop to the lit tier, and when the last open mark
of the day goes so does the weekday letter. Nothing is stored or sent.

## What is here

| Path | What |
| --- | --- |
| `embed.html` | **The deliverable.** One block of CSS + HTML + JS for a Webflow Custom Code embed. Built; do not edit. |
| `embed.template.html` | The source of the above. Edit this, then rebuild. |
| `build-embed.py` | Inlines the plate manifests and icon outlines into the template. |
| `assets/<tier>@<dpr>x/*` | The plates, one per headroom step, with a shape mask each; the icon masks; the missed mark. 1095 files, 1.6 MB. Upload these. |
| `assets/<set>/manifest.json` | Every plate's size and offset in CSS pixels, from the renderer. |
| `fonts/Inter-Regular.{otf,woff2}` | The one font (Inter 4.1, OFL). The plates were cut with the `.otf`; the page loads the `.woff2`. |
| `icons/*.svg` | The first cut's Phosphor outlines; no longer used, kept for the record. The icons are now SF Symbols rendered by the generator. |
| `preview.html` | The embed on a plain page for a local server, with test hooks (below). |
| `tuning.html`, `tuning/` | The first cut's halo variants; history. |
| `webflow-asset-map.py` | Maps plate file names to the hashed URLs Webflow serves them from. |

The renderer and the verifier live with the app's other tools:
`Tools/make-week-plates.swift` and `Tools/check-week-plates.swift`.

## On the site, 2026-09-11

It is live on georgklock.com/glow-up, in a new `.section.centered` directly
under the headline block, and it is in **three pieces**, because Webflow caps
every custom-code block at 10,000 characters and the one-block embed is 44 KB:

| Where | What | Size |
| --- | --- | --- |
| Page settings → head code | `webflow/head.html` — the CSS and the `@font-face` | 6.6 K |
| An HTML Embed element in the section | `webflow/embed.html` — the markup, with `data-manifest` naming the JSON asset | 0.5 K |
| **Site** settings → footer code | `webflow/footer.html` — the script, comments stripped | 18.6 K |
| Asset `gw-manifest.json` | `webflow/gw-manifest.json` — manifests, icon outlines and the name→URL map, fetched once at load | 216 K |
| 1096 assets `gw-*` | the plates at every step, their masks, the missed mark, the glass; byte-identical on the CDN (spot-checked) | 1.6 M |
| Custom font `Inter` | `fonts/Inter-Regular.woff2`, family name `Inter` | 111 K |

The script is site-wide only because the page-level footer is also capped at
10,000; it returns at once on any page without `#gw`. The upload used the
Webflow MCP's `create_asset` plus a multipart POST; note that the assets API
returns its S3 fields in camelCase (`xAmzSignature`, `policy`,
`successActionStatus`) and S3 wants them spelled `X-Amz-Signature`, `Policy`,
`success_action_status` — the first 28 uploads came back 403 until renamed.

**To change it**, edit `embed.template.html`, then:

```bash
python3 Website/week-widget/build-embed.py --webflow --asset-map private/week-widget-asset-map.json --asset-base "https://cdn.prod.website-files.com/620d05babdddc967daa0780a/" --font-url "<Inter hostedUrl>" --manifest-url "<gw-manifest.json hostedUrl>"
```

and paste `webflow/head.html` and `webflow/footer.html` over the two code
blocks. Re-cut plates need re-uploading, a fresh map, a fresh manifest asset,
and a new `data-manifest` URL in the embed. `webflow/preview.html` serves the
same three blocks from a local server, which is where a change is checked
first.

Verified on the live page in Chrome 152 on the XDR: HDR true, 31 plates
ready, Inter loaded, a click on today's Gratitude ring goes to done and undo
restores it, no console errors.

### Doing it by hand instead

1. **Upload the plates.** Every file under `assets/*/`; names are unique across
   tiers. Webflow keeps an AVIF byte-identical and generates no variants, but
   only at the raw asset URL — never through an Image element, which emits a
   `srcset` of re-encoded SDR copies.
2. **Map the URLs.** Webflow prefixes each upload with a hash:

   ```bash
   python3 Website/week-widget/webflow-asset-map.py --site <site id> --token "$WEBFLOW_TOKEN" > private/week-widget-asset-map.json
   ```

3. **The font.** Site settings → Fonts, `Inter-Regular.woff2` as family
   `Inter`, or host the `.woff2` and pass `--font-url`. The plates and the live
   text **must** be the same cut of the same font, or the emit→lit swap jumps.
4. **Build** with `--webflow`, upload `webflow/gw-manifest.json` as an asset,
   rebuild with its URL as `--manifest-url`, and paste the three blocks.
5. **Look at it on a screen with headroom**, in Chrome and in Safari.

Without a map, the one-block `embed.html` expects `<asset base>/<set>/<file>`
— the layout of `assets/` here — which suits any host that keeps file names
and has no size cap.

## How the page decides what to show

- **Tier.** Three discrete sizes, because a plate is a fixed raster: desktop
  (≥ 960px viewport, 48px cell), tablet (600–959px, 36px), mobile (< 600px,
  21px). Every other dimension is the app's `WidgetMetrics` / `SlotLayout` /
  `GlowShape` number times one scale, so the ratios survive.
- **Density.** Plates exist at desktop 1x and 2x, tablet 2x, mobile 3x. The
  page takes the smallest density not below the screen's, else the largest.
  A 3x plate on a 2x phone is a 1.5x downscale, which the word slider measured
  as acceptable; a 1x plate on a 2x screen is not offered.
- **Headroom.** `matchMedia('(dynamic-range: high)')` gates every fetch: a
  screen without it never loads a plate and shows the emitting tier as plain
  `#FFFFFF`, the lit tier as `#D9D9D9`. That query answers for the display, not
  the decoder, so each plate also has to `load` with a non-zero natural width
  before it is shown; an `error` or an empty decode leaves the live twin in
  place, with no broken-image icon.
- **Today** is the visitor's local weekday, Monday first. The daily rows'
  history is seeded relative to it (done, with one missed day each); the
  weekly rows carry a fixed completion pattern filtered to the past. The
  placement of every row is `WeekSpans.dividedWithoutRestDay` and
  `assignColumns` ported to JavaScript (`docs/week-marks.md` §4), without
  creation credit, rest days or bonuses. Every open mark is clickable, weekly
  ones included, because the app's invariant 7 means completing today never
  moves a future window — the row is simply redrawn. A midnight timer
  re-seeds.
- **Tilt** runs only under `(hover: hover) and (pointer: fine)` and not under
  `prefers-reduced-motion`: ±7°, eased at 5.5% per frame, shadow shifting
  against it.

## What the source says that the brief did not

The brief was written without the app's source; the source is what this
matches, so three things differ from its wording:

- **A done mark is a full lit disc** (or capsule across days), not a small
  dot — `SlotMarkView.doneMark`: the `#D9D9D9` fill inset 1pt, a white rim at
  the top, a 30% black one at the bottom, a quarter-cell well.
- **The missed ✕ is a recessed well shaped like a cross**, not a resting-grey
  glyph — `CrossShape` filled 15% black with three inner shadows. The resting
  step belongs to the rest-day cut, which is not in this demo.
- **The socket is lit from above**: black bevel on the top edge, 13% white on
  the bottom. On `#000` only the bottom rim shows, as on the This Week screen.

Two things follow the brief rather than the app: the eight rows have no spacer
rows between groups (the app's seed list has two), and the week starts on
Monday, where the app makes it a setting.

## The third cut (2026-09-11): SF Symbols, masks, a slider, the glass

On review after the second cut, four more things changed, and one of them
changed the shape of every plate.

- **Every plate is clipped to its own shape with a CSS mask.** A PQ file has to
  carry an opaque surround, and the second cut relied on that surround being
  the card's exact grey. It is, on a screen with headroom — and on a screen
  without one the browser tone-maps the PQ grey to something darker, so every
  emitting mark and word wore a darker rectangle. The generator now writes an
  alpha PNG of each plate's shape at the plate's exact pixel size, and the
  page applies it with `mask-image`, so the surround never reaches the screen
  on any display. That also freed the card to carry a texture.
- **1x is a plate too.** Sliding between 1x and 2x used to cross-fade the 2x
  plate over the live CSS text, and the two are rasterised differently (the
  browser and CoreText), so the letters appeared to move. Every headroom step
  from 1x to 8x is now a plate — the 1x one written as Display P3, exactly SDR
  white — and the live text never mixes in on a screen with headroom.
- **The icons are the app's SF Symbols**, rasterised by AppKit from the same
  symbol names as `DefaultHabits`, at `WidgetMetrics.iconSize`. The lit tier
  is an alpha mask of the symbol painted through `mask-image`, so both tiers
  share one outline. SF Symbols are licensed for Apple platforms; putting them
  on the web was asked for and is the owner's call.
- **The ✕ is the app's own.** An SVG-filter rebuild of `CrossShape`'s three
  inner shadows came out flat and soft next to the real thing, so the
  generator renders the app's SwiftUI code (copied into it, with a pointer to
  `SlotMarkView`) through `ImageRenderer` into a PNG with alpha, per tier.
- **The slider.** Below the card, 1x to 8x (`GlowSettings.range`), default 2x.
  Between two steps the upper plate fades in over the lower; both are masked to
  the same shape, so nothing else changes. Hidden on a screen without headroom,
  where there is nothing to slide.
- **The glass.** The card's background is the widget's material over the
  wallpaper, lifted from the App Store frame: the pixels between rows, in the
  spacer rows and the margins are the material; everything else is inpainted
  from them (`Website/week-widget/assets/gw-card-glass.jpg`, from the
  reconstruction in this session's history — a smooth gradient, 61 at the top
  to 40 at the bottom with a faint blue cast top-right). `--card: #202020`
  stays beneath it as the fallback.

Plates: 3 sets × 8 steps × 28 = 672 AVIF, plus 84 shape masks, 24 icon masks
and 3 missed marks; 1.2 MB in total, fetched lazily as the slider asks for a
step. `Tools/check-week-plates.swift` accepts the 1x floor as SDR by design.

## The fourth cut (2026-09-11): one slider for the card and the sentence

The page used to carry two demonstrations of the same trick, each with its
own control: the word slider ("An HDR image can be brighter than white.",
`Tools/make-glow-word.swift`, twelve steps) in the centered section, and the
hero with its own eight-step slider in a section of its own. They are one
thing now.

- **The sentence sits under the card**, inside the hero, as twelve stacked
  `<img>` layers of the page's existing word files (the hashed CDN names are
  in the script, `SENTENCE_FILES`; nothing was re-rendered or re-uploaded).
  It is sized like the site's "Larger Text" style — the images were rendered
  at 144pt into 2690px, so 32px of type is a 598px stage, 486 / 318px on the
  tablet and phone breakpoints and 68.2vw below 479px — smaller than the old
  960px stage, still the largest type on the page after the headline.
- **One range, 1x to 12x.** The plates were re-cut for the four steps above
  8x (`--gains 1,…,12`; 336 new files, verified with libavif like the rest),
  so the card and the sentence answer the same value. Between two whole steps
  the upper plate and the upper sentence layer fade in over the lower.
- **It sweeps on a loop.** 1x up to 12x and back, 5.2 s a pass, eased at both
  ends (the word slider's timing). A drag takes over; the loop resumes from
  where the visitor left it after four seconds without input. It stops while
  the tab is hidden, holds at 12x under reduced motion, and never starts on a
  screen without headroom, where the slider is hidden and only the 1x sentence
  file is fetched.
- **Every step is fetched up front** once the plate path opens, so the first
  pass never meets a plate mid-load and shows the live twin for a frame. One
  tier at one density is about 550 KB across 12 steps.
- **The sentence sits above the card** (moved there on review), the slider
  below it.
- **The card is always the same Thursday.** `today` used to be the visitor's
  weekday, re-seeded at midnight; the demo now pins Thursday so the picture is
  the one that was reviewed: five habits open, Thursday's letter the only one
  emitting, and Workout, VO2 Max and Tutorial already logged today
  (`doneToday` in the seed) — a lit disc, name and icon lit rather than
  emitting, the tier the app gives a completion. Clicking a done mark undoes
  it, and clicking an open ring completes it and drops its row to lit, as
  before.
- **The page tree.** The hero embed moved into the centered section in place
  of the old word-slider embed, ahead of the "if the text above doesn't glow"
  note; the empty section and paragraph went. The Dynamic Island video moved
  into the two-frame row beside the open-close video and the widgets shot
  (`.project-image.shot-widgets` is the same flex row as the three-frame
  setup row below it), and its own section went.

## Verified, 2026-09-11 (third cut)

| Check | Result |
| --- | --- |
| Strict decoder | All 112 plates pass `avifdec` 1.4.2: even dimensions, 10-bit, YUV 4:2:0, primaries 9, transfer 16 (PQ), no alpha |
| Decoded peak | 428–440 nits, 2.09–2.17× SDR white, via libavif's own 16-bit decode; the ~8% over the requested 2× is the PQ round trip already measured for the word slider |
| HDR display, Chrome 152 on the MacBook's XDR | `(dynamic-range: high)` true; 31 plates loaded and shown; a real click on today's Gratitude ring turns it into a done disc, drops the name and icon to lit, and the F letter drops once the last open mark of the day is done; undo restores it |
| Emit → lit swap | Plate and live twin compared at 4× for the name, the icon, the letters and the ring: same position, same size |
| Seam | None: the first capture showed ring plates clipping the sockets beside them and the rows above and below; fixed by paint order, re-captured clean |
| SDR fallback | `preview.html?sdr`: no plate fetched, emitting tier renders `#FFFFFF`, lit `#D9D9D9`, same layout and interaction |
| Decode failure | `preview.html?corrupt` (truncated AVIF) and `?missing` (404): the affected plates flag broken, their live twins show, the other 27 stay lit |
| Tiers | Card 676px at desktop, 507px at 760px viewport, 296px at 375px with no horizontal scroll |
| Tilt | Off under touch emulation; on with a fine pointer, transform and shadow follow the cursor |
| Network | After load, interaction makes no request |

**Not verified here, and needed before this ships:** the glow judged by eye on
the XDR (a capture cannot show it), Safari at all, and the ring's halo
setting above. Both browsers on a screen with headroom is the check that
matters, and it is a person's.
