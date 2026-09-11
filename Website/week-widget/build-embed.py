#!/usr/bin/env python3
"""Assemble the Webflow embed for the "This Week" hero.

Reads embed.template.html, inlines every plate manifest under assets/ and the
icon outlines under icons/, and writes:

  embed.html    — the block to paste into a Webflow Custom Code embed
  preview.html  — the same block on a plain page, for a local server

Options:
  --asset-base URL   where <set>/<file> can be fetched (default ./assets/)
  --asset-map JSON   file name → URL, for hosts that rename uploads (Webflow);
                     see webflow-asset-map.py
  --font-url URL     a woff2 for @font-face 'GW Inter'; omit when the site
                     already serves Inter under that family name

The embed never fetches the manifests: they are inlined so the only requests
the card makes are for the plates themselves and, if given, the font.
"""

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

parser = argparse.ArgumentParser()
parser.add_argument("--asset-base", default="./assets/")
parser.add_argument("--asset-map", default=None)
parser.add_argument("--font-url", default="./fonts/Inter-Regular.woff2")
parser.add_argument("--out", default=str(HERE))
args = parser.parse_args()

# Only what the page needs, per plate, so the inlined block stays small.
manifests = {}
for manifest_path in sorted((HERE / "assets").glob("*/manifest.json")):
    manifest = json.loads(manifest_path.read_text())
    manifests[manifest["set"]] = {
        "tier": manifest["tier"],
        "dpr": manifest["dpr"],
        "plates": {
            key: {
                "file": plate["file"],
                "cssWidth": round(plate["cssWidth"], 4),
                "cssHeight": round(plate["cssHeight"], 4),
                "offsetLeft": round(plate["offsetLeft"], 4),
                "offsetTop": round(plate["offsetTop"], 4),
            }
            for key, plate in manifest["plates"].items()
        },
    }
assert manifests, "no assets/*/manifest.json — run Tools/make-week-plates.swift first"

# The icon outlines the page draws live, from the same files the plates were
# cut from, so the lit and emitting tiers share one shape.
icons = {}
slugs = {
    "gratitude": "pencil", "stretch": "yoga", "read-book": "book", "workout": "dumbbell",
    "vo2-max": "run", "tutorial": "play-rectangle", "sunset": "sunset", "early-night": "bed",
}
for slug, icon in slugs.items():
    svg = (HERE / "icons" / f"{icon}.svg").read_text()
    paths = re.findall(r"<path\b[^>]*>", svg)
    assert paths, f"no <path> in {icon}.svg"
    icons[slug] = "".join(paths)

asset_map = json.loads(Path(args.asset_map).read_text()) if args.asset_map else {}
if asset_map:
    expected = {p["file"] for m in manifests.values() for p in m["plates"].values()}
    missing = sorted(expected - set(asset_map))
    assert not missing, f"asset map is missing {len(missing)} plates, e.g. {missing[:3]}"

template = (HERE / "embed.template.html").read_text()
font_face = ""
if args.font_url:
    font_face = (
        "<style>@font-face{font-family:'GW Inter';font-style:normal;font-weight:400;"
        f"font-display:block;src:url({args.font_url}) format('woff2');}}</style>\n"
    )
embed = font_face + template
for placeholder, value in {
    "__MANIFESTS__": json.dumps(manifests, separators=(",", ":")),
    "__ASSET_MAP__": json.dumps(asset_map, separators=(",", ":")),
    "__ASSET_BASE__": json.dumps(args.asset_base),
    "__ICONS__": json.dumps(icons, separators=(",", ":")),
}.items():
    assert placeholder in embed, placeholder
    embed = embed.replace(placeholder, value)
assert "__" not in re.sub(r"__(?:proto__)", "", embed).replace("__MANIFESTS__", ""), "unfilled placeholder"

out = Path(args.out)
(out / "embed.html").write_text(embed)

# A deliberately unreadable AVIF for the decode-failure check: the first 200
# bytes of a real plate, which any decoder refuses outright.
sample = next((HERE / "assets").glob("*/gw-*-ring-1.avif"))
corrupt = "data:image/avif;base64," + __import__("base64").b64encode(sample.read_bytes()[:200]).decode()
hooks = """<script>
// Preview-only test hooks. ?sdr pretends the display has no headroom, so the
// gate that decides whether a plate is ever fetched is what gets exercised.
// ?corrupt points three plates at a truncated AVIF; ?missing at a 404.
(function () {
  var q = new URLSearchParams(location.search);
  if (q.has('sdr')) {
    var real = window.matchMedia.bind(window);
    window.matchMedia = function (query) {
      if (query === '(dynamic-range: high)') {
        return { matches: false, media: query, addEventListener: function () {}, removeEventListener: function () {}, addListener: function () {}, removeListener: function () {} };
      }
      return real(query);
    };
  }
  var bad = q.has('corrupt') ? '__CORRUPT__' : q.has('missing') ? './assets/does-not-exist.avif' : null;
  if (bad) {
    window.GLOW_WEEK_ASSET_MAP = {};
    ['desktop-2x-day-F', 'desktop-2x-ring-1', 'desktop-2x-name-gratitude', 'desktop-1x-day-F', 'desktop-1x-ring-1', 'desktop-1x-name-gratitude'].forEach(function (k) {
      window.GLOW_WEEK_ASSET_MAP['gw-' + k + '.avif'] = bad;
    });
  }
})();
</script>
""".replace("__CORRUPT__", corrupt)

preview = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Glow Up · This Week (preview)</title>
<style>
  html, body {{ margin: 0; background: #141416; color: #ddd; font-family: system-ui, sans-serif; }}
  .page {{ min-height: 100vh; display: grid; place-items: center; }}
  .note {{ position: fixed; left: 12px; bottom: 12px; font-size: 12px; opacity: .6; }}
</style>
{hooks}
</head>
<body>
<div class="page">
{embed}
</div>
<div class="note">preview · background is deliberately not black</div>
</body>
</html>
"""
(out / "preview.html").write_text(preview)
print(f"embed.html {len(embed) // 1024} KB, {len(manifests)} sets, {sum(len(m['plates']) for m in manifests.values())} plates")
