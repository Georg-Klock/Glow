#!/usr/bin/env python3
"""Regenerates the SF Symbols catalogue the icon picker browses.

    python3 Tools/make-symbol-catalog.py

Reads the symbol database that ships with macOS and writes
Glow/Resources/SymbolCatalog.json.

**The picker browses a fraction of SF Symbols on purpose.** All 9,403 of them
are mostly chevrons, transport controls, HomeKit accessories and iOS furniture;
nobody naming a habit is looking for `arrow.up.backward.bottomtrailing`. So the
browsable set is built the way the emoji tab beside it is: things that stand for
something, in the eight categories an emoji keyboard uses.

Two passes get there:

  1. **Drop a fill where its outline exists.** `heart` and `heart.fill` are one
     choice at picker scale. Fill-only symbols are kept — dropping those loses
     the shape entirely.
  2. **Keep what an emoji would have said.** Every emoji in EmojiCatalog.json is
     matched against a symbol by name, and what matches is what appears. The
     match is imperfect by nature: Unicode says "droplet" where SF Symbols says
     `drop`, and "fire" where it says `flame`. Exact names get most of it and
     SYNONYMS below gets the rest; anything unmatched is simply not offered.

The file also carries `all`: every supported symbol name, browsable or not. That
list is what decides whether a *stored* icon renders as a symbol or as text, so
it cannot shrink with the picker — a habit whose icon left the browsable set
would otherwise start rendering as the literal string "figure.flexibility".

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
EMOJI = pathlib.Path("Glow/Resources/EmojiCatalog.json")

# Words that say what kind of thing an emoji is rather than what it depicts.
# "cat face" is a cat; "keycap 1" is a 1.
NOISE = {
    "face", "sign", "symbol", "button", "emoji", "selector", "mark", "keycap",
    "colour", "color", "light", "medium", "dark", "skin", "tone", "flag",
    "with", "and", "of", "the", "a", "in", "on", "no", "not",
}

# Where Unicode and SF Symbols use different words for the same picture. Only
# the ones that actually occur — this is not a thesaurus, it is a list of misses
# found by running the matcher and reading what it dropped.
SYNONYMS = {
    "droplet": "drop", "fire": "flame", "automobile": "car",
    "high voltage": "bolt", "party popper": "party.popper",
    "wrapped gift": "gift", "locked": "lock", "unlocked": "lock.open",
    "envelope": "envelope", "mobile phone": "iphone", "laptop": "laptop.computer",
    "desktop computer": "desktopcomputer", "television": "tv",
    "alarm clock": "alarm", "hourglass done": "hourglass",
    "printer": "printer", "battery": "battery.100percent",
    "electric plug": "powerplug", "light bulb": "lightbulb",
    "magnifying glass tilted left": "magnifyingglass",
    "shopping cart": "cart", "credit card": "creditcard",
    "money bag": "bag", "chart increasing": "chart.line.uptrend.xyaxis",
    "bar chart": "chart.bar", "calendar": "calendar", "spiral calendar": "calendar",
    "card index dividers": "folder", "file folder": "folder",
    "page facing up": "doc", "memo": "square.and.pencil", "pencil": "pencil",
    "paperclip": "paperclip", "scissors": "scissors",
    "musical note": "music.note", "musical notes": "music.note.list",
    "studio microphone": "mic", "microphone": "mic", "headphone": "headphones",
    "bell": "bell", "bell with slash": "bell.slash", "megaphone": "megaphone",
    "camera": "camera", "video camera": "video", "film frames": "film",
    "framed picture": "photo", "artist palette": "paintpalette",
    "books": "books.vertical", "open book": "book", "bookmark": "bookmark",
    "newspaper": "newspaper", "graduation cap": "graduationcap",
    "backpack": "backpack", "briefcase": "briefcase", "hammer": "hammer",
    "wrench": "wrenchdriver", "gear": "gearshape", "key": "key",
    "house": "house", "office building": "building.2", "hospital": "cross.case",
    "bank": "building.columns", "tent": "tent", "mountain": "mountain.2",
    "deciduous tree": "tree", "four leaf clover": "clover", "leaf fluttering in wind": "leaf",
    "herb": "leaf", "cactus": "cactus", "sun": "sun.max", "sun behind cloud": "cloud.sun",
    "cloud": "cloud", "cloud with rain": "cloud.rain", "cloud with snow": "cloud.snow",
    "snowflake": "snowflake", "rainbow": "rainbow", "crescent moon": "moon",
    "star": "star", "glowing star": "sparkles", "sparkles": "sparkles",
    "sunrise": "sunrise", "sunset": "sunset", "wind face": "wind",
    "water wave": "water.waves", "tornado": "tornado", "thermometer": "thermometer.medium",
    "airplane": "airplane", "rocket": "airplane.departure", "bicycle": "bicycle",
    "bus": "bus", "tram": "tram", "sailboat": "sailboat", "fuel pump": "fuelpump",
    "car": "car", "taxi": "car", "police car": "car", "delivery truck": "truck.box",
    "運": "car", "anchor": "wave.3.right", "compass": "safari",
    "world map": "map", "globe showing europe africa": "globe",
    "man running": "figure.run", "woman running": "figure.run",
    "person running": "figure.run", "person walking": "figure.walk",
    "person swimming": "figure.pool.swim", "person biking": "figure.outdoor.cycle",
    "person lifting weights": "figure.strengthtraining.traditional",
    "person in lotus position": "figure.mind.and.body",
    "person doing cartwheel": "figure.gymnastics",
    "soccer ball": "soccerball", "basketball": "basketball", "tennis": "tennisball",
    "american football": "football", "baseball": "baseball",
    "bed": "bed.double", "bathtub": "bathtub", "shower": "shower",
    "toothbrush": "toothbrush", "pill": "pills", "syringe": "syringe",
    "stethoscope": "stethoscope", "dna": "atom", "brain": "brain",
    "anatomical heart": "heart", "red heart": "heart", "broken heart": "heart.slash",
    "eye": "eye", "ear": "ear", "nose": "nose", "hand with fingers splayed": "hand.raised",
    "thumbs up": "hand.thumbsup", "thumbs down": "hand.thumbsdown",
    "clapping hands": "hands.clap", "folded hands": "hands.and.sparkles",
    "waving hand": "hand.wave", "flexed biceps": "figure.strengthtraining.functional",
    "footprints": "shoeprints.fill", "eyes": "eyes",
    "hot beverage": "cup.and.saucer", "teacup without handle": "mug",
    "wine glass": "wineglass", "clinking beer mugs": "mug",
    "bottle with popping cork": "wineglass", "fork and knife": "fork.knife",
    "birthday cake": "birthday.cake", "carrot": "carrot", "green apple": "apple.logo",
    "fish": "fish", "dog face": "dog", "cat face": "cat", "bird": "bird",
    "rabbit face": "hare", "turtle": "tortoise", "butterfly": "ladybug",
    "honeybee": "ladybug", "lady beetle": "ladybug", "paw prints": "pawprint",
    "telephone": "phone", "speech balloon": "bubble.left",
    "thought balloon": "bubble.middle.bottom", "love letter": "envelope.badge",
    "package": "shippingbox", "postbox": "tray", "inbox tray": "tray.and.arrow.down",
    "outbox tray": "tray.and.arrow.up", "wastebasket": "trash",
    "recycling symbol": "arrow.3.trianglepath", "warning": "exclamationmark.triangle",
    "question mark": "questionmark", "exclamation mark": "exclamationmark",
    "check mark": "checkmark", "cross mark": "xmark", "plus": "plus", "minus": "minus",
    "infinity": "infinity", "hundred points": "100.circle",
}

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

    # Pass one: a fill is a duplicate wherever its outline exists, and a keycap
    # is a letter rather than a picture.
    browsable = {
        n for n in supported
        if not (n.endswith(".fill") and n[:-5] in supported)
        and not KEYCAP.match(n)
        and n not in BLOCKED
    }
    dropped_fills = len(supported) - len(browsable)

    # Pass two: keep what an emoji would have said, in the emoji keyboard's
    # own categories.
    groups, matched, unmatched = emoji_groups(browsable)

    payload = {
        "groups": groups,
        # Every supported name, browsable or not. This is what decides whether a
        # *stored* icon is drawn as a symbol, so it must not shrink with the
        # picker — see the note at the top of this file.
        "all": sorted(supported, key=lambda n: rank.get(n, len(rank))),
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=None, separators=(",", ":")) + "\n")

    print(f"wrote {OUTPUT}")
    print(f"  {len(supported)} supported symbols, all kept for validation")
    print(f"  {dropped_fills} fills dropped where an outline exists")
    print(f"  {matched} browsable, in {len(groups)} categories")
    for g in groups:
        print(f"    {g['title']}: {len(g['symbols'])}")
    print(f"  {unmatched} emoji had no symbol and are simply not offered")


def tokens_of(name):
    """The words of an emoji name that say what it depicts."""
    cleaned = re.sub(r"[^a-z ]", " ", name.lower())
    return [w for w in cleaned.split() if w and w not in NOISE]


KEYCAP = re.compile(r"^[a-z0-9]\.")

# Symbols whose *name* is a word but whose *picture* is a piece of UI. The
# matcher cannot tell these apart — `left` and `right` are real symbols that a
# hand-pointing emoji matches perfectly, and they draw the letters L and R.
# Found by looking at the picker rather than by reasoning about the data.
BLOCKED = {
    "left", "right",        # AirPods channel indicators; they draw "L" and "R"
    "control",              # the modifier glyph, matched by "control knobs"
    "sos", "numbers",       # lettering, not pictures
    "mount",                # disk mount, matched by "mount fuji"; mountain.2 is the picture
    "stop",                 # media transport, matched by "stop sign"
    "apple.logo",           # matched by "green apple", and it is a company
}


def match_symbol(name, browsable):
    """The symbol an emoji stands for, or None.

    Ordered from most specific to least, so "open book" reaches `book` and
    "cat face" reaches `cat` rather than `face.smiling`.
    """
    lowered = name.lower()
    if lowered in SYNONYMS:
        candidate = SYNONYMS[lowered]
        return candidate if candidate in browsable else None

    words = tokens_of(name)
    if not words:
        return None

    # The whole name, run together or dotted: "hourglass" , "person.walk".
    for joined in ("".join(words), ".".join(words)):
        if joined in browsable:
            return joined

    # A single word of it, longest first — the longest word is the most specific
    # thing the name says. Three letters minimum: shorter than that and a stray
    # word matches a keycap, so "T-Rex" arrives as `t.bubble`.
    for word in sorted(words, key=len, reverse=True):
        if len(word) >= 3 and word in browsable:
            return word

    # There was a third rule here — a two-part symbol led by one of the words,
    # so "sun" could reach `sun.max`. It let far more through than it caught:
    # "cricket" reached `cricket.ball` (the insect, not the sport), "spider web"
    # reached `web.camera`, and "American" reached `american.football` under
    # Flags. The handful of real cases it existed for are in SYNONYMS instead,
    # where they can be read and argued with.
    return None


def emoji_groups(browsable):
    """The emoji catalogue's categories, rendered in SF Symbols."""
    if not EMOJI.exists():
        sys.exit(f"error: {EMOJI} not found. Run make-emoji-catalog.py first.")

    catalogue = json.loads(EMOJI.read_text(encoding="utf-8"))
    groups = []
    used = set()
    matched = 0
    unmatched = 0

    for category in catalogue:
        symbols = []
        for entry in category["emoji"]:
            symbol = match_symbol(entry["n"], browsable)
            if symbol is None:
                unmatched += 1
                continue
            matched += 1
            # A symbol can answer for several emoji — "car", "taxi" and "police
            # car" are all `car`. It appears once, in the first category that
            # wanted it.
            if symbol in used:
                continue
            used.add(symbol)
            symbols.append(symbol)

        if symbols:
            groups.append({
                "key": category["title"].lower().replace(" & ", "-").replace(" ", "-"),
                "title": category["title"],
                "icon": symbols[0],
                "symbols": symbols,
            })
    return groups, len(used), unmatched


if __name__ == "__main__":
    main()
