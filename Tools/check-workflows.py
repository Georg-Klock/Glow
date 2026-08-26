#!/usr/bin/env python3
"""Asserts that the tracked workflows are the execution contract they read as.

Run by CI's gate job on every push, beside the other self-testing checkers.
Exits non-zero, loudly, on any failure.

A workflow file looks reviewable and mostly is not:

  * **`uses: owner/action@v7` is a pointer somebody else holds.** A tag can be
    moved to new code without any commit here, so the reviewed YAML is not the
    code that runs. Every third-party reference must be a full 40-character
    commit SHA — not an abbreviation, which is only a prefix an attacker can
    collide — with the release it was resolved from named in an adjacent
    comment, so a human can still read the file and Dependabot's SHA-diff
    updates stay reviewable. See #287.

  * **An undeclared `permissions:` block is a repository setting, not a fact.**
    The default is read-only today because a setting says so; the workflow
    should be least-privilege by its own declaration. Anything broader than
    the allowlist below fails until the allowlist is widened in the same diff
    as the job that demonstrates the need.

Local actions (`uses: ./…`) are this repository's own commits and need no pin.
`docker://` references are rejected outright: none is used, and one arriving
should be a reviewed decision, not a parse case this file guesses about.

Parsed line-by-line rather than with a YAML library, on purpose: the gate
runner should need nothing outside the standard library, and the constructs
this file has opinions about — a `uses:` line, a `permissions:` block — are
line-shaped. A workflow written strangely enough to defeat that is a workflow
this repository should not merge.

`--self-test` writes mutated workflow fixtures and proves each rule fires,
because a gate nobody has watched fail is a gate nobody knows works. See #138.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

WORKFLOWS = Path(".github/workflows")

# Permissions this repository's workflows may declare. Widening this list is
# the reviewable event, and it belongs in the same change as the job that
# needs the new scope.
ALLOWED_PERMISSIONS = {
    "contents": {"read"},
}

USES = re.compile(r"^\s*-?\s*uses:\s*(?P<ref>[^#\s]+)\s*(?:#\s*(?P<comment>.*))?$")
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
# The first token of the pin comment must name the release the SHA came from.
VERSION_COMMENT = re.compile(r"^v\d+(\.\d+){0,3}\b")
PERMISSION_ENTRY = re.compile(r"^(?P<indent>\s*)(?P<key>[A-Za-z-]+):\s*(?P<value>[^#\s]+)\s*(?:#.*)?$")


def check_workflow(name: str, text: str) -> list[str]:
    """Every policy failure in one workflow, as messages a reviewer can act on."""
    failures: list[str] = []
    lines = text.split("\n")

    declared_permissions = False
    in_permissions = False
    permissions_indent = 0

    for number, line in enumerate(lines, start=1):
        stripped = line.strip()

        # ---- permissions blocks, wherever they appear (workflow or job level)
        if in_permissions:
            indent = len(line) - len(line.lstrip())
            if stripped and indent <= permissions_indent:
                in_permissions = False
            elif stripped and not stripped.startswith("#"):
                entry = PERMISSION_ENTRY.match(line)
                if not entry:
                    failures.append(
                        f"{name}:{number}: unparseable permissions entry {stripped!r}."
                    )
                    continue
                key, value = entry.group("key"), entry.group("value")
                if value not in ALLOWED_PERMISSIONS.get(key, set()):
                    failures.append(
                        f"{name}:{number}: permission {key}: {value} is broader than "
                        "the allowlist in Tools/check-workflows.py. Widening the "
                        "allowlist is the reviewable event."
                    )
                continue

        if stripped.startswith("permissions:"):
            declared_permissions = True
            remainder = stripped[len("permissions:"):].split("#")[0].strip()
            if remainder:
                # The one-line forms: `permissions: read-all`, `write-all`, `{}`.
                if remainder not in ("{}",):
                    failures.append(
                        f"{name}:{number}: permissions: {remainder} grants scopes "
                        "wholesale. Declare each permission on its own line so the "
                        "allowlist can read it."
                    )
            else:
                in_permissions = True
                permissions_indent = len(line) - len(line.lstrip())
            continue

        # ---- uses: references
        match = USES.match(line)
        if not match or stripped.startswith("#"):
            continue
        ref, comment = match.group("ref"), match.group("comment")

        if ref.startswith("./"):
            continue  # this repository's own commit is the pin
        if ref.startswith("docker://"):
            failures.append(
                f"{name}:{number}: {ref} — docker references are not part of this "
                "repository's reviewed policy."
            )
            continue
        if "@" not in ref:
            failures.append(f"{name}:{number}: {ref} has no @ref at all.")
            continue

        action, _, version = ref.partition("@")
        if not FULL_SHA.match(version):
            kind = "an abbreviated SHA" if re.fullmatch(r"[0-9a-f]{4,39}", version) \
                else "a mutable tag or branch"
            failures.append(
                f"{name}:{number}: {action} is pinned to {kind} ({version!r}), not a "
                "full 40-character commit SHA. A ref its owner can move is code "
                "this repository never reviewed."
            )
            continue
        if not comment or not VERSION_COMMENT.match(comment.strip()):
            failures.append(
                f"{name}:{number}: {action}@{version[:12]}… has no adjacent version "
                "comment (e.g. `# v7.0.1`). The SHA is for the machine; the comment "
                "is what keeps the file reviewable by a person."
            )

    if not declared_permissions:
        failures.append(
            f"{name}: no permissions: declaration. The read-only default is a "
            "repository setting a click can change; least privilege belongs in "
            "the reviewed file."
        )

    return failures


def tracked_workflows() -> list[Path]:
    """The workflows git tracks — an untracked draft is not yet policy."""
    listed = subprocess.run(
        ["git", "ls-files", str(WORKFLOWS)],
        capture_output=True, text=True, check=False,
    )
    if listed.returncode == 0:
        return [
            Path(line) for line in listed.stdout.splitlines()
            if line.endswith((".yml", ".yaml"))
        ]
    return sorted(WORKFLOWS.glob("*.yml")) + sorted(WORKFLOWS.glob("*.yaml"))


# ---------------------------------------------------------------- self-test

COMPLIANT = """\
name: Fixture
on: push
permissions:
  contents: read
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: ./local/action
      - run: echo ok
