#!/usr/bin/env python3
"""Reads a built product and decides whether it is shippable.

Run by CI on the unsigned Release build for the device SDK, and by
Tools/ship-testflight.sh on the archive and again on the exported `.ipa`
immediately before the upload. **One file, two callers, on purpose** — a gate
and a release path that each carry their own idea of what "matching" means will
eventually disagree, and the release path is the one nobody watches.

What it is for. `project.yml` sets `MARKETING_VERSION`, and until #133 the host
target did not read it: xcodegen wrote its own `CFBundleShortVersionString`
default, so every build shipped a host at `1.0` / `1` beside a widget at
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`. An appex whose version
differs from its host is a submission rejection, and nothing in the build says
so — the app installs, the widget runs, and the answer arrives from App Store
Connect after the upload.

Everything checked here has that shape: a fact about the *shipped bundle* that
no build failure reports.

  * **Version parity.** The host and every appex must agree on both keys, and
    the message names both values, because "they differ" without the numbers
    is a message that sends the reader back to `plutil`.

  * **Unexpanded build settings.** A literal `$(MARKETING_VERSION)` in a
    shipped plist is a plist Xcode never substituted into. It reads as a
    version until it is read closely.

  * **Identity.** The declared bundle identifiers, and the rule that an appex's
    identifier is the host's plus one component — Apple's, and enforced only at
    install time.

  * **Manifests.** `PrivacyInfo.xcprivacy` at each bundle root. #132 put them
    there and tests assert it on the simulator build; this is the same
    assertion on the artifact that actually goes up.

  * **Entitlements and profile** (`--require-signing`). The exact App Group,
    read back out of the signature rather than out of the source file, and an
    embedded profile that has not expired. CI's build is unsigned by design, so
    it does not ask for these; the release path does.

The expectations are declared in Tools/test-inventory.json, next to the test
floors, so what a build has to contain is reviewable in a diff rather than
spelled out in a script argument.

Fail closed, everywhere. An artifact that does not exist, an archive with no
app in it, an appex nobody declared: each is a failure, not a shrug. The
validator this replaces treated an absent build as a pass, which is the exact
failure mode that makes a green tick worthless.

`--self-test` fabricates bundles on disk and runs them past the same code path,
because a gate nobody has watched fail is a gate nobody knows works. See #138.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_INVENTORY = Path(__file__).resolve().parent / "test-inventory.json"

# A build setting Xcode never substituted, still sitting in the shipped plist.
UNEXPANDED = re.compile(r"\$[({]")

VERSION_KEYS = ("CFBundleShortVersionString", "CFBundleVersion")


# ---------------------------------------------------------------- reading


class Unreadable(Exception):
    """The artifact could not be opened far enough to have an opinion about."""


def read_plist(path: Path) -> dict:
    return plistlib.loads(path.read_bytes())


def run_tool(*command: str) -> subprocess.CompletedProcess | None:
    """One macOS tool, or None where the tool does not exist.

    `--self-test` runs on the Linux gate runner, which has neither `codesign`
    nor `security`. Everything those two answer is about a *signed* artifact,
    which only exists on the machine that signed it; the decision made from
    their answers is exercised there as fabricated facts instead.
    """
    try:
        return subprocess.run(command, capture_output=True, check=False)
    except (FileNotFoundError, OSError):
        return None


def entitlements_of(bundle: Path) -> dict | None:
    """What the signature actually grants, or None when nothing is signed.

    Read out of the signature rather than out of the entitlements file, because
    the whole class of bug this guards is codesign silently dropping what the
    file asked for.
    """
    result = run_tool("codesign", "-d", "--entitlements", ":-", "--xml", str(bundle))
    if result is None or result.returncode != 0 or not result.stdout:
        return None
    data = result.stdout
    # Older codesign prefixes an 8-byte blob header before the XML.
    start = data.find(b"<?xml")
    if start > 0:
        data = data[start:]
    try:
        return plistlib.loads(data)
    except Exception:  # noqa: BLE001 — an unparseable signature is "not signed"
        return None


def profile_expiry(bundle: Path) -> datetime | None:
    """The embedded provisioning profile's expiry, or None when there is none."""
    profile = bundle / "embedded.mobileprovision"
    if not profile.exists():
        return None
    raw = profile.read_bytes()
    # A mobileprovision is a CMS envelope around an XML plist. `security cms -D`
    # is the supported way in and is macOS-only; the slice is the fallback, so
    # that a Linux runner asked to look at one says something useful instead of
    # crashing.
    decoded = run_tool("security", "cms", "-D", "-i", str(profile))
    payload = (
        decoded.stdout
        if decoded is not None and decoded.returncode == 0 and decoded.stdout
        else None
    )
    if payload is None:
        start = raw.find(b"<?xml")
        end = raw.find(b"</plist>")
        if start < 0 or end < 0:
            return None
        payload = raw[start : end + len(b"</plist>")]
    try:
        expiry = plistlib.loads(payload).get("ExpirationDate")
    except Exception:  # noqa: BLE001
        return None
    if not isinstance(expiry, datetime):
        return None
    # plistlib returns naive datetimes that are UTC.
    return expiry.replace(tzinfo=timezone.utc)


