#!/usr/bin/env python3
"""Regenerates the SF Symbols catalogue the icon picker browses.

    python3 Tools/make-symbol-catalog.py

Reads the symbol database that ships with macOS and writes
Glow/Resources/SymbolCatalog.json: every symbol available on the app's
deployment target, grouped by Apple's own categories and kept in Apple's own
display order.

Committed as a script, with its output committed too, so the catalogue can be
regenerated when Xcode updates without anyone hand-maintaining a list of nine
thousand strings, and so a build never depends on the script having been run.

Localised, script-specific and directional variants are dropped: `.ar`, `.hi`,
`.th` and friends are the same icon for another writing system, and showing all
of them turns a picker into a phone book.
"""

import json
import pathlib
import plistlib
import re
import sys

GLYPHS = pathlib.Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
OUTPUT = pathlib.Path("Glow/Resources/SymbolCatalog.json")

# Matches the deploymentTarget in project.yml.
MAX_IOS = (18, 0)

# Suffixes that mark a localised or script-specific variant of another symbol.
LOCALE_SUFFIX = re.compile(
    r"\.(ar|hi|he|ja|ko|th|zh|kn|gu|mr|ml|ta|te|pa|bn|or|si|km|my|ru|el|de|es|fr|it|pt)"
    r"(\.[a-z]+)*$"
)

CATEGORY_TITLES = {
    "whatsnew": "What's New", "multicolor": "Multicolour", "variable": "Variable",
    "communication": "Communication", "weather": "Weather", "maps": "Maps",
    "objectsandtools": "Objects & Tools", "devices": "Devices", "cameraandphotos": "Camera & Photos",
    "gaming": "Gaming", "connectivity": "Connectivity", "transportation": "Transport",
    "automotive": "Automotive", "accessibility": "Accessibility", "privacyandsecurity": "Privacy & Security",
    "human": "People", "home": "Home", "fitness": "Fitness", "nature": "Nature",
    "editing": "Editing", "text": "Text", "textformatting": "Text Formatting",
    "media": "Media", "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time",
    "health": "Health", "shapes": "Shapes", "arrows": "Arrows", "indices": "Indices",
    "math": "Maths", "draw": "Drawing",
}

# Categories that are about how a symbol renders rather than what it depicts.
SKIP_CATEGORIES = {"all", "whatsnew", "multicolor", "variable", "indices"}


def parse_version(text):
    parts = text.split(".")
    return (int(parts[0]), int(parts[1]) if len(parts) > 1 else 0)


def main():
    if not GLYPHS.exists():
        sys.exit(f"error: {GLYPHS} not found. This script needs a Mac with Xcode installed.")

    availability = plistlib.loads((GLYPHS / "name_availability.plist").read_bytes())
    releases = availability["year_to_release"]
    symbol_years = availability["symbols"]
    categories = plistlib.loads((GLYPHS / "categories.plist").read_bytes())
    symbol_categories = plistlib.loads((GLYPHS / "symbol_categories.plist").read_bytes())
    order = plistlib.loads((GLYPHS / "symbol_order.plist").read_bytes())

    rank = {name: index for index, name in enumerate(order)}

    supported = set()
    for name, year in symbol_years.items():
        ios = releases.get(year, {}).get("iOS")
        if not ios or parse_version(ios) > MAX_IOS:
            continue
        if LOCALE_SUFFIX.search(name):
            continue
        supported.add(name)

    groups = []
    seen = set()
    for category in categories:
        key = category["key"]
        if key in SKIP_CATEGORIES:
            continue
        members = sorted(
            (n for n in supported if key in symbol_categories.get(n, [])),
            key=lambda n: rank.get(n, len(rank)),
        )
        if not members:
            continue
        seen.update(members)
        groups.append({
            "key": key,
            "title": CATEGORY_TITLES.get(key, key.replace("and", " & ").title()),
            "icon": category.get("icon", "square"),
            "symbols": members,
        })

    leftovers = sorted(supported - seen, key=lambda n: rank.get(n, len(rank)))
    if leftovers:
        groups.append({"key": "other", "title": "Other", "icon": "square.grid.2x2", "symbols": leftovers})

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(groups, indent=None, separators=(",", ":")) + "\n")

    total = sum(len(g["symbols"]) for g in groups)
    print(f"wrote {OUTPUT}: {total} symbols in {len(groups)} categories")


if __name__ == "__main__":
    main()
