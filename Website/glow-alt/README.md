# Glow Up · alt — the week widget as a real 3-D object

Live at **<https://www.georgklock.com/glow-up-alt>** (Webflow page id
`6aa89db22eed5a80b7815481`, slug `glow-up-alt`).

The week grid from `/glow-up`, rebuilt in WebGL. The CSS version is a stack of
rounded `<div>`s with inset box-shadows: the sockets look recessed because
someone drew a shadow at the top and a highlight at the bottom, and they stop
looking recessed the moment anything moves. Here the card is a mesh, every
socket is a hole in it, and the light does the rest. Drag it and the pockets
occlude, catch a rim highlight on the near lip and go black on the far wall,
because that is what a hole does.

## What is actually geometry

Everything that has depth:

| Part | How it is built |
| --- | --- |
| The slab | Rounded-rect outline, a filleted top edge, a vertical side wall, a bottom fillet and an underside |
| The top face | One triangulated polygon with **a hole for every socket** |
| A socket | A rounded-over lip, a wall, a floor fillet and a floor, swept around that socket's own outline |
| A finished mark | A pill seated in its pocket — proud of the floor, below the face |
| An open mark | A ring standing on the pocket floor, bevelled so its top edge takes a highlight |

About 27,000 vertices and 49,000 triangles, exact at any zoom.

**One thing is not geometry, and the code says so where it does it**: the habit
names, the weekday letters, the icons and the missed ✕ are a relief read off a
mask texture and folded into the normal — a normal map. A quarter of a
millimetre of silkscreen does not need its own triangles, and saying so is
cheaper than pretending otherwise.

## Why not a displaced grid

The first version was the obvious one: a dense plane, a signed-distance field
for the card and its pockets, displacement in the vertex shader, normals from
four more taps in the fragment shader. It was wrong, and the way it was wrong is
worth keeping.

A pocket rim is a *curve*. An axis-aligned grid cannot follow one, so the rim
position quantises to the grid and every rim came back as a row of saw teeth —
worse, not better, for being partly resolved, because the analytic normals were
smooth while the geometry underneath them was not. Refining the grid along the
rows and the cell edges fixes the straight sides of a capsule and does nothing
for its rounded ends. Getting six samples across a 1.5-unit fillet everywhere
needed roughly 1.9 million vertices.

Sweeping the profile around each socket's own outline needs 49,000 triangles and
is exact. The grid was 550,000 and exact nowhere. If a future change reaches for
a heightfield again, this is the reason not to.

## Three bugs this cost, all worth knowing

- **A mark has to clear the pocket wall, not the opening.** The lip eats `RIM`
  inward as it rolls over, so a pill inset by `INSET` from the socket outline
  was *wider than the hole it sat in* and cut straight through the wall. Marks
  are inset by `RIM + INSET`.
- **Do not take the normal from `gl_FrontFacing`.** A swept strip's winding
  flips depending on which of its two loops is the outer one, so half the mesh
  reported back-facing; flipping the normal there turned every pocket floor and
  every pill upside down and lit them with the ground colour. Every ring already
  carries the outward normal its profile says it has — use it, and render
  `DoubleSide` so the winding cannot punch holes.
- **A specular lobe is not a material.** A directional light with `shininess`
  in the seventies across a flat 338-unit face reads as one big vertical
  gradient, not as a surface. Shininess and F₀ are now per material (card 16 /
  0.05, pill 48 / 0.07, ring 90 / 0.09) with a Schlick fresnel and a rough
  energy normalisation, and the face reads as a face.

## The week it shows

`TODAY`, `HABITS`, `LETTERS`, `widths`, `assignColumns` and `rowSpans` are
copied verbatim from `Website/week-widget/webflow/footer.html`, so this page and
`/glow-up` show the same demo week down to which day is missed. **If one
changes, change both** — there is no shared module to keep them honest.

The plan is the 2-D widget's own geometry at `--s: 1`: 24-unit cells, 8-unit
gaps, a 98-unit label column, 22-unit corners, a 338 × 354 card. Depth is the
only thing invented here — slab 16, pockets 3.4 deep.

## What it cannot do

**It cannot glow.** The glow on `/glow-up` is a PQ AVIF handed to the
compositor; a WebGL canvas is SDR and the brightest thing it can produce is
paper white. See `docs/glow.md`. This page is about *form*, the other one is
about *light*.

## Looking at it

```bash
python3 -m http.server 8912 --directory Website/glow-alt
```

`index.html` carries `data-debug` on the stage, which turns on `?p=`, `?y=` and
`?z=` (pitch in radians, yaw in radians, zoom multiplier) for repeatable
captures and publishes `window.GWA` for poking at the view. The Webflow embed
carries no `data-debug`, so neither exists on the live page.

## How it is deployed

`scene.js` is the source. It is one file in three IIFE blocks marked
`===== block n of 3`, because a Webflow custom-code block stops at 10,000
characters and the scene is 24,000.

```bash
python3 Website/glow-alt/build-webflow.py
```

strips comment-only lines, splits on those markers and writes
`webflow/block1.html` … `block3.html`, printing each block's size and failing if
one is over the cap. That is the fallback path: paste the three into embeds on
the page, in order.

**What is actually live is simpler.** The three blocks are concatenated into
`webflow/gwa-scene.js` and uploaded as a site asset — Webflow accepts
`application/javascript` — so the page holds one stage embed and a head with the
styles and two `<script src>` tags. The scene is at

```
https://cdn.prod.website-files.com/620d05babdddc967daa0780a/6aa89dff5b2dcf08aed1794c_gwa-scene.js
```

served with `cache-control: max-age=31536000`. **That URL is immutable**: a
changed file is a new hash, a new asset and a new URL, so any edit means
re-uploading and editing the page head. Verify the upload by fetching the
hosted URL and `cmp`-ing it against the built file — the CDN's `etag` is the
file's MD5, so a mismatch is visible without reading a byte.

three.js is pinned at `0.160.0` from cdnjs, the last release that ships a UMD
build. It logs a deprecation warning on load; that is expected. If it ever
disappears, the scene needs an ES-module loader, not a newer UMD guess.

## Performance

512 × 536 was the grid version's cost; this one is a fixed ~49,000 triangles and
the fragment shader is a dozen lines, so the frame cost is trivial and the only
real budget is the two 1352 × 1416 canvas textures (colour and relief mask).
Rendering pauses when the stage leaves the viewport, the idle drift respects
`prefers-reduced-motion`, and the device pixel ratio is capped at 2 (1.75 under
768px).
