# The HDR note

One line under the hero's slider on georgklock.com/glow-up:

    HDR images can glow brighter than pure white

Rendered by `Tools/make-glow-word.swift` as one AVIF per headroom step —
Söhne Buch at 68pt, twelve steps, `--halo 0` — and stacked by the hero script,
which fades step n+1 in over step n as the slider moves. The 1× file is Display
P3, the other eleven are PQ.

    swift Tools/make-glow-word.swift \
      --text "HDR images can glow brighter than pure white" \
      --out ./out --font Sohne-Buch --size 68 --steps 12 --halo 0

`gu-hdrnote-01.avif` … `-12.avif`, 1448 × 154, 192 KB the set.

## It only exists on a screen with headroom

`.gw:not(.gw-hdr) .gw-note { display: none }`. The sentence is a claim the page
can only make by demonstrating it, and an SDR screen tone-maps the PQ files to
the same white as everything else — so the line would sit there asserting
something it visibly fails to do. What SDR visitors get instead is the
`.gw-nohdr` message in place of the slider.

That is why all twelve steps are still needed even though only one line ships:
the stack is the demo. Step 1 is the base layer at exactly SDR white and the
rest ride on top of it.

## Crop

The render is 1448 × 154 and the ink lands in rows 55–116, measured by decoding
step 1 and scanning for non-black rows. The page shows a band of 78 centred on
row 85.5, so:

    NOTE_BAND = 78
    object-position: 50% 61.184%        /* (85.5 − 78/2) ÷ (154 − 78) */

Those two have to move together. `NOTE_BAND` sets the host's aspect ratio and
the `object-position` picks which slice of the image `object-fit: cover` shows;
change one alone and the line crops off-centre.

## Where the wording lives

`NOTE_LINES` in the **site footer** custom code — text, render width, and the
twelve hashed CDN names. That is the only place. To change the sentence:
render, verify, upload, and paste the new names in.

A second copy once lived in the page footer and rewrote every note image
through a MutationObserver. Two sources for one sentence, and the footer always
lost — the page showed the override's images whatever `NOTE_LINES` said.
Removed 2026-09-13. If the note ever goes back to wording nobody set, look for
a second writer before looking at `NOTE_LINES`.

## Verify before uploading

`avifdec --info` on each file: the 1× step should read Transfer Char 2 with an
ICC profile, the rest Colour Primaries 9 and Transfer Char 16, none with an
alpha plane. Then decode and check the peaks rise — measured for this set at
0.664, 0.782 and 0.855 of the code range for steps 2, 6 and 12, all above the
0.581 that PQ gives SDR white. Apple's decoders will read a file libavif
rejects, so use libavif.

## Superseded

`gu-note-l1-*` … `gu-note-l3-*`, the three-line "If this text doesn't glow…"
set, is no longer referenced by the page. Kept for now; safe to prune.
