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

## On the site, 2026-09-11

It is live on georgklock.com/glow-up, in a new `.section.centered` directly
under the headline block, and it is in **three pieces**, because Webflow caps
every custom-code block at 10,000 characters and the one-block embed is 44 KB:

| Where | What | Size |
| --- | --- | --- |
| Page settings → head code | `webflow/head.html` — the CSS and the `@font-face` | 5.0 K |
| An HTML Embed element in the section | `webflow/embed.html` — the markup, with `data-manifest` naming the JSON asset | 1.9 K |
| **Site** settings → footer code | `webflow/footer.html` — the script, comments stripped | 13.4 K |
| Asset `gw-manifest.json` | `webflow/gw-manifest.json` — manifests, icon outlines and the name→URL map, fetched once at load | 32 K |
| 112 assets `gw-*.avif` | the plates, byte-identical on the CDN (spot-checked), served `image/avif` | 199 K |
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

## No halo, and a grey card (2026-09-11, second cut)

The first cut carried the word slider's halo and sat on a `#000000` card. Both
went on review: the halo read as a drop shadow on every emitting mark and
letter, and a black card looked nothing like the widget in the screenshots
beside it. The plates are now cut with `--halo-strength 0 --grain-depth 0
--pad 0.08` — the shape and a two-pixel antialiased edge, nothing else — and
the card is `#202020`, the mode of the widget's material over a dark
wallpaper measured on the App Store frame (28–32). A PQ plate carries no
alpha, so the plates are cut with that same grey as their surround
(`--surround 202020`); decoded through libavif the surround comes back at
2.93 nits, which is exactly sRGB 32 at 203-nit white, so the browser lands it
on the card's own colour. The card must never change colour without the
plates being re-cut, and `tuning.html` (the halo variants) is now history.

## Verified, 2026-09-11

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
