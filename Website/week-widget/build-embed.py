#!/usr/bin/env python3
"""Assemble the "This Week" hero from embed.template.html.

Two shapes come out, because Webflow caps every custom-code block at 10,000
characters and the whole block is about four times that:

  embed.html, preview.html
      Everything in one block — CSS, markup, script, and the plate manifests,
      icon outlines and asset map inlined. For any host without a size cap,
      and for the local preview server.

  webflow/head.html, webflow/embed.html, webflow/footer.html,
  webflow/gw-manifest.json, webflow/preview.html     (with --webflow)
      The same thing in three code blocks that each fit: the CSS (page head),
      the markup (an HTML Embed element), the script (page footer), with the
      data in one JSON asset the script fetches once. The markup names the
      JSON's URL in data-manifest. Comments and indentation are stripped from
      the CSS and the script; nothing else changes.

Options:
  --asset-base URL   where <set>/<file> can be fetched (default ./assets/)
  --asset-map JSON   file name → URL for hosts that rename uploads (Webflow)
  --font-url URL     a woff2 for @font-face 'GW Inter'; "" to omit the rule
  --webflow          also write the three-block shape under webflow/
  --manifest-url URL the JSON asset's URL, for webflow/embed.html
                     (default ./gw-manifest.json, which webflow/preview.html serves)
"""

import argparse
import base64
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

parser = argparse.ArgumentParser()
parser.add_argument("--asset-base", default="./assets/")
parser.add_argument("--asset-map", default=None)
parser.add_argument("--font-url", default="./fonts/Inter-Regular.woff2")
parser.add_argument("--webflow", action="store_true")
parser.add_argument("--manifest-url", default="./gw-manifest.json")
parser.add_argument("--out", default=str(HERE))
args = parser.parse_args()

# ─── Data ───────────────────────────────────────────────────────────────────
# Only what the page needs, per plate, so the block stays small.
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

data = {"manifests": manifests, "icons": icons, "assetMap": asset_map, "assetBase": args.asset_base}
compact = dict(separators=(",", ":"))

# ─── Template parts ─────────────────────────────────────────────────────────
template = (HERE / "embed.template.html").read_text()
style_end = template.index("</style>") + len("</style>")
script_start = template.index("<script>")
css_block = template[template.index("<style>"):style_end]
markup = template[style_end:script_start].strip()
script_block = template[script_start:].rstrip()
assert script_block.endswith("</script>")
assert "__INLINE__" in script_block

font_face = ""
if args.font_url:
    font_face = (
        "@font-face{font-family:'GW Inter';font-style:normal;font-weight:400;"
        f"font-display:block;src:url({args.font_url}) format('woff2');}}"
    )


def strip_css(css):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"\n\s*\n", "\n", css)
    return "\n".join(line.strip() for line in css.splitlines() if line.strip())


def strip_js(js):
    """Whole-line // comments, trailing // comments after code that carries no
    quote, blank lines and indentation. The script's own strings are the only
    place a // could hide, and none of them share a line with a comment."""
    out = []
    for line in js.splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = re.search(r"\s+//[^'\"]*$", s)
        if m and s.count("'") % 2 == 0 and s.count('"') % 2 == 0:
            s = s[:m.start()].rstrip()
        out.append(s)
    return "\n".join(out)


# ─── One block ──────────────────────────────────────────────────────────────
one = css_block.replace("<style>", "<style>" + font_face, 1) if font_face else css_block
one += "\n" + markup + "\n" + script_block.replace("__INLINE__", json.dumps(data, **compact))
assert "__" not in one.replace("__proto__", ""), "unfilled placeholder"
out = Path(args.out)
(out / "embed.html").write_text(one)

# A deliberately unreadable AVIF for the decode-failure check: the first 200
# bytes of a real plate, which any decoder refuses outright.
sample = next((HERE / "assets").glob("*/gw-*-ring-1.avif"))
corrupt = "data:image/avif;base64," + base64.b64encode(sample.read_bytes()[:200]).decode()
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


def page(head_extra, body, note):
    return f"""<!doctype html>
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
{hooks}{head_extra}
</head>
<body>
<div class="page">
{body}
</div>
<div class="note">{note}</div>
</body>
</html>
"""


(out / "preview.html").write_text(page("", one, "preview · one block · background is deliberately not black"))
print(f"embed.html {len(one) // 1024} KB, {len(manifests)} sets, {sum(len(m['plates']) for m in manifests.values())} plates")

# ─── Three blocks, for Webflow ──────────────────────────────────────────────
if args.webflow:
    wf = out / "webflow"
    wf.mkdir(exist_ok=True)
    head = "<style>" + font_face + strip_css(css_block[len("<style>"):-len("</style>")]) + "</style>"
    embed = markup.replace('<div class="gw" id="gw">', f'<div class="gw" id="gw" data-manifest="{args.manifest_url}">', 1)
    assert "data-manifest" in embed
    footer_js = strip_js(script_block[len("<script>"):-len("</script>")].replace("__INLINE__", "null"))
    footer = "<script>" + footer_js + "</script>"
    (wf / "head.html").write_text(head)
    (wf / "embed.html").write_text(embed)
    (wf / "footer.html").write_text(footer)
    (wf / "gw-manifest.json").write_text(json.dumps(data, **compact))
    # The same three blocks on a page, with a manifest that finds the plates
    # one directory up, where the repository keeps them.
    (wf / "gw-manifest.local.json").write_text(json.dumps(dict(data, assetMap={}, assetBase="../assets/"), **compact))
    (wf / "preview.html").write_text(page(
        head,
        embed.replace(f'data-manifest="{args.manifest_url}"', 'data-manifest="./gw-manifest.local.json"', 1) + "\n" + footer,
        "preview · three blocks + JSON, the Webflow shape",
    ))
    for name in ("head.html", "embed.html", "footer.html"):
        n = len((wf / name).read_text())
        flag = "" if n <= 10000 else "  ← OVER Webflow's 10,000-character limit"
        print(f"webflow/{name}: {n} chars{flag}")
    print(f"webflow/gw-manifest.json: {len((wf / 'gw-manifest.json').read_text()) // 1024} KB")
