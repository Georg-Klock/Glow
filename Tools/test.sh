#!/usr/bin/env bash
#
# The test command. Use this rather than a hand-typed xcodebuild.
#
# It runs the suite once into a result bundle nobody else can overwrite, keeps
# the bundle and everything the run attached, and then asks
# Tools/validate-test-result.py whether the run was really a pass —
# because `xcodebuild` exiting 0 only says that what ran did not fail. A lost
# test bundle, a suite that shrank by three hundred tests, a skipped test and a
# compiler warning all exit 0. See #138.
#
# What this leaves behind, under Artifacts/<run>/ (gitignored):
#
#   xcodebuild.log     the whole run, exactly as it was printed
#   Glow.xcresult      the result bundle, for Xcode or xcresulttool
#   attachments/       what the tests attached, incl. the render baseline
#   validation.json    the structured verdict
#   summary.md         the same verdict as markdown, for CI's run summary
#
# The directory is unique per run — a CI run id and attempt where there is one,
# a timestamp and the shell's pid otherwise — so two runs cannot read each
# other's evidence and a failed run's bundle is still there afterwards.
#
# Picks whichever iPhone simulator this machine actually has, so it works the
# same locally and on a CI runner with a different Xcode. Set
# GLOW_ERASE_SIMULATOR=1 to erase that simulator first: #168 was a value left
# in a simulator's App Group defaults by a dying test, and while the private
# per-process suite now stops a test writing there at all, a CI lane that
# reuses a runner image should still start from nothing.

set -euo pipefail

cd "$(dirname "$0")/.."

RUN_ID="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-$(date +%Y%m%d-%H%M%S)}-$$"
RUN="Artifacts/${RUN_ID}"
mkdir -p "$RUN"
# A convenience for the next local run, and skipped on CI: upload-artifact
# follows symlinks, so `latest` would put the whole run in the bundle twice.
if [ -z "${GITHUB_ACTIONS:-}" ]; then
  ln -sfn "$RUN_ID" Artifacts/latest
fi
LOG="$RUN/xcodebuild.log"
RESULT="$RUN/Glow.xcresult"

echo "==> Generating Glow.xcodeproj"
Tools/generate.sh

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

if [ "${GLOW_ERASE_SIMULATOR:-0}" = "1" ]; then
  echo "==> Erasing simulator $DEVICE_ID"
  xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl erase "$DEVICE_ID"
fi

echo "==> Testing on simulator $DEVICE_ID"
echo "==> Evidence: $RUN"

set +e
xcodebuild test \
  -project Glow.xcodeproj \
  -scheme Glow \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO \
  | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

# Everything below runs whatever xcodebuild decided. A failing run is the run
# whose evidence is worth the most, and the validator has things to say about
# runs that "passed".

if [ -d "$RESULT" ]; then
  mkdir -p "$RUN/attachments"
  xcrun xcresulttool export attachments \
    --path "$RESULT" --output-path "$RUN/attachments" >/dev/null 2>&1 || true
  # The export names files by uuid and records the readable name in the
  # manifest. Copy them out under the readable name too, so the artifact is
  # browsable without reading JSON first.
  /usr/bin/python3 - "$RUN/attachments" <<'PY' || true
import json, pathlib, shutil, sys

root = pathlib.Path(sys.argv[1])
manifest = root / "manifest.json"
if manifest.exists():
    named = root / "named"
    named.mkdir(exist_ok=True)
    for test in json.loads(manifest.read_text()):
        for attachment in test.get("attachments", []):
            source = root / attachment["exportedFileName"]
            if source.exists():
                shutil.copyfile(source, named / attachment["suggestedHumanReadableName"])
PY
fi

# How many tests reported, whatever the exit code. A run that never reached the
# tests and a run whose tests failed are different problems, and until #148 they
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
    # The mirror image of the validator's bundle floors, and the same argument:
    # a run that never got to the tests must not look like a test failure.
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
fi

echo
echo "==> Validating the result bundle"
set +e
/usr/bin/python3 Tools/validate-test-result.py \
  --xcresult "$RESULT" \
  --attachments "$RUN/attachments" \
  --json-output "$RUN/validation.json" \
  --summary-output "$RUN/summary.md"
VALIDATION=$?
set -e

if [ "$STATUS" -ne 0 ] || [ "$VALIDATION" -ne 0 ]; then
  echo
  echo "Evidence for this run is in $RUN"
  if grep -q "Render baseline" "$LOG" 2>/dev/null && grep -q "✘.*signature" "$LOG" 2>/dev/null; then
    echo
    echo "The render baseline moved. If the change was intended, approve it:"
    echo "  cp $RUN/attachments/named/render-signatures-actual*.json \\"
    echo "     RenderTests/Baselines/render-signatures.json"
    echo "and say in the pull request what moved and why."
  fi
  # Written as an if rather than as `[ … ] && exit`, which under `set -e`
  # exits with the status of the *test* when the test is false.
  if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
  fi
  exit "$VALIDATION"
fi

COUNT=$(/usr/bin/python3 -c "
import json, sys
print(json.load(open('$RUN/validation.json'))['total'])
")

echo
echo "L1 ${COUNT}/${COUNT}"
