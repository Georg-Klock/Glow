#!/usr/bin/env python3
"""Fails when a documentation contradiction this repo already paid to remove
comes back into a normative document. See #288.

The instruction graph has drifted before, and every drift read as an
instruction: a "one-screen" opening line while the app has three tabs, a week
start documented as fixed while Settings offers a picker, a week widget family
documented as current after PR #277 removed it, and literal `L1 n/n` test
counts that were stale in every place one was ever written. Each check here is
one of those reintroductions, matched narrowly — this is not a style linter
and not a word blacklist.

`docs/decisions.md` is exempt by construction: it is the historical log, and a
history is allowed to say what used to be true. If a normative document ever
needs to quote a forbidden phrase as history, add the exact line to that
rule's `allowed_lines` — the allowlist is per-rule and exact, so an exemption
is a reviewable event rather than a loosened pattern.

Run with no arguments to check the working tree; `--self-test` proves each
rule still rejects the contradiction it exists for, against mutation fixtures,
and still accepts the phrasing the current documents actually use. Both run in
CI's Linux gate job on every push, beside the other self-testing gates (#138).

Stdlib only, no network, runnable anywhere.
"""

from __future__ import annotations

import re
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The documents that state current truth. docs/decisions.md is deliberately
# not here — see the module docstring.
NORMATIVE = (
    "CLAUDE.md",
    "SPEC.md",
    "docs/vision.md",
    "docs/ARCHITECTURE.md",
    ".github/pull_request_template.md",
)


@dataclass(frozen=True)
class Rule:
    name: str
    # Which of the NORMATIVE files this rule applies to.
    files: tuple[str, ...]
    # Matched against the whole file, so a phrase split by a hard wrap is
    # still caught; patterns use \s+ where a line break may fall.
    pattern: re.Pattern
    why: str
    # Exact stripped lines that may contain a match anyway. Empty on purpose;
    # adding to one is the reviewable exemption path.
    allowed_lines: tuple[str, ...] = field(default=())


RULES = (
    Rule(
        name="numeric-l1-example",
        files=("CLAUDE.md", ".github/pull_request_template.md"),
        pattern=re.compile(r"\bL1\s+\d+\s*/\s*\d+"),
        why=(
            "a literal test count goes stale the day the suite grows; "
            "instructions and templates say to paste the real Tools/test.sh "
            "output and keep placeholders non-numeric, like `L1 <n>/<n>`"
        ),
    ),
    Rule(
        name="one-screen-claim",
        files=NORMATIVE,
        pattern=re.compile(r"\bone[-\s]+screen\b", re.IGNORECASE),
        why=(
            "the app is three tabs — Widgets, This Week, Settings "
            "(Glow/Views/RootTabView.swift, #238); calling it one screen is "
            "what #288 found misleading agents"
        ),
    ),
    Rule(
        name="forced-monday-claim",
        files=NORMATIVE,
        pattern=re.compile(r"\bforced\s+(?:to\s+)?Monday\b", re.IGNORECASE),
        why=(
            "the week start is a setting — WeekPreferences.firstWeekday, "
            "surfaced in Settings — defaulting to Monday, not forced to it"
        ),
    ),
    Rule(
        name="week-small-as-current",
        files=NORMATIVE,
        pattern=re.compile(
            r"\bsmall,\s+medium,?\s+and\s+large\b"
            r"|\bweek\s+widget\s+is\s+small\b",
            re.IGNORECASE,
        ),
        why=(
            "the week widget is medium and large; the small family was "
            "removed by PR #277, and a current-tense enumeration including it "
            "invites a reconstruction"
        ),
    ),
)

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def line_of(text: str, index: int) -> tuple[int, str]:
    """1-based line number and the full line containing `index`."""
    number = text.count("\n", 0, index) + 1
    start = text.rfind("\n", 0, index) + 1
    end = text.find("\n", index)
    return number, text[start : end if end != -1 else len(text)]