def inspect_bundle(path: Path) -> dict:
    """One `.app` or `.appex`, as the facts this file has opinions about."""
    info = path / "Info.plist"
    if not info.exists():
        raise Unreadable(f"{path} has no Info.plist, so it is not a bundle.")
    try:
        plist = read_plist(info)
    except Exception as error:  # noqa: BLE001 — the message is the product
        raise Unreadable(f"{path}/Info.plist is not a readable plist ({error}).") from error
    return {
        "name": path.name,
        "path": str(path),
        "identifier": plist.get("CFBundleIdentifier"),
        "shortVersion": plist.get("CFBundleShortVersionString"),
        "version": plist.get("CFBundleVersion"),
        "resources": sorted(child.name for child in path.iterdir()),
        "entitlements": entitlements_of(path),
        "profileExpiry": profile_expiry(path),
    }


def host_app_in(path: Path) -> Path:
    """The one host `.app` inside an artifact, whatever kind of artifact it is.

    Deliberately not `find … | head -1`. An artifact with no app, or with more
    than one, is a question — and answering it by taking whichever the
    filesystem listed first is how a validator ends up validating something
    nobody shipped.
    """
    if path.suffix == ".app":
        return path
    if path.suffix == ".xcarchive":
        applications = path / "Products" / "Applications"
        candidates = sorted(applications.glob("*.app")) if applications.is_dir() else []
    elif path.is_dir():
        candidates = sorted(path.glob("*.app"))
    else:
        raise Unreadable(f"{path} is not a .app, a .xcarchive, an .ipa or a directory of apps.")

    if not candidates:
        raise Unreadable(f"{path} contains no .app. There is nothing here to ship.")
    if len(candidates) > 1:
        names = ", ".join(c.name for c in candidates)
        raise Unreadable(f"{path} contains {len(candidates)} apps ({names}); it should contain one.")
    return candidates[0]


def inspect_artifact(path: Path) -> dict:
    """The host app and every appex it embeds."""
    host_path = host_app_in(path)
    host = inspect_bundle(host_path)
    plugins = host_path / "PlugIns"
    extensions = []
    if plugins.is_dir():
        for child in sorted(plugins.iterdir()):
            if child.suffix == ".appex":
                extensions.append(inspect_bundle(child))
    return {"host": host, "extensions": extensions}


def unpack_ipa(ipa: Path, into: Path) -> Path:
    """The Payload directory of an exported `.ipa`."""
    if not zipfile.is_zipfile(ipa):
        raise Unreadable(f"{ipa} is not a zip archive, so it is not an .ipa.")
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(into)
    payload = into / "Payload"
    if not payload.is_dir():
        raise Unreadable(f"{ipa} has no Payload/ directory.")
    return payload


# ---------------------------------------------------------------- the gate


def describe(value) -> str:
    return "absent" if value is None else repr(value)