"""


def self_test() -> int:
    """Mutations, each proving this file rejects what it claims to reject."""
    scenarios: list[tuple[str, str, str | None]] = [
        ("a compliant workflow passes", COMPLIANT, None),
        ("a version tag fails",
         COMPLIANT.replace(
             "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
             "actions/checkout@v7"),
         "a mutable tag or branch"),
        ("a branch reference fails",
         COMPLIANT.replace(
             "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
             "actions/checkout@main"),
         "a mutable tag or branch"),
        ("an abbreviated SHA fails",
         COMPLIANT.replace(
             "3d3c42e5aac5ba805825da76410c181273ba90b1", "3d3c42e5aac5"),
         "an abbreviated SHA"),
        ("a missing version comment fails",
         COMPLIANT.replace(" # v7.0.1", ""),
         "no adjacent version comment"),
        ("a comment that is not a version fails",
         COMPLIANT.replace("# v7.0.1", "# pinned, trust me"),
         "no adjacent version comment"),
        ("a missing permissions block fails",
         COMPLIANT.replace("permissions:\n  contents: read\n", ""),
         "no permissions: declaration"),
        ("a write permission fails",
         COMPLIANT.replace("contents: read", "contents: write"),
         "broader than the allowlist"),
        ("an unlisted scope fails",
         COMPLIANT.replace("contents: read", "contents: read\n  id-token: write"),
         "broader than the allowlist"),
        ("wholesale read-all fails",
         COMPLIANT.replace("permissions:\n  contents: read", "permissions: read-all"),
         "grants scopes wholesale"),
        ("a docker reference fails",
         COMPLIANT.replace("uses: ./local/action", "uses: docker://alpine:3.20"),
         "docker references"),
        ("a ref with no pin at all fails",
         COMPLIANT.replace(
             "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
             "actions/checkout"),
         "has no @ref"),
    ]

    bad = 0
    for name, text, expected in scenarios:
        failures = check_workflow("fixture.yml", text)
        if expected is None:
            ok = not failures
            detail = "" if ok else f" — got {failures}"
        else:
            ok = any(expected in failure for failure in failures)
            detail = "" if ok else f" — expected {expected!r} in {failures}"
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{detail}")
        bad += 0 if ok else 1

    # Through the same file discovery a real run uses, so a fixture on disk is
    # read the way a workflow is.
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory) / "broken.yml"
        fixture.write_text(COMPLIANT.replace(" # v7.0.1", ""))
        failures = check_workflow(fixture.name, fixture.read_text())
        ok = any("no adjacent version comment" in failure for failure in failures)
        print(f"  {'ok  ' if ok else 'FAIL'} a fixture read from disk fails the same way")
        bad += 0 if ok else 1

    total = len(scenarios) + 1
    print(f"check-workflows self-test: {total - bad}/{total} scenarios")
    return 1 if bad else 0


# ---------------------------------------------------------------- entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

    workflows = tracked_workflows()
    if not workflows:
        print("error: no tracked workflows found under .github/workflows. A policy "
              "with nothing to check is a policy that cannot notice its subject "
              "vanishing.", file=sys.stderr)
        return 1

    failures: list[str] = []
    for workflow in workflows:
        failures.extend(check_workflow(str(workflow), workflow.read_text()))

    if failures:
        print("error: the tracked workflows do not obey the pinning and permissions "
              "policy.", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"check-workflows: pins, version comments and permissions verified on "
          f"{len(workflows)} workflow{'s' if len(workflows) != 1 else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
