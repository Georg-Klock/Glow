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
"""

import json
import plistlib
import subprocess
import sys
from pathlib import Path

PROJECT = Path("Glow.xcodeproj/project.pbxproj")

APP_GROUP = "group.com.georgklock.glow"
CAPABILITY = "com.apple.ApplicationGroups.iOS"

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


def check_extension_only(settings: dict[str, dict], name: str) -> None:
    for config, values in sorted(settings.items()):
        value = values.get("APPLICATION_EXTENSION_API_ONLY")
        if str(value).upper() != "YES":
            fail(
                f"{name} ({config}): APPLICATION_EXTENSION_API_ONLY is {value!r}, not YES. "
                "The extension compiles the app's source folders; without this the "
                "compiler cannot reject app-only API."
            )


def main() -> int:
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
    print(f"check-project: App Groups, entitlements and extension-only API verified on {checked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
