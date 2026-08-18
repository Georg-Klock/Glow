#!/usr/bin/env bash
#
# Generates Glow.xcodeproj. Use this rather than calling xcodegen directly.
#
# xcodegen writes a target's `attributes` as a Swift-style string when the
# value is a nested dictionary, so
#
#     SystemCapabilities = "[\"com.apple.ApplicationGroups.iOS\": [\"enabled\": 1]]";
#
# lands in the project where Xcode expects a real dictionary, and Xcode ignores
# it. That matters: SystemCapabilities is how a project tells automatic signing
# which capabilities the App ID needs. Without it, the App Groups entitlement is
# compiled in and then silently stripped by codesign, because the profile it
# picked never granted the group.
#
# So: generate, then rewrite that one value into the form Xcode reads.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed. brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --quiet

/usr/bin/python3 - <<'PY'
import pathlib
import sys

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
elif "SystemCapabilities" not in text:
    # Not fatal, but worth saying out loud: it means the App Groups capability
    # is no longer declared and the widget will quietly stop seeing the store.
    print("generate: warning, no SystemCapabilities in the project", file=sys.stderr)
PY

echo "generate: wrote Glow.xcodeproj"
