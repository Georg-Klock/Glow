#!/usr/bin/env python3
"""Compare a run's rendered signatures against the committed baseline.

`Tools/approve-baseline.sh` used `cmp` for this, and on the current runtime
`cmp` is the right question: the same commit rendered 48 times across eight
processes on iOS 26.5 came back **bit-identical every time**, so any difference
in that file is a real one.

On iOS 18.5 it is not. Sixty renders across ten processes on two different
iOS 18.5 devices differ from each other by up to 601 pixels — every one of them
by a single level, in the `.ultraThinMaterial` the widget surface is drawn on.
See #431 and `docs/decisions.md`.

Almost all of that noise is invisible to a signature. A 16 x 16 cell mean
averages roughly 1,800 pixels, so a few hundred single-level flips move it by
about a thousandth of a level; the exact-black share is a percentage to one
decimal place over the whole frame. Measured across those sixty renders,
neither moved once.

**One statistic is not invisible to it.** `tones` is a *count* of pixels at one
exact level — that is the whole point of it (#199), and it is also what makes
it the one number a single pixel can move. It moves by one, in both directions:

    week large        255   4097 / 4098   30 renders each, over 60
    week large sunday 255   7233 / 7234    6 renders of 60 at 7233
    grid rows         124    230 /  231    6 renders of 60 at 230

Neither end of that ever moved further. `week large` shows how little it takes:
the count at 255 itself is 4106 in every single render, and what oscillates is
the neighbour the excess subtracts — one pixel crossing 253/254.

So this compares exactly everywhere the render was measured to be exact, and
allows the measured noise, and no more, in the one place it was not.

**What that stops catching**, said plainly: a deliberate visual change whose
entire effect on every frame is one or two pixels of one flat tone, with no
cell mean and no ground share moving at all. Nothing in this project's history
is that small — #194 moved a tone by about 3,400 and #332 collapsed one from
4,401 to 2,170 — and a change that small is below the resolution of anything
anyone can draw.

**And it is not a tolerance on the gate.** `RenderBaselineTests` is untouched:
it compares cells against a tolerance of 3 and tones against a retention ratio,
and it always has. This is the file-equality check that stands in front of it,
which was stricter than the gate by accident rather than by decision — and
which was therefore the only thing that ever failed on #431's oscillation.

    compare-signatures.py --actual A.json --committed B.json
    compare-signatures.py --self-test

The first line of output is one word — `same`, `noise` or `moved` — and every
line after it is one difference. Exit status is 0 whenever the comparison could
be made; the caller reads the word. 2 is usage or I/O.
"""

import argparse
import json
import sys

#: How far a single tone count may move before it is a change rather than the
#: renderer. The measured spread on iOS 18.5 is exactly 1, in 60 renders on two
#: devices; on iOS 26.5 it is 0 in 48. This is that, with one level of headroom.
#: Raising it is a decision — the numbers above are what would have to be
#: re-measured first.
TONE_NOISE = 2

#: Everything else in a signature, compared exactly. The grid arrives as `rows`
#: — sixteen strings of sixteen numbers — so comparing that compares all 256
#: cells.
EXACT_KEYS = ("width", "height", "exactBlackPercent", "rows")


def compare(actual: dict, committed: dict) -> tuple[str, list[str]]:
    """Classify the difference. Returns (`same` | `noise` | `moved`, reasons)."""
    moved: list[str] = []
    noise: list[str] = []

    rendered = actual.get("frames", {})
    baseline = committed.get("frames", {})

    for name in sorted(set(rendered) | set(baseline)):
        if name not in baseline:
            moved.append(f"{name}: rendered, but the baseline has no such frame")
            continue
        if name not in rendered:
            moved.append(f"{name}: in the baseline, but this run rendered no such frame")
            continue

        mine, theirs = rendered[name], baseline[name]
        for key in EXACT_KEYS:
            if mine.get(key) != theirs.get(key):
                moved.append(f"{name}: {key} moved")

        mine_tones = mine.get("tones", {})
        their_tones = theirs.get("tones", {})
        for level in sorted(set(mine_tones) | set(their_tones), key=int):
            here, there = mine_tones.get(level), their_tones.get(level)
            if here == there:
                continue
            if here is None or there is None:
                moved.append(f"{name}: level {level} is in one signature and not the other")
            elif abs(here - there) > TONE_NOISE:
                moved.append(f"{name}: level {level} {there} -> {here}")
            else:
                noise.append(f"{name}: level {level} {there} -> {here}")

    if moved:
        return "moved", moved + noise
    if noise:
        return "noise", noise
    return "same", []


