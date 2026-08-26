#!/usr/bin/env python3
"""Asserts the facts about Glow.xcodeproj that nothing else notices are missing.

Run by Tools/generate.sh after every generation, and separately runnable in CI.
Exits non-zero, loudly, on any failure.

Everything checked here has the same shape: a value the build needs, which is
silently dropped rather than diagnosed when it is absent.

  * SystemCapabilities tells automatic signing that the App ID needs App
    Groups. xcodegen writes it as a Swift-style *string*, which Xcode ignores;
    generate.sh rewrites it. Reading the project back as a property list is the
    only way to know the rewrite produced a dictionary, because a string and a
    dictionary look identical to a textual search for the key.

  * CODE_SIGN_ENTITLEMENTS, and the group inside the file it names. xcodegen
    generates the entitlements file, so a `path` with no `properties` overwrites
    it with an empty dict — which signs cleanly and leaves the widget unable to
    see the store.

  * APPLICATION_EXTENSION_API_ONLY on the extension. The widget compiles four
    of the app's source folders; without it the compiler has no opinion about
    app-only API arriving in the extension.

The previous check was textual and failed open: it repaired what it recognised
and said nothing when it recognised nothing. A generator whose output format
moves is exactly the case where recognising nothing is the likely outcome.

And one thing checked here is the opposite shape: a value the build does *not*
need, whose arrival would be silent too. Glow's promise is that habit data
never leaves the device except through an explicit share, and the road
SwiftData's `.automatic` CloudKit default would take runs through an iCloud
entitlement. So the entitlements are held to an allowlist — the App Group and
nothing else — and the six iCloud/ubiquity keys are rejected by name, so that
enabling sync is a reviewed change to this file rather than a capability
checkbox nobody diffs. `--self-test` proves each rejection fires. See #281.
"""

import argparse
import json
import plistlib
import subprocess
import sys
from pathlib import Path

PROJECT = Path("Glow.xcodeproj/project.pbxproj")

APP_GROUP = "group.com.georgklock.glow"
CAPABILITY = "com.apple.ApplicationGroups.iOS"

# The local-only denylist (#281): every route by which managed CloudKit or
# ubiquity storage reaches a build has one of these keys in front of it.
FORBIDDEN_ENTITLEMENTS = (
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.icloud-container-development-container-identifiers",
    "com.apple.developer.icloud-container-environment",
    "com.apple.developer.icloud-services",
    "com.apple.developer.ubiquity-container-identifiers",
    "com.apple.developer.ubiquity-kvstore-identifier",
)

# What a Glow target may ask to be entitled to. Widening this list is the
# reviewable event.
ALLOWED_ENTITLEMENT_KEYS = {"com.apple.security.application-groups"}

# Capabilities the generated project may declare per target. The iCloud
# capability arriving here is the same decision as an entitlement arriving.
ALLOWED_CAPABILITIES = {CAPABILITY}

# Targets that must carry the App Groups capability and the entitlement.
GROUPED_TARGETS = ("Glow", "GlowWidget")

# Targets that must be built with extension-only API enforcement.
EXTENSION_TARGETS = ("GlowWidget",)

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def load() -> dict:
    if not PROJECT.exists():
        print(f"error: {PROJECT} does not exist. Run Tools/generate.sh.", file=sys.stderr)
        sys.exit(1)
    # The pbxproj is an OpenStep property list; plutil reads it, and reading it
    # the way Xcode does is the whole point of this file.
    raw = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(PROJECT)],
        capture_output=True,
        check=False,
    )
    if raw.returncode != 0:
        print("error: the generated project is not a readable property list:", file=sys.stderr)
        print(raw.stderr.decode(errors="replace"), file=sys.stderr)
        sys.exit(1)
    return json.loads(raw.stdout)


