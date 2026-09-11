# The HDR note

The three lines under the hero's slider on georgklock.com/glow-up, rendered
by `Tools/make-glow-word.swift` as one AVIF per line and headroom step
(Söhne Buch at 68pt, twelve steps; the 1x file is Display P3, the rest PQ):

    If this text doesn’t glow significantly brighter on your current screen,
    please come back on iPhone 12 Pro or newer, MacBook Pro
    or other HDR capable screens to see the effect.

`gu-note-l<line>-<step>.avif`, 36 files, 909 KB; uploaded to the site as
assets and named with their hashed CDN names in the hero script's
`NOTE_LINES` (`Website/week-widget/embed.template.html`). The page sets each
line at 17px, the body size; widths are the render's pixels (2082 / 1808 /
1464 at 154 high). To change the wording, render again, upload, and paste
the new names into `NOTE_LINES`.