# MARK: - The self-test
#
# A checker nobody checks can weaken silently, which is why the other five
# carry one. This one has a numeric constant in it, so it needs one most.

def _signature(tones: dict[str, int], black: float = 0.0, row: str = "  0") -> dict:
    return {
        "width": 100,
        "height": 100,
        "exactBlackPercent": black,
        "rows": [" ".join([row] * 16)] * 16,
        "tones": tones,
    }


def _baseline(frames: dict) -> dict:
    return {"frames": frames}


def self_test() -> int:
    committed = _baseline({"a": _signature({"124": 231, "255": 4097})})

    cases: list[tuple[str, dict, str, str]] = [
        (
            "an identical render is the same",
            _baseline({"a": _signature({"124": 231, "255": 4097})}),
            "same", "",
        ),
        (
            "one pixel of tone is the renderer",
            _baseline({"a": _signature({"124": 230, "255": 4097})}),
            "noise", "level 124 231 -> 230",
        ),
        (
            "both directions, both cells at once, is still the renderer",
            _baseline({"a": _signature({"124": 232, "255": 4098})}),
            "noise", "level 255 4097 -> 4098",
        ),
        (
            "past the measured noise is a change",
            _baseline({"a": _signature({"124": 228, "255": 4097})}),
            "moved", "level 124 231 -> 228",
        ),
        (
            "a collapsed tone is a change",
            _baseline({"a": _signature({"124": 231, "255": 0})}),
            "moved", "level 255 4097 -> 0",
        ),
        (
            "a cell mean is compared exactly, however small the move",
            _baseline({"a": _signature({"124": 231, "255": 4097}, row="  1")}),
            "moved", "rows moved",
        ),
        (
            "so is the ground share",
            _baseline({"a": _signature({"124": 231, "255": 4097}, black=0.1)}),
            "moved", "exactBlackPercent moved",
        ),
        (
            "a tone level appearing is a change, not a rounding",
            _baseline({"a": _signature({"124": 231, "255": 4097, "217": 1})}),
            "moved", "level 217 is in one signature and not the other",
        ),
        (
            "a new frame is a change",
            _baseline({
                "a": _signature({"124": 231, "255": 4097}),
                "b": _signature({"124": 5}),
            }),
            "moved", "b: rendered, but the baseline has no such frame",
        ),
        (
            "a lost frame is a change",
            _baseline({}),
            "moved", "a: in the baseline, but this run rendered no such frame",
        ),
        (
            "noise beside a real move does not soften it",
            _baseline({"a": _signature({"124": 230, "255": 3000})}),
            "moved", "level 255 4097 -> 3000",
        ),
    ]

    failures = 0
    for title, actual, expected, fragment in cases:
        verdict, reasons = compare(actual, committed)
        joined = "; ".join(reasons)
        ok = verdict == expected and fragment in joined
        print(f"  {'ok  ' if ok else 'FAIL'}  {title}")
        if not ok:
            failures += 1
            print(f"        got {verdict!r} {joined!r}, wanted {expected!r} containing {fragment!r}")

    # The empty-baseline case: nothing committed at all is not "same".
    verdict, _ = compare(_baseline({"a": _signature({"124": 1})}), _baseline({}))
    ok = verdict == "moved"
    print(f"  {'ok  ' if ok else 'FAIL'}  a run with no committed baseline is a change")
    failures += 0 if ok else 1

    print(f"compare-signatures: {len(cases) + 1 - failures}/{len(cases) + 1} self-tests passed")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", help="the run's render-signatures-actual.json")
    parser.add_argument("--committed", help="the committed baseline for this runtime")
    parser.add_argument("--self-test", action="store_true", dest="selftest")
    arguments = parser.parse_args()

    if arguments.selftest:
        return self_test()

    if not arguments.actual or not arguments.committed:
        parser.error("--actual and --committed are both required")

    try:
        with open(arguments.actual) as file:
            actual = json.load(file)
    except (OSError, ValueError) as error:
        print(f"error: cannot read the run's signatures: {error}", file=sys.stderr)
        return 2

    try:
        with open(arguments.committed) as file:
            committed = json.load(file)
    except FileNotFoundError:
        print("moved")
        print(f"{arguments.committed}: there is no committed baseline yet")
        return 0
    except (OSError, ValueError) as error:
        print(f"error: cannot read {arguments.committed}: {error}", file=sys.stderr)
        return 2

    verdict, reasons = compare(actual, committed)
    print(verdict)
    for reason in reasons:
        print(reason)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