def check_capability(objects: dict, target_attributes: dict, target_id: str, name: str) -> None:
    attributes = target_attributes.get(target_id)
    if not isinstance(attributes, dict):
        fail(f'{name}: no TargetAttributes entry, so no "{CAPABILITY}" capability.')
        return

    capabilities = attributes.get("SystemCapabilities")
    if capabilities is None:
        fail(f"{name}: SystemCapabilities is absent. App Groups will be stripped at signing.")
        return
    if not isinstance(capabilities, dict):
        # This is the mangled form: a Swift dictionary description in a string.
        fail(
            f"{name}: SystemCapabilities is a {type(capabilities).__name__}, not a dictionary. "
            "Xcode ignores it, and the generator's output format has moved — "
            "the repair in Tools/generate.sh no longer matches."
        )
        return

    entry = capabilities.get(CAPABILITY)
    if not isinstance(entry, dict):
        fail(f'{name}: SystemCapabilities has no "{CAPABILITY}" dictionary.')
        return
    # plutil renders pbxproj numbers as strings; both spellings mean enabled.
    if str(entry.get("enabled")) != "1":
        fail(f'{name}: "{CAPABILITY}" is present but not enabled ({entry.get("enabled")!r}).')

    for message in capability_policy_failures(capabilities, name):
        fail(message)


def capability_policy_failures(capabilities: dict, name: str) -> list[str]:
    """Capabilities outside the allowlist, as messages. Pure, for the self-test."""
    out = []
    for key, entry in sorted(capabilities.items()):
        if key in ALLOWED_CAPABILITIES:
            continue
        enabled = isinstance(entry, dict) and str(entry.get("enabled")) == "1"
        state = "enabled" if enabled else f"present ({entry!r})"
        out.append(
            f'{name}: SystemCapabilities declares "{key}", {state}. Glow is '
            "local-only (#281); a new capability is a product decision, and it "
            "starts by widening the allowlist in Tools/check-project.py."
        )
    return out


def entitlement_policy_failures(entitlements: dict, label: str) -> list[str]:
    """Entitlement keys Glow must not request, as messages. Pure, for the self-test."""
    out = []
    for key in sorted(entitlements):
        if key in FORBIDDEN_ENTITLEMENTS:
            out.append(
                f"{label}: entitlement {key} is on the iCloud/ubiquity denylist. "
                "It is the road SwiftData's `.automatic` CloudKit default needs, "
                "and Glow's local-only promise (#281) closes it here, where a "
                "capability change becomes a reviewable diff."
            )
        elif key not in ALLOWED_ENTITLEMENT_KEYS:
            out.append(
                f"{label}: entitlement {key} is outside the reviewed allowlist "
                f"({sorted(ALLOWED_ENTITLEMENT_KEYS)}). If it is deliberate, widen "
                "the allowlist in Tools/check-project.py in the same change."
            )
    return out


def build_settings(objects: dict, target: dict) -> dict[str, dict]:
    """Every configuration name -> build settings, for one target."""
    list_id = target.get("buildConfigurationList")
    config_list = objects.get(list_id, {})
    out = {}
    for config_id in config_list.get("buildConfigurations", []):
        config = objects.get(config_id, {})
        out[config.get("name", config_id)] = config.get("buildSettings", {})
    return out


def check_entitlements(settings: dict[str, dict], name: str) -> None:
    for config, values in sorted(settings.items()):
        path = values.get("CODE_SIGN_ENTITLEMENTS")
        if not path:
            fail(f"{name} ({config}): no CODE_SIGN_ENTITLEMENTS.")
            continue
        file = Path(path)
        if not file.exists():
            fail(f"{name} ({config}): CODE_SIGN_ENTITLEMENTS points at {path}, which does not exist.")
            continue
        try:
            entitlements = plistlib.loads(file.read_bytes())
        except Exception as error:  # noqa: BLE001 — the message is the product
            fail(f"{name} ({config}): {path} is not a readable plist ({error}).")
            continue
        groups = entitlements.get("com.apple.security.application-groups")
        if not groups:
            fail(
                f"{name} ({config}): {path} declares no application groups. "
                "An empty entitlements file signs cleanly and requests nothing."
            )
        elif APP_GROUP not in groups:
            fail(f"{name} ({config}): {path} does not contain {APP_GROUP} (has {groups}).")

        for message in entitlement_policy_failures(entitlements, f"{name} ({config})"):
            fail(message)


