#!/usr/bin/env python3
"""Reads a test run's `.xcresult` and decides whether it is really a pass.

Run by Tools/test.sh after every run, on the result bundle that run wrote, and
separately runnable against any bundle CI kept.

`xcodebuild` exiting 0 answers one question — did anything that ran report a
failure — and CI has been treating that answer as three. It is not:

  * **A target that stops running is not a failure.** A scheme can lose a test
    bundle, or run one with a third of its tests, and every test that did run
    still passes. Tools/test.sh already refused a run that reported *no* tests;
    that check cannot see 370 becoming 40, and it certainly cannot see
    `GlowRenderTests` disappearing while `GlowTests` keeps the total high. The
    floors here are per bundle for exactly that reason.

  * **A skipped test is not a passed test.** It is reported next to the passes
    and is easy to read as one.

  * **A warning is not nothing.** The compiler's opinion arrives in the result
    bundle and, until now, in nobody's terminal.

**Runtime warnings are counted, reported, and not yet fatal.** The result bundle
records them as one opaque `Multiple Runtime Warnings` node per test — 92 of
them on a run that passes — so making them fail the build means enumerating them
first, and that is its own piece of work rather than a line in this file. The
count is in `validation.json` and in CI's run summary, where a person sees it
beside gates that do fail.

The floors are minima, not equalities, so adding a test never touches this
file. Lowering one is the reviewable event: it means tests were deleted, and it
should be as visible in a diff as deleting them was.

Everything here is a pure function of parsed JSON, and `--self-test` runs the
mutations past it — a gate nobody has watched fail is a gate nobody knows
works. See #138.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_INVENTORY = Path(__file__).resolve().parent / "test-inventory.json"

# The only result a test node may carry. "Expected Failure" is deliberately not
# here: this project has none, and a suite that starts having them should say so
# in a review rather than in a result bundle nobody reads.
PASSING = "Passed"


# ---------------------------------------------------------------- reading


def xcresult(path: Path, *command: str) -> dict:
    """One `xcresulttool get` call, as parsed JSON."""
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", *command, "--path", str(path), "--compact"],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"xcresulttool get {' '.join(command)} failed on {path}:\n"
            + result.stderr.decode(errors="replace")
        )
    return json.loads(result.stdout)


def read(path: Path) -> dict:
    return {
        "build": xcresult(path, "build-results"),
        "tests": xcresult(path, "test-results", "tests"),
        "summary": xcresult(path, "test-results", "summary"),
    }


def read_attachments(directory: Path | None) -> list[dict]:
    """The manifest `xcresulttool export attachments` writes, or nothing."""
    if directory is None:
        return []
    manifest = directory / "manifest.json"
    if not manifest.exists():
        return []
    return json.loads(manifest.read_text())


# ---------------------------------------------------------------- the gate


def bundles_in(tests: dict) -> dict[str, dict]:
    """Every test bundle in the report, with its test cases counted by result."""
    found: dict[str, dict] = {}

    def walk(node, bundle):
        kind = node.get("nodeType")
        if kind == "Unit test bundle" or kind == "UI test bundle":
            bundle = node.get("name")
            found.setdefault(
                bundle, {"total": 0, "byResult": {}, "notPassed": [], "runtimeWarnings": 0}
            )
        if kind == "Test Case" and bundle is not None:
            entry = found[bundle]
            result = node.get("result", "Unknown")
            entry["total"] += 1
            entry["byResult"][result] = entry["byResult"].get(result, 0) + 1
            if result != PASSING:
                entry["notPassed"].append(f"{node.get('name')} [{result}]")
        # Counted, reported, and deliberately not fatal yet — see the note at
        # the top of this file.
        if kind == "Runtime Warning" and bundle is not None:
            found[bundle]["runtimeWarnings"] += 1
        for child in node.get("children") or []:
            walk(child, bundle)

    for node in tests.get("testNodes") or []:
        walk(node, None)
    return found


def fingerprint(diagnostic: dict) -> str:
    """What an allowlist entry has to name.

    The type and the message, and not the source URL: the URL carries an
    absolute path and a timestamp, so a fingerprint built from it would be
    unique to one checkout on one machine and would allowlist nothing twice.
    """
    return f"{diagnostic.get('issueType', 'Diagnostic')}: {diagnostic.get('message', '')}"


# `xcresulttool export attachments` reports a name the test never chose:
# "render-signatures-actual" comes back as
# "render-signatures-actual_0_E13EAD92-….json" — an index and the attachment's
# uuid, wedged in before the extension. Matching has to happen on the name the
# test asked for, or a check for "-diff.png" reports it missing while the file
# is sitting in the directory.
EXPORT_SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}(?=\.[^.]+$)")


def readable(name: str) -> str:
    return EXPORT_SUFFIX.sub("", name)


def attachment_names(manifest: list[dict], test: str | None = None) -> list[str]:
    names = []
    for entry in manifest:
        if test is not None and entry.get("testIdentifier") != test:
            continue
        for attachment in entry.get("attachments") or []:
            names.append(readable(attachment.get("suggestedHumanReadableName", "")))
    return names


def validate(build: dict, tests: dict, summary: dict, manifest: list[dict], inventory: dict) -> tuple[list[str], dict]:
    """The whole decision, as a pure function. Returns (failures, report)."""
    failures: list[str] = []
    found = bundles_in(tests)

    # 1. The build itself.
    if build.get("status") != "succeeded":
        failures.append(f"the build did not succeed (status {build.get('status')!r}).")
    for error in build.get("errors") or []:
        failures.append(f"build error: {fingerprint(error)}")

    # 2. Diagnostics. Narrow, fingerprinted, documented — and empty is the
    #    target state, not an accident.
    allowlist = inventory.get("diagnosticAllowlist", [])
    allowed = {entry["fingerprint"] for entry in allowlist if "fingerprint" in entry}
    # A prefix, for the one shape a fingerprint cannot name: a diagnostic whose
    # message carries an absolute path, which is different on every machine.
    prefixes = tuple(entry["fingerprintPrefix"] for entry in allowlist if "fingerprintPrefix" in entry)
    diagnostics = (build.get("warnings") or []) + (build.get("analyzerWarnings") or [])
    unexpected = []
    for diagnostic in diagnostics:
        mark = fingerprint(diagnostic)
        if mark not in allowed and not (prefixes and mark.startswith(prefixes)):
            unexpected.append(mark)
    for mark in sorted(set(unexpected)):
        failures.append(
            f"undeclared diagnostic: {mark}\n"
            "      Fix it, or add it to Tools/test-inventory.json with a reason and an issue."
        )

    # 3. Every bundle the repository says it has, still running, still whole.
    for name, rule in sorted(inventory.get("bundles", {}).items()):
        floor = rule["minimum"]
        entry = found.get(name)
        if entry is None:
            failures.append(
                f"{name} did not run at all. The scheme has lost a test bundle; "
                f"every test in the others can still pass."
            )
            continue
        if entry["total"] < floor:
            failures.append(
                f"{name} ran {entry['total']} tests; the reviewed floor is {floor}. "
                "Tests were deleted or stopped being discovered. If that was deliberate, "
                "lower the floor in Tools/test-inventory.json in the same change."
            )
        for description in entry["notPassed"]:
            failures.append(f"{name}: {description}")

    # 4. Bundles nobody declared. A new test target that CI does not know to
    #    require is a target that can vanish again unnoticed.
    for name in sorted(set(found) - set(inventory.get("bundles", {}))):
        failures.append(
            f"{name} ran but is not declared in Tools/test-inventory.json, so nothing "
            "would notice it disappearing. Add it with a floor."
        )

    # 5. The run's own summary, as a cross-check on the walk above.
    if summary.get("failedTests"):
        failures.append(f"the run reports {summary['failedTests']} failed tests.")
    if summary.get("skippedTests"):
        failures.append(
            f"the run reports {summary['skippedTests']} skipped tests. "
            "A skipped test is not a passing one."
        )
    walked = sum(entry["total"] for entry in found.values())
    if summary.get("totalTestCount") not in (None, walked):
        failures.append(
            f"the summary counts {summary['totalTestCount']} tests and the report tree "
            f"has {walked}. One of them is not describing this run."
        )

    # 6. Evidence. Artifacts that only exist on a good day cannot be used to
    #    review a bad one.
    names = attachment_names(manifest)
    for required in inventory.get("requiredAttachments", []):
        if required not in names:
            failures.append(
                f"the run attached no {required}. The visual baseline records what it "
                "rendered on every run; its absence means the gate did not run."
            )

    visual = inventory.get("visualFailureAttachments")
    if visual:
        entry = found.get(visual["bundle"], {"notPassed": []})
        if entry["notPassed"]:
            got = attachment_names(manifest)
            for suffix in visual["names"]:
                if not any(name.endswith(suffix) for name in got):
                    failures.append(
                        f"{visual['bundle']} failed and attached no {suffix}. A visual "
                        "failure has to leave something a person can look at."
                    )

    report = {
        "result": "failed" if failures else "passed",
        "total": walked,
        "bundles": {
            name: {
                "total": entry["total"],
                "byResult": entry["byResult"],
                "minimum": inventory.get("bundles", {}).get(name, {}).get("minimum"),
                "runtimeWarnings": entry.get("runtimeWarnings", 0),
            }
            for name, entry in sorted(found.items())
        },
        "diagnostics": sorted(set(fingerprint(d) for d in diagnostics)),
        "undeclaredDiagnostics": sorted(set(unexpected)),
        "attachments": sorted(names),
        "failures": failures,
    }
    return failures, report


def markdown(report: dict) -> str:
    """The same verdict, for a CI run summary."""
    lines = [f"### Tests: {report['result']} — {report['total']} tests", ""]
    lines += ["| bundle | tests | floor | runtime warnings |", "| --- | --- | --- | --- |"]
    for name, entry in report["bundles"].items():
        floor = entry["minimum"] if entry["minimum"] is not None else "undeclared"
        lines.append(
            f"| {name} | {entry['total']} | {floor} | {entry.get('runtimeWarnings', 0)} |"
        )
    if report["failures"]:
        lines += ["", "### Why this is not a pass", ""]
        lines += [f"- {failure.splitlines()[0]}" for failure in report["failures"]]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- self-test


def self_test() -> int:
    """Mutations, each one proving this file rejects what it claims to reject.

    Not hypothetical mutations: every scenario below is a way CI has been, or
    could be, green while the repository was not.
    """
    clean_build = {"status": "succeeded", "errorCount": 0, "warnings": [], "errors": []}

    def node(name, result=PASSING):
        return {"nodeType": "Test Case", "name": name, "result": result}

    def tests_tree(counts):
        return {
            "testNodes": [{
                "nodeType": "Test Plan", "name": "Glow", "result": PASSING,
                "children": [
                    {
                        "nodeType": "Unit test bundle", "name": name, "result": PASSING,
                        "children": [node(f"{name}{i}") for i in range(count)],
                    }
                    for name, count in counts.items()
                ],
            }]
        }

    def summary(total, failed=0, skipped=0):
        return {"totalTestCount": total, "failedTests": failed, "skippedTests": skipped}

    inventory = {
        "bundles": {"GlowTests": {"minimum": 300}, "GlowRenderTests": {"minimum": 12}},
        "requiredAttachments": ["render-signatures-actual.json"],
        "visualFailureAttachments": {
            "bundle": "GlowRenderTests",
            "names": ["-expected.png", "-actual.png", "-diff.png"],
        },
        "diagnosticAllowlist": [],
    }
    manifest = [{
        "testIdentifier": "RenderBaselineTests/framesMatchBaseline()",
        "attachments": [{"suggestedHumanReadableName":
                         "render-signatures-actual_0_E13EAD92-777B-4F8E-B68A-4A24EF56BF7C.json"}],
    }]
    good = tests_tree({"GlowTests": 320, "GlowRenderTests": 12})

    scenarios: list[tuple[str, tuple, str | None]] = [
        ("a clean run passes",
         (clean_build, good, summary(332), manifest, inventory), None),
        ("a missing render bundle fails",
         (clean_build, tests_tree({"GlowTests": 320}), summary(320), manifest, inventory),
         "GlowRenderTests did not run"),
        ("a shrunken bundle fails even when the total is high",
         (clean_build, tests_tree({"GlowTests": 400, "GlowRenderTests": 3}), summary(403), manifest, inventory),
         "the reviewed floor is 12"),
        ("an undeclared bundle fails",
         (clean_build, tests_tree({"GlowTests": 320, "GlowRenderTests": 12, "GlowSmokeTests": 1}),
          summary(333), manifest, inventory),
         "not declared in Tools/test-inventory.json"),
        ("one failed test fails",
         (clean_build,
          {"testNodes": [{"nodeType": "Test Plan", "name": "Glow", "children": [
              {"nodeType": "Unit test bundle", "name": "GlowTests",
               "children": [node(f"t{i}") for i in range(319)] + [node("bad", "Failed")]},
              {"nodeType": "Unit test bundle", "name": "GlowRenderTests",
               "children": [node(f"r{i}") for i in range(12)]},
          ]}]},
          summary(332, failed=1), manifest, inventory),
         "bad [Failed]"),
        ("a skipped test fails",
         (clean_build,
          {"testNodes": [{"nodeType": "Test Plan", "name": "Glow", "children": [
              {"nodeType": "Unit test bundle", "name": "GlowTests",
               "children": [node(f"t{i}") for i in range(319)] + [node("later", "Skipped")]},
              {"nodeType": "Unit test bundle", "name": "GlowRenderTests",
               "children": [node(f"r{i}") for i in range(12)]},
          ]}]},
          summary(332, skipped=1), manifest, inventory),
         "later [Skipped]"),
        ("a compiler warning fails",
         ({**clean_build, "warnings": [
             {"issueType": "Swift Compiler Warning", "message": "'x' is deprecated"}]},
          good, summary(332), manifest, inventory),
         "undeclared diagnostic"),
        ("a warning allowlisted by prefix passes",
         ({**clean_build, "warnings": [
             {"issueType": "Uncategorized",
              "message": "Aggregation tool emitted warnings:\n/Users/somebody/…profraw: counter mismatch"}]},
          good, summary(332), manifest,
          {**inventory, "diagnosticAllowlist": [
              {"fingerprintPrefix": "Uncategorized: Aggregation tool emitted warnings:",
               "reason": "self-test", "issue": "#138"}]}),
         None),
        ("an allowlisted warning passes",
         ({**clean_build, "warnings": [
             {"issueType": "Swift Compiler Warning", "message": "'x' is deprecated"}]},
          good, summary(332), manifest,
          {**inventory, "diagnosticAllowlist": [
              {"fingerprint": "Swift Compiler Warning: 'x' is deprecated",
               "reason": "self-test", "issue": "#138"}]}),
         None),
        ("a build error fails",
         ({"status": "failed", "errorCount": 1,
           "errors": [{"issueType": "Swift Compiler Error", "message": "no such module"}]},
          good, summary(332), manifest, inventory),
         "the build did not succeed"),
        ("a run with no attached render manifest fails",
         (clean_build, good, summary(332), [], inventory),
         "attached no render-signatures-actual.json"),
        ("a visual failure with no images fails",
         (clean_build,
          {"testNodes": [{"nodeType": "Test Plan", "name": "Glow", "children": [
              {"nodeType": "Unit test bundle", "name": "GlowTests",
               "children": [node(f"t{i}") for i in range(320)]},
              {"nodeType": "Unit test bundle", "name": "GlowRenderTests",
               "children": [node(f"r{i}") for i in range(11)] + [node("framesMatchBaseline()", "Failed")]},
          ]}]},
          summary(332, failed=1), manifest, inventory),
         "attached no -diff.png"),
        ("a summary that disagrees with the tree fails",
         (clean_build, good, summary(9999), manifest, inventory),
         "is not describing this run"),
    ]

    bad = 0
    for name, arguments, expected in scenarios:
        failures, _ = validate(*arguments)
        if expected is None:
            ok = not failures
            detail = "" if ok else f" — got {failures}"
        else:
            ok = any(expected in failure for failure in failures)
            detail = "" if ok else f" — expected {expected!r} in {failures}"
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{detail}")
        bad += 0 if ok else 1

    print(f"validate-test-result self-test: {len(scenarios) - bad}/{len(scenarios)} scenarios")
    return 1 if bad else 0


# ---------------------------------------------------------------- entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xcresult", type=Path)
    parser.add_argument("--attachments", type=Path,
                        help="directory written by `xcresulttool export attachments`")
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--summary-output", type=Path,
                        help="the same verdict as markdown, for a CI run summary")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

    if arguments.xcresult is None:
        parser.error("--xcresult is required unless --self-test is given")
    if not arguments.xcresult.exists():
        print(f"error: {arguments.xcresult} does not exist. A run that kept no result "
              "bundle cannot be validated, and an unvalidated run is not a pass.",
              file=sys.stderr)
        return 1

    inventory = json.loads(arguments.inventory.read_text())
    data = read(arguments.xcresult)
    manifest = read_attachments(arguments.attachments)
    failures, report = validate(
        data["build"], data["tests"], data["summary"], manifest, inventory
    )

    if arguments.json_output:
        arguments.json_output.parent.mkdir(parents=True, exist_ok=True)
        arguments.json_output.write_text(json.dumps(report, indent=2) + "\n")

    if arguments.summary_output:
        arguments.summary_output.parent.mkdir(parents=True, exist_ok=True)
        arguments.summary_output.write_text(markdown(report))

    for name, entry in report["bundles"].items():
        floor = entry["minimum"]
        print(f"validate: {name} {entry['total']} tests"
              + (f" (floor {floor})" if floor is not None else " (undeclared)"))

    if failures:
        print("\nerror: the run reported a pass, and it is not one.", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"validate: {report['total']} tests, every declared bundle present, "
          "no undeclared diagnostics")
    return 0


if __name__ == "__main__":
    sys.exit(main())