def validate(artifact: dict, expectations: dict, *, require_signing: bool, now: datetime) -> list[str]:
    """The whole decision, as a pure function of already-read facts."""
    failures: list[str] = []
    host = artifact["host"]
    extensions = artifact["extensions"]

    declared_host = expectations.get("host", {})
    declared_extensions = expectations.get("extensions", {})
    app_group = expectations.get("appGroup")

    def check_identity(bundle: dict, declared: dict, label: str) -> None:
        want = declared.get("bundleIdentifier")
        got = bundle["identifier"]
        if want and got != want:
            failures.append(
                f"{label}: CFBundleIdentifier is {describe(got)}, and the repository "
                f"declares {want!r}."
            )
        for resource in declared.get("requiredResources", []):
            if resource not in bundle["resources"]:
                failures.append(
                    f"{label}: no {resource} at the bundle root. It is only a "
                    "declaration once it is inside the thing being shipped."
                )

    def check_versions_readable(bundle: dict, label: str) -> None:
        for key, field in zip(VERSION_KEYS, ("shortVersion", "version")):
            value = bundle[field]
            if not value:
                failures.append(f"{label}: {key} is {describe(value)}.")
            elif UNEXPANDED.search(str(value)):
                failures.append(
                    f"{label}: {key} is {value!r} — an unexpanded build setting. "
                    "Xcode never substituted it, and it reads as a version."
                )

    # 1. The host itself.
    check_identity(host, declared_host, host["name"])
    check_versions_readable(host, host["name"])

    # 2. Every extension the repository says ships, and no others.
    found = {bundle["name"]: bundle for bundle in extensions}
    for name in sorted(declared_extensions):
        if name not in found:
            failures.append(
                f"{name} is not in {host['name']}/PlugIns. The repository declares it, "
                "and an app that ships without its widget installs and runs."
            )
    for name in sorted(set(found) - set(declared_extensions)):
        failures.append(
            f"{name} ships and is not declared in Tools/test-inventory.json, so nothing "
            "would notice it changing. Add it, or stop embedding it."
        )

    # 3. Identity, manifests and version parity, per extension.
    for name in sorted(set(found) & set(declared_extensions)):
        bundle = found[name]
        declared = declared_extensions[name]
        check_identity(bundle, declared, name)
        check_versions_readable(bundle, name)

        host_id = host["identifier"]
        if host_id and bundle["identifier"] and not str(bundle["identifier"]).startswith(f"{host_id}."):
            failures.append(
                f"{name}: CFBundleIdentifier {bundle['identifier']!r} is not "
                f"{host_id!r} plus one component. iOS refuses to install it."
            )

        for key, field in zip(VERSION_KEYS, ("shortVersion", "version")):
            if bundle[field] != host[field]:
                failures.append(
                    f"{name}: {key} is {describe(bundle[field])} and {host['name']}'s is "
                    f"{describe(host[field])}. An extension whose version differs from its "
                    "host is an App Store rejection, after the upload."
                )

    # 4. What the signature really grants. CI builds unsigned on purpose, so
    #    this is asked for by the release path and not by the gate.
    if require_signing:
        for bundle in [host] + extensions:
            label = bundle["name"]
            entitlements = bundle["entitlements"]
            if entitlements is None:
                failures.append(
                    f"{label}: not signed, or its signature carries no entitlements. "
                    "This artifact is one upload away from the App Store."
                )
                continue
            if app_group:
                groups = entitlements.get("com.apple.security.application-groups") or []
                if app_group not in groups:
                    failures.append(
                        f"{label}: the signature grants {groups!r}, not {app_group!r}. "
                        "The entitlements file asked for it and codesign dropped it; "
                        "the app works and the widget shows nothing."
                    )

            expiry = bundle["profileExpiry"]
            if expiry is None:
                failures.append(
                    f"{label}: no readable embedded.mobileprovision. A distribution "
                    "bundle carries one."
                )
            elif expiry <= now:
                failures.append(
                    f"{label}: its provisioning profile expired on "
                    f"{expiry.date().isoformat()}, and today is {now.date().isoformat()}."
                )

    return failures


