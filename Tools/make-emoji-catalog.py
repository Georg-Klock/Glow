#!/usr/bin/env python3
"""Regenerates the full emoji catalogue the icon picker browses.

    python3 Tools/make-emoji-catalog.py [path/to/emoji-test.txt]

Reads Unicode's emoji-test.txt — the same data that defines what belongs on an
emoji keyboard and in what order — and writes Glow/Resources/EmojiCatalog.json
grouped into the categories an iPhone keyboard uses.

Committed as a script, with its output committed too, so the catalogue can be
regenerated for a new Unicode version without anyone hand-maintaining two
thousand glyphs, and so a build never depends on the script having been run.

Two deliberate exclusions:

  * Skin-tone and hair variants. The keyboard shows one base glyph and hides the
    variants behind a long press; listing all five inline turns a grid into a
    wall of the same person.
  * The "Component" group — bare skin-tone swatches and hair components are not
    emoji anyone picks as an icon.
"""

import json
import pathlib
import re
import sys
import urllib.request

SOURCE = "https://unicode.org/Public/emoji/16.0/emoji-test.txt"
OUTPUT = pathlib.Path("Glow/Resources/EmojiCatalog.json")

# Unicode's groups, mapped onto the categories an iPhone keyboard shows.
# Two Unicode groups fold into "Smileys & People", exactly as the keyboard does.
KEYBOARD_GROUPS = [
    ("Smileys & People", ["Smileys & Emotion", "People & Body"]),
    ("Animals & Nature", ["Animals & Nature"]),
    ("Food & Drink", ["Food & Drink"]),
    ("Activity", ["Activities"]),
    ("Travel & Places", ["Travel & Places"]),
    ("Objects", ["Objects"]),
    ("Symbols", ["Symbols"]),
    ("Flags", ["Flags"]),
]

SKIN_TONES = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}
HAIR = {0x1F9B0, 0x1F9B1, 0x1F9B2, 0x1F9B3}

LINE = re.compile(r"^([0-9A-F ]+);\s*([\w-]+)\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$")


def load(path_or_none):
    if path_or_none:
        return pathlib.Path(path_or_none).read_text(encoding="utf-8")
    with urllib.request.urlopen(SOURCE, timeout=60) as response:
        return response.read().decode("utf-8")


def main():
    text = load(sys.argv[1] if len(sys.argv) > 1 else None)

    by_unicode_group = {}
    group = subgroup = None
    for line in text.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if line.startswith("# subgroup:"):
            subgroup = line.split(":", 1)[1].strip()
            continue
        match = LINE.match(line)
        if not match:
            continue
        codes, status, glyph, name = match.groups()
        if status != "fully-qualified":
            continue
        points = {int(c, 16) for c in codes.split()}
        if points & SKIN_TONES or points & HAIR:
            continue
        by_unicode_group.setdefault(group, []).append(
            {"e": glyph, "n": name.strip(), "s": subgroup}
        )

    groups = []
    for title, unicode_groups in KEYBOARD_GROUPS:
        items = []
        for ug in unicode_groups:
            items.extend(by_unicode_group.get(ug, []))
        if items:
            groups.append({"title": title, "emoji": items})

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(groups, ensure_ascii=False, separators=(",", ":")) + "\n",
                      encoding="utf-8")

    total = sum(len(g["emoji"]) for g in groups)
    print(f"wrote {OUTPUT}: {total} emoji in {len(groups)} categories")
    for g in groups:
        print(f"  {g['title']}: {len(g['emoji'])}")


if __name__ == "__main__":
    main()
