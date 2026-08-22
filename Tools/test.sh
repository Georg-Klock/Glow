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

echo "==> Generating Glow.xcodeproj"
"$(dirname "$0")/generate.sh"

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

# How many tests reported, whatever the exit code. A run that never reached the
# tests and a run whose tests failed are different problems, and until now they
# printed the same thing.
REPORTED=$(grep -cE "^.?.?.?Test run with [0-9]+ test" "$LOG" || true)

if [ "$STATUS" -ne 0 ]; then
  echo
  # `✘` and `error:` are the real signals. A bare `failed` is not: the
  # simulator logs `IOSurfaceClientSetSurfaceNotify failed` on runs that pass,
  # and matching it meant a launch failure was reported as one failing
  # assertion — a graphics warning — with the actual cause discarded. See #148.
  ASSERTIONS=$(grep -E "✘|error:|Testing failed:" "$LOG" | head -40 || true)

  if [ -n "$ASSERTIONS" ]; then
    echo "FAILED. Failing assertions:"
    echo "$ASSERTIONS"
  elif [ "$REPORTED" -eq 0 ]; then
    # The mirror image of the no-tests check below, and the same argument: a
    # run that never got to the tests must not look like a test failure.
    echo "FAILED before any test reported — this is not an assertion failure."
    echo "xcodebuild exited $STATUS with no test run. Its last 30 lines:"
    echo
    tail -30 "$LOG" | sed 's/^/  /'
  else
    echo "FAILED after the tests reported, with no assertion in the log."
    echo "Something after the run failed — the last 30 lines:"
    echo
    tail -30 "$LOG" | sed 's/^/  /'
  fi
  exit "$STATUS"
fi

# Swift Testing reports "Test run with N tests passed" once per test target.
# Sum them — taking the last line silently shrank the count to whichever
# target happened to finish last once the scheme grew a second one.
COUNT=$(grep -oE "Test run with [0-9]+ test" "$LOG" | grep -oE "[0-9]+" | paste -sd+ - | bc || true)
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
  echo "error: the run reported no tests. The scheme is not running the test target." >&2
  exit 1
fi

echo
echo "L1 ${COUNT}/${COUNT}"