def report(artifact: dict) -> str:
    lines = []
    for bundle in [artifact["host"]] + artifact["extensions"]:
        lines.append(
            f"  {bundle['name']}: {bundle['identifier']} "
            f"{bundle['shortVersion']} ({bundle['version']})"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------- self-test


def fabricate(root: Path, *, host_version=("0.1", "42"), widget_version=("0.1", "42"),
              host_id="com.georgklock.glow", widget_id="com.georgklock.glow.widget",
              widget=True, manifests=True, extra_appex=False) -> Path:
    """A `.app` on disk, wrong in whichever way the scenario asks for."""
    app = root / "Glow.app"
    (app / "PlugIns").mkdir(parents=True)

    def write(bundle: Path, identifier, versions, manifest):
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": versions[0],
            "CFBundleVersion": versions[1],
        }))
        if manifest:
            (bundle / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({}))

    write(app, host_id, host_version, manifests)
    if widget:
        write(app / "PlugIns" / "GlowWidget.appex", widget_id, widget_version, manifests)
    if extra_appex:
        write(app / "PlugIns" / "Rogue.appex", "com.georgklock.glow.rogue", host_version, True)
    return app


def self_test() -> int:
    """Mutations, each one proving this file rejects what it claims to reject.

    Every scenario is a build that would have uploaded: the version mismatch is
    the one #133 was opened for and the one this repository actually shipped in
    every build before it.
    """
    expectations = {
        "host": {"bundleIdentifier": "com.georgklock.glow",
                 "requiredResources": ["PrivacyInfo.xcprivacy"]},
        "extensions": {"GlowWidget.appex": {
            "bundleIdentifier": "com.georgklock.glow.widget",
            "requiredResources": ["PrivacyInfo.xcprivacy"]}},
        "appGroup": "group.com.georgklock.glow",
    }
    now = datetime(2026, 8, 22, tzinfo=timezone.utc)

    # On disk, through the same inspect + validate the callers use.
    on_disk: list[tuple[str, dict, str | None]] = [
        ("a matched build passes", {}, None),
        ("a mismatched marketing version fails",
         {"host_version": ("1.0", "42")},
         "CFBundleShortVersionString is '0.1' and Glow.app's is '1.0'"),
        ("a mismatched build number fails",
         {"widget_version": ("0.1", "41")},
         "CFBundleVersion is '41' and Glow.app's is '42'"),
        ("the shipped-today mismatch fails",  # host 1.0/1, widget 0.1/1
         {"host_version": ("1.0", "1"), "widget_version": ("0.1", "1")},
         "is '0.1' and Glow.app's is '1.0'"),
        ("an unexpanded build setting fails",
         {"host_version": ("$(MARKETING_VERSION)", "42"),
          "widget_version": ("$(MARKETING_VERSION)", "42")},
         "an unexpanded build setting"),
        ("a missing widget fails",
         {"widget": False},
         "GlowWidget.appex is not in Glow.app/PlugIns"),
        ("an undeclared appex fails",
         {"extra_appex": True},
         "Rogue.appex ships and is not declared"),
        ("a missing privacy manifest fails",
         {"manifests": False},
         "no PrivacyInfo.xcprivacy at the bundle root"),
        ("a wrong host bundle identifier fails",
         {"host_id": "com.georgklock.glow.beta"},
         "the repository declares 'com.georgklock.glow'"),
        ("an appex outside the host's identifier fails",
         {"widget_id": "com.georgklock.widget"},
         "is not 'com.georgklock.glow' plus one component"),
    ]

    bad = 0
    for name, arguments, expected in on_disk:
        with tempfile.TemporaryDirectory() as directory:
            app = fabricate(Path(directory), **arguments)
            try:
                failures = validate(
                    inspect_artifact(app), expectations, require_signing=False, now=now
                )
            except Unreadable as error:
                failures = [str(error)]
        bad += 0 if report_scenario(name, failures, expected) else 1

    # An absent host, through the same entry point a caller uses.
    with tempfile.TemporaryDirectory() as directory:
        try:
            inspect_artifact(Path(directory))
            failures = []
        except Unreadable as error:
            failures = [str(error)]
    bad += 0 if report_scenario(
        "an absent host fails rather than passing", failures, "contains no .app"
    ) else 1

    # Signing facts cannot be fabricated on a Linux runner, and the reading of
    # them is one subprocess away from here. The decision is the part that has
    # to be watched failing.
    signed = {
        "host": {"name": "Glow.app", "identifier": "com.georgklock.glow",
                 "shortVersion": "0.1", "version": "42", "resources": ["PrivacyInfo.xcprivacy"],
                 "entitlements": {"com.apple.security.application-groups":
                                  ["group.com.georgklock.glow"]},
                 "profileExpiry": datetime(2027, 1, 1, tzinfo=timezone.utc)},
        "extensions": [],
    }
    stripped = {**signed, "host": {**signed["host"], "entitlements": {}}}
    unsigned = {**signed, "host": {**signed["host"], "entitlements": None}}
    expired = {**signed, "host": {**signed["host"],
                                  "profileExpiry": datetime(2026, 8, 21, tzinfo=timezone.utc)}}
    no_profile = {**signed, "host": {**signed["host"], "profileExpiry": None}}
    only_host = {**expectations, "extensions": {}}

    for name, artifact, expected in [
        ("a signed build with the group passes", signed, None),
        ("a stripped App Group entitlement fails", stripped,
         "the signature grants [], not 'group.com.georgklock.glow'"),
        ("an unsigned artifact fails the release path", unsigned, "not signed"),
        ("an expired provisioning profile fails", expired, "expired on 2026-08-21"),
        ("a distribution bundle with no profile fails", no_profile,
         "no readable embedded.mobileprovision"),
    ]:
        failures = validate(artifact, only_host, require_signing=True, now=now)
        bad += 0 if report_scenario(name, failures, expected) else 1

    total = len(on_disk) + 6
    print(f"check-release-build self-test: {total - bad}/{total} scenarios")
    return 1 if bad else 0


