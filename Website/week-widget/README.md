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
| `assets/<tier>@<dpr>x/*.avif` | The plates. 112 files, ~200 KB. Upload these. |
| `assets/<set>/manifest.json` | Every plate's size and offset in CSS pixels, from the renderer. |
| `fonts/Inter-Regular.{otf,woff2}` | The one font (Inter 4.1, OFL). The plates were cut with the `.otf`; the page loads the `.woff2`. |
| `icons/*.svg` | Phosphor (MIT) outlines, plus a hand-drawn `play-rectangle`. Used by the renderer and inlined into the page. |
| `preview.html` | The embed on a plain page for a local server, with test hooks (below). |
| `tuning.html`, `tuning/` | The open ring cut at six halo settings, for a decision on an HDR screen. |
| `webflow-asset-map.py` | Maps plate file names to the hashed URLs Webflow serves them from. |

The renderer and the verifier live with the app's other tools:
`Tools/make-week-plates.swift` and `Tools/check-week-plates.swift`.

## Putting it on Webflow

1. **Upload the plates.** Drag every file under `assets/*/` into the Asset
   Manager. Names are unique across tiers (`gw-desktop-2x-ring-1.avif`), so
   they can all go in one folder. Webflow keeps an AVIF byte-identical and
   generates no variants (measured for the word slider), but only at the raw
   asset URL — never place these through an Image element, which emits a
   `srcset` of re-encoded SDR copies.
2. **Map the URLs.** Webflow prefixes each upload with a hash, so the page
   cannot derive a plate's address from its name:

   ```bash
   python3 Website/week-widget/webflow-asset-map.py --site <site id> --token "$WEBFLOW_TOKEN" > private/week-widget-asset-map.json
   ```

   The token needs `assets:read` only. Keep the map out of the repo; it is a
   list of one site's CDN paths.
3. **The font.** Either add `fonts/Inter-Regular.woff2` under Site settings →
   Fonts as a custom font named `Inter` and build with `--font-url ""`, or host
   the `.woff2` somewhere and pass its URL. The page's stack is
   `'GW Inter', 'Inter', system-ui`. The plates and the live text **must** be
   the same cut of the same font, or the emit→lit swap jumps.
4. **Build and paste.**

   ```bash
   python3 Website/week-widget/build-embed.py --asset-map private/week-widget-asset-map.json --font-url "https://…/Inter-Regular.woff2"
   ```

   Paste `embed.html` into an Embed element. It is self-contained: the only
   requests it makes are for the plates it will show and the font.
5. **Publish to staging and look at it on a screen with headroom**, in Chrome
   and in Safari. A screenshot cannot show the glow; only the screen can.

Without a map, the embed expects `<asset base>/<set>/<file>` — the layout of
`assets/` here — which suits any host that keeps file names.

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

## Open: the ring's halo

The halo numbers (`radius 0.155 × cell`, `strength 0.085`, `grain 0.22`
multiplied, `softness 1.6`) are the word slider's, judged on letterforms. The
ring is a far thinner shape and nobody has yet looked at it lit. `tuning.html`
shows six cuts side by side; open it from a local server on a screen with
headroom, choose, and re-cut all four sets with the chosen values:

```bash
swift Tools/make-week-plates.swift --out Website/week-widget/assets --font-file Website/week-widget/fonts/Inter-Regular.otf --icons Website/week-widget/icons --halo-radius 0.155 --halo-strength 0.085
swift Tools/check-week-plates.swift --dir Website/week-widget/assets
python3 Website/week-widget/build-embed.py
```

The plates ship at the app's default peak, `--gain 2` (`GlowSettings.defaultValue`).

## Verified, 2026-09-11

| Check | Result |
| --- | --- |
| Strict decoder | All 112 plates pass `avifdec` 1.4.2: even dimensions, 10-bit, YUV 4:2:0, primaries 9, transfer 16 (PQ), no alpha |
| Decoded peak | 424–440 nits, 2.09–2.17× SDR white, via libavif's own 16-bit decode; the ~8% over the requested 2× is the PQ round trip already measured for the word slider |
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
