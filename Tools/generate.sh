#!/usr/bin/env bash
#
# Generates Glow.xcodeproj. This is the only supported way to do it.
#
# Three things happen here, and the third is the one that makes the first two
# trustworthy.
#
# 1. The generator is pinned. Tools/xcodegen.pin names a version and the digest
#    of its release archive; Tools/install-xcodegen.sh resolves it into a
#    gitignored cache. The generated project is a function of project.yml *and*
#    of the generator, so leaving the generator floating leaves the project
#    floating.
#
# 2. One value is repaired. xcodegen writes a target's `attributes` as a
#    Swift-style string when the value is a nested dictionary, so
#
#        SystemCapabilities = "[\"com.apple.ApplicationGroups.iOS\": [\"enabled\": 1]]";
#
#    lands where Xcode expects a real dictionary, and Xcode ignores it.
#    SystemCapabilities is how a project tells signing which capabilities the
#    App ID needs; without it the App Groups entitlement is compiled in and then
#    silently stripped by codesign, because the profile it picked never granted
#    the group.
#
# 3. The result is validated as a property list, not as text. The repair above
#    is a string substitution: it fixes what it recognises and is silent when it
#    recognises nothing, which is precisely what a changed output format looks
#    like. Tools/check-project.py reads the project back the way Xcode does and
#    fails if the capability, the entitlement or the extension-only setting is
#    not really there.

set -euo pipefail

cd "$(dirname "$0")/.."

source Tools/xcodegen.pin

# Deliberately not "use whatever xcodegen is on PATH if it reports the pinned
# version". A binary with the right name and the right --version string is the
# one thing a pin is for; only the digest-checked copy is used, whatever else
# is installed. It costs one 4MB download per version, once.
if ! XCODEGEN=$(Tools/install-xcodegen.sh); then
  echo "error: could not resolve XcodeGen ${XCODEGEN_VERSION}." >&2
  echo "It is pinned in Tools/xcodegen.pin and downloaded on first use;" >&2
  echo "this needs network access once." >&2
  exit 1
fi

"$XCODEGEN" generate --quiet

/usr/bin/python3 - <<'PY'
import pathlib

project = pathlib.Path("Glow.xcodeproj/project.pbxproj")
text = project.read_text()

mangled = 'SystemCapabilities = "[\\"com.apple.ApplicationGroups.iOS\\": [\\"enabled\\": 1]]";'
correct = (
    "SystemCapabilities = {\n"
    '\t\t\t\t\t\t\t"com.apple.ApplicationGroups.iOS" = {\n'
    "\t\t\t\t\t\t\t\tenabled = 1;\n"
    "\t\t\t\t\t\t\t};\n"
    "\t\t\t\t\t\t};"
)

count = text.count(mangled)
if count:
    project.write_text(text.replace(mangled, correct))
    print(f"generate: fixed SystemCapabilities on {count} target(s)")
PY

# Fails the generation rather than warning about it. A project missing any of
# this builds, installs, and is wrong on the phone.
/usr/bin/python3 Tools/check-project.py

echo "generate: wrote Glow.xcodeproj with XcodeGen ${XCODEGEN_VERSION}"