def report_scenario(name: str, failures: list[str], expected: str | None) -> bool:
    if expected is None:
        ok = not failures
        detail = "" if ok else f" — got {failures}"
    else:
        ok = any(expected in failure for failure in failures)
        detail = "" if ok else f" — expected {expected!r} in {failures}"
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{detail}")
    return ok


# ---------------------------------------------------------------- entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", nargs="?", type=Path,
                        help="a .app, a .xcarchive or an .ipa")
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    parser.add_argument("--require-signing", action="store_true",
                        help="also check entitlements and profile expiry; for the release path")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

    if arguments.artifact is None:
        parser.error("an artifact path is required unless --self-test is given")
    if not arguments.artifact.exists():
        print(f"error: {arguments.artifact} does not exist. An artifact nobody built "
              "cannot be validated, and an unvalidated artifact is not shippable.",
              file=sys.stderr)
        return 1

    inventory = json.loads(arguments.inventory.read_text())
    expectations = inventory.get("release")
    if not expectations:
        print(f"error: {arguments.inventory} declares no \"release\" section, so there is "
              "nothing to check against.", file=sys.stderr)
        return 1

    temporary = None
    try:
        path = arguments.artifact
        if path.suffix == ".ipa":
            temporary = Path(tempfile.mkdtemp(prefix="glow-ipa-"))
            path = unpack_ipa(path, temporary)
        artifact = inspect_artifact(path)
        failures = validate(
            artifact, expectations,
            require_signing=arguments.require_signing,
            now=datetime.now(timezone.utc),
        )
    except Unreadable as error:
        print(f"error: {arguments.artifact} is not a shippable build.", file=sys.stderr)
        print(f"  - {error}", file=sys.stderr)
        return 1
    finally:
        if temporary is not None:
            shutil.rmtree(temporary, ignore_errors=True)

    print(f"check-release-build: {arguments.artifact}")
    print(report(artifact))

    if failures:
        print("\nerror: this build is not the build this repository ships.", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    signing = " signature and profile," if arguments.require_signing else ""
    print(f"check-release-build: identity, versions,{signing} manifests verified "
          f"on {1 + len(artifact['extensions'])} bundles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