def scan(root: Path) -> list[str]:
    found: list[str] = []
    for relative in NORMATIVE:
        path = root / relative
        if not path.exists():
            found.append(f"{relative}: missing — the normative set names it.")
            continue
        text = path.read_text(encoding="utf-8")
        for rule in RULES:
            if relative not in rule.files:
                continue
            for match in rule.pattern.finditer(text):
                number, line = line_of(text, match.start())
                if line.strip() in rule.allowed_lines:
                    continue
                found.append(
                    f"{relative}:{number}: [{rule.name}] "
                    f"{match.group(0)!r} — {rule.why}."
                )
    return found


# --- self-test -------------------------------------------------------------

# Each mutation is a contradiction that really stood in this repository,
# quoted from the file it stood in; the gate must reject every one.
MUTATIONS = (
    ("CLAUDE.md", '("L1 143/143"). A PR that does not state its result\n', "numeric-l1-example"),
    (".github/pull_request_template.md", 'Paste the result of Tools/test.sh, e.g. "L1 47/47".\n', "numeric-l1-example"),
    ("CLAUDE.md", "A one-screen iPhone habit tracker.\n", "one-screen-claim"),
    ("docs/ARCHITECTURE.md", "There is one screen and three sheets.\n", "one-screen-claim"),
    ("SPEC.md", "using the\nuser's calendar, with `firstWeekday` forced to Monday.\n", "forced-monday-claim"),
    ("docs/ARCHITECTURE.md", "The week widget: small, medium and large, reading the same store.\n", "week-small-as-current"),
    ("docs/vision.md", "The week widget is small, medium and\nlarge, each placed independently.\n", "week-small-as-current"),
)

# Phrasings the current documents legitimately use; the gate must accept them
# all, or it has become the broad blacklist #288 declined.
BENIGN = (
    ("CLAUDE.md", "It prints `L1 <n>/<n>`; that line goes in the PR body.\n"),
    (".github/pull_request_template.md", "L1 ?/?\n"),
    ("SPEC.md", "One weekly-grid screen is enough to see every habit's status.\n"),
    ("SPEC.md", "`WeekPreferences.firstWeekday`, defaulting to Monday and never to the locale's answer.\n"),
    ("SPEC.md", "two families, medium and large. **Small was one of them and is gone** (PR #277).\n"),
    ("docs/ARCHITECTURE.md", "The week widget: medium and large — small was a third family and PR #277 dropped it.\n"),
)


def write_fixture(root: Path, contents: dict[str, str]) -> None:
    for relative in NORMATIVE:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents.get(relative, "clean\n"), encoding="utf-8")


def self_test() -> int:
    problems: list[str] = []

    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)

        # A clean tree passes.
        write_fixture(root, {})
        if scan(root):
            problems.append("a clean fixture tree did not pass")

        # Every mutation is rejected, by the rule that names it.
        for relative, mutation, expected in MUTATIONS:
            write_fixture(root, {relative: mutation})
            hits = scan(root)
            if not any(f"[{expected}]" in hit and hit.startswith(relative) for hit in hits):
                problems.append(
                    f"{relative}: {mutation.strip()!r} was not rejected by {expected} "
                    f"(got: {hits or 'nothing'})"
                )

        # Every benign phrasing is accepted.
        for relative, benign in BENIGN:
            write_fixture(root, {relative: benign})
            hits = scan(root)
            if hits:
                problems.append(
                    f"{relative}: benign {benign.strip()!r} was rejected: {hits}"
                )

        # A missing normative file is itself a failure.
        write_fixture(root, {})
        (root / "SPEC.md").unlink()
        if not any("SPEC.md: missing" in hit for hit in scan(root)):
            problems.append("a missing normative file was not reported")

    if problems:
        print("error: the docs gate does not reject what it claims to reject.", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(
        f"check-docs --self-test: {len(MUTATIONS)} mutations rejected, "
        f"{len(BENIGN)} benign phrasings accepted, missing-file case covered"
    )
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

    for message in scan(ROOT):
        fail(message)

    if failures:
        print("error: a known documentation contradiction is back.", file=sys.stderr)
        for message in failures:
            print(f"  - {message}", file=sys.stderr)
        print(
            "  A historical mention belongs in docs/decisions.md, which this "
            "gate does not read; a normative document states what is true now.",
            file=sys.stderr,
        )
        return 1

    checked = ", ".join(NORMATIVE)
    print(f"check-docs: no known contradiction reintroduced in {checked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
