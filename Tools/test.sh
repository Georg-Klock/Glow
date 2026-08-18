#!/usr/bin/env bash
#
# The test command. Use this rather than a hand-typed xcodebuild, because it
# asserts a non-zero test count: a scheme that builds no test target otherwise
# exits 0 and looks exactly like a pass.
#
# Picks whichever iPhone simulator this machine actually has, so it works the
# same locally and on a CI runner with a different Xcode.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed. brew install xcodegen" >&2
  exit 1
fi

echo "==> Generating Glow.xcodeproj"
xcodegen generate --quiet

DEVICE_ID=$(
  xcrun simctl list devices available --json |
    /usr/bin/python3 -c '
import json, re, sys

data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> (26, 5)
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.split("iOS-")[-1]))
    for device in devices:
        name = device["name"]
        if not device.get("isAvailable") or "iPhone" not in name:
            continue
        # Prefer the newest runtime, then the highest model number, so a run
        # lands on a current phone rather than on whichever SE sorts last.
        model = [int(part) for part in re.findall(r"\d+", name)] or [0]
        candidates.append(((version, model, name), device["udid"]))

print(max(candidates)[1] if candidates else "")
'
)

if [ -z "$DEVICE_ID" ]; then
  echo "error: no available iPhone simulator found. Install an iOS runtime in Xcode." >&2
  exit 1
fi

echo "==> Testing on simulator $DEVICE_ID"
LOG=$(mktemp -t glow-tests)
trap 'rm -f "$LOG"' EXIT

set +e
xcodebuild test \
  -project Glow.xcodeproj \
  -scheme Glow \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  echo
  echo "FAILED. Failing assertions:"
  grep -E "✘|error:|failed" "$LOG" | head -40 || true
  exit "$STATUS"
fi

# Swift Testing reports "Test run with N tests passed". Anything that gets here
# with no tests has a broken scheme, not a green build.
COUNT=$(grep -oE "Test run with [0-9]+ test" "$LOG" | grep -oE "[0-9]+" | tail -1 || true)
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
  echo "error: the run reported no tests. The scheme is not running the test target." >&2
  exit 1
fi

echo
echo "L1 ${COUNT}/${COUNT}"