def check_extension_only(settings: dict[str, dict], name: str) -> None:
    for config, values in sorted(settings.items()):
        value = values.get("APPLICATION_EXTENSION_API_ONLY")
        if str(value).upper() != "YES":
            fail(
                f"{name} ({config}): APPLICATION_EXTENSION_API_ONLY is {value!r}, not YES. "
                "The extension compiles the app's source folders; without this the "
                "compiler cannot reject app-only API."
            )


def self_test() -> int:
    """Fixtures, each proving a policy rejection fires. See #138 for the shape.

    The App Groups checks are exercised daily by every real generation; the
    denylist is the part whose whole job is a build that does not exist yet,
    so a fixture per forbidden key is the only way to watch it fail.
    """
    scenarios: list[tuple[str, dict, str | None]] = [
        ("the App Group alone passes",
         {"com.apple.security.application-groups": [APP_GROUP]}, None),
    ]
    for key in FORBIDDEN_ENTITLEMENTS:
        scenarios.append((
            f"{key.rsplit('.', 1)[-1]} is rejected",
            {"com.apple.security.application-groups": [APP_GROUP], key: ["x"]},
            "iCloud/ubiquity denylist",
        ))
    scenarios.append((
        "an entitlement outside the allowlist is rejected",
        {"com.apple.security.application-groups": [APP_GROUP],
         "aps-environment": "production"},
        "outside the reviewed allowlist",
    ))

    bad = 0
    for name, entitlements, expected in scenarios:
        messages = entitlement_policy_failures(entitlements, "fixture")
        ok = (not messages) if expected is None \
            else any(expected in message for message in messages)
        detail = "" if ok else f" — got {messages}"
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{detail}")
        bad += 0 if ok else 1

    capability_scenarios: list[tuple[str, dict, str | None]] = [
        ("the App Groups capability alone passes",
         {CAPABILITY: {"enabled": "1"}}, None),
        ("the iCloud capability is rejected",
         {CAPABILITY: {"enabled": "1"}, "com.apple.iCloud": {"enabled": "1"}},
         "local-only"),
        ("an unknown capability is rejected even disabled",
         {CAPABILITY: {"enabled": "1"}, "com.apple.Push": {"enabled": "0"}},
         "local-only"),
    ]
    for name, capabilities, expected in capability_scenarios:
        messages = capability_policy_failures(capabilities, "fixture")
        ok = (not messages) if expected is None \
            else any(expected in message for message in messages)
        detail = "" if ok else f" — got {messages}"
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{detail}")
        bad += 0 if ok else 1

    total = len(scenarios) + len(capability_scenarios)
    print(f"check-project self-test: {total - bad}/{total} scenarios")
    return 1 if bad else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    if parser.parse_args().self_test:
        return self_test()

    data = load()
    objects = data["objects"]

    projects = [o for o in objects.values() if o.get("isa") == "PBXProject"]
    if len(projects) != 1:
        print(f"error: expected one PBXProject, found {len(projects)}.", file=sys.stderr)
        return 1
    target_attributes = projects[0].get("attributes", {}).get("TargetAttributes", {})

    targets = {
        object_id: o
        for object_id, o in objects.items()
        if o.get("isa") == "PBXNativeTarget"
    }
    by_name = {o.get("name"): (object_id, o) for object_id, o in targets.items()}

    for name in GROUPED_TARGETS:
        if name not in by_name:
            fail(f"{name}: no such target in the generated project.")
            continue
        target_id, target = by_name[name]
        check_capability(objects, target_attributes, target_id, name)
        check_entitlements(build_settings(objects, target), name)

    for name in EXTENSION_TARGETS:
        if name not in by_name:
            fail(f"{name}: no such target in the generated project.")
            continue
        _, target = by_name[name]
        check_extension_only(build_settings(objects, target), name)

    if failures:
        print("error: the generated project is not the project this repo needs.", file=sys.stderr)
        for message in failures:
            print(f"  - {message}", file=sys.stderr)
        return 1

    checked = ", ".join(sorted(set(GROUPED_TARGETS + EXTENSION_TARGETS)))
    print(f"check-project: App Groups, entitlements (within the local-only allowlist) "
          f"and extension-only API verified on {checked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
