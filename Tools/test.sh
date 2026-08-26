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
#
# "Whichever is newest" is the right default for a developer machine and the
# wrong contract for a lane that exists to test a *specific* runtime (#286).
# GLOW_EXPECTED_RUNTIME_MAJOR=18 restricts the selection to that iOS major and
# then *asserts* the chosen device matches — including a device pinned by
# GLOW_SIMULATOR_UDID — so the minimum-iOS lane fails loudly rather than
# falling forward to whatever newer runtime the machine happens to have.
# Unset, nothing changes. What ran is recorded either way: the runtime and
# device go to the console, into <run>/simulator.txt, and onto the end of the
# validator's summary.md.

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

# A caller that knows it is one of several concurrent runs pins its own phone
# with GLOW_SIMULATOR_UDID. Without it the selection below is deterministic, so
# every concurrent run picks the *same* device and they install competing
# bundles onto it — see #221 and the lock further down.
DEVICE_ID="${GLOW_SIMULATOR_UDID:-}"

[ -n "$DEVICE_ID" ] || DEVICE_ID=$(
  xcrun simctl list devices available --json |
    /usr/bin/python3 -c '
import json, os, re, sys

expected = os.environ.get("GLOW_EXPECTED_RUNTIME_MAJOR", "")
data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> (26, 5)
    version = tuple(int(part) for part in re.findall(r"\d+", runtime.split("iOS-")[-1]))
    # The minimum lane asks for one major and must not be answered with
    # another (#286); filtered here, and asserted again below for every path.
    if expected and version[:1] != (int(expected),):
        continue
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
  if [ -n "${GLOW_EXPECTED_RUNTIME_MAJOR:-}" ]; then
    echo "error: no available iPhone simulator on an iOS ${GLOW_EXPECTED_RUNTIME_MAJOR}.x runtime." >&2
    echo "The expectation is the point: this run must not fall forward to a newer" >&2
    echo "runtime (#286). Install the iOS ${GLOW_EXPECTED_RUNTIME_MAJOR} runtime and create an iPhone on it," >&2
    echo "or unset GLOW_EXPECTED_RUNTIME_MAJOR. Installed runtimes:" >&2
    xcrun simctl list runtimes | grep iOS >&2 || true
  else
    echo "error: no available iPhone simulator found. Install an iOS runtime in Xcode." >&2
  fi
  exit 1
fi

# What phone this actually is, wherever the udid came from — the selection
# above, a caller's GLOW_SIMULATOR_UDID, either way the evidence and the
# assertion read the same facts.
DEVICE_EVIDENCE=$(
  xcrun simctl list devices --json |
    GLOW_DEVICE_ID="$DEVICE_ID" /usr/bin/python3 -c '
import json, os, sys

target = os.environ["GLOW_DEVICE_ID"]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["udid"] == target:
            print(runtime + "|" + device["name"])
            raise SystemExit
'
)
RUNTIME_ID="${DEVICE_EVIDENCE%%|*}"
DEVICE_NAME="${DEVICE_EVIDENCE#*|}"
if [ -z "$RUNTIME_ID" ]; then
  echo "error: simulator $DEVICE_ID is not in simctl's device list." >&2
  exit 1
fi

if [ -n "${GLOW_EXPECTED_RUNTIME_MAJOR:-}" ]; then
  case "$RUNTIME_ID" in
    *".iOS-${GLOW_EXPECTED_RUNTIME_MAJOR}-"*) ;;
    *)
      echo "error: GLOW_EXPECTED_RUNTIME_MAJOR is ${GLOW_EXPECTED_RUNTIME_MAJOR}, but the chosen simulator is" >&2
      echo "  $DEVICE_NAME ($DEVICE_ID) on $RUNTIME_ID" >&2
      echo "A lane that silently runs on a newer runtime than it claims is the" >&2
      echo "failure #286 names. Fix the expectation or the device, not this check." >&2
      exit 1
      ;;
  esac
fi

# The run's own record of where it ran, kept beside the log so a crashed run
# still says which phone it died on.
{
  echo "device: $DEVICE_NAME ($DEVICE_ID)"
  echo "runtime: $RUNTIME_ID"
  echo "expected runtime major: ${GLOW_EXPECTED_RUNTIME_MAJOR:-unset (newest wins)}"
  xcodebuild -version | tr '\n' ' '
  echo
} > "$RUN/simulator.txt"

# Two runs on one device tear each other apart, and not in ways that read as a
# device conflict: the host dies during bootstrap, or a bundle reports fewer
# tests than its floor, or a failure names a file that is clean in this
# checkout. The third can just as easily produce a green run that is partly
# another checkout's. So a run holds the device for its duration and a second
# run waits rather than interleaving. See #221.
LOCK="${TMPDIR:-/tmp}/glow-simulator-$DEVICE_ID.lock"
exec 9>"$LOCK"
if ! /usr/bin/python3 -c 'import fcntl,sys; fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)' 2>/dev/null; then
  echo "==> Simulator $DEVICE_ID is busy with another run; waiting for it"
fi
/usr/bin/python3 -c 'import fcntl; fcntl.flock(9, fcntl.LOCK_EX)'

if [ "${GLOW_ERASE_SIMULATOR:-0}" = "1" ]; then
  echo "==> Erasing simulator $DEVICE_ID"
  xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl erase "$DEVICE_ID"
fi

# **There is no accessibility tree until accessibility is switched on** (#245).
#
# UIKit loads the accessibility bundles into an app only when the device says
# accessibility is enabled, and a simulator nobody has ever run VoiceOver or the
# Accessibility Inspector on does not say that. In a process without them
# nothing vends elements at all — measured on a device this script had just
# erased, every node in a hosted `WeeklyGridView` came back
# `isAccessibilityElement = false`, the navigation bar included, and the root
# reported an element count of zero.
#
# `EmptyStateAccessibilityTests` walks that tree, so it failed on every CI run —
# the lane erases its phone — and passed on the machine it was written on, which
# had accessibility left on from an earlier session. Empty, not wrong: an empty
# tree is what an absent runtime looks like, which is why it read as a layout
# problem.
#
# Here rather than in the test, because the preference is the device's and is
# read once, as the test host launches: by the time any test runs it is far too
# late to set it. `bootstatus -b` because a device that was just erased is shut
# down, and `simctl spawn` needs it up.
echo "==> Enabling accessibility on simulator $DEVICE_ID"
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null
xcrun simctl spawn "$DEVICE_ID" \
  defaults write com.apple.Accessibility AccessibilityEnabled -bool true
xcrun simctl spawn "$DEVICE_ID" \
  defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true

echo "==> Testing on $DEVICE_NAME ($RUNTIME_ID), simulator $DEVICE_ID"
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
  # `error:` on its own is not a signal either, for the same reason a bare
  # `failed` was not: CoreData logs `CoreData: error:` lines on runs that pass,
  # and the migration suite plants a malformed store on purpose, so a crashed
  # run once reported that noise under "Failing assertions". Compiler errors
  # carry a file and a position; those are the ones worth quoting. See #148.
  ASSERTIONS=$(grep -E "✘|\.swift:[0-9]+:[0-9]+: error:|Testing failed:" "$LOG" | head -40 || true)

  # A host that dies mid-run is its own outcome, and it names an innocent test.
  # Three separate investigations went looking for a bug in whichever test
  # happened to be running when the process was killed. See #175 and #179.
  CRASHED=$(grep -cE "Restarting after unexpected exit|crashed with signal|Test crashed" "$LOG" || true)

  if [ "$CRASHED" -gt 0 ]; then
    echo "FAILED because the test host died mid-run — this is probably not the"
    echo "fault of the test it names."
    echo
    grep -E "Restarting after unexpected exit|crashed with signal|Test crashed|Fatal error" "$LOG" \
      | head -6 | sed 's/^/  /'
    echo
    echo "  load average now: $(uptime | sed 's/.*load averages*: //')"
    echo
    # Intersected, not counted separately: `ps` names devices that are not
    # booted at all, so a bare count of each says "3 booted, 3 busy" while two
    # of them sit idle — the exact reading this line exists to prevent.
    BOOTED_IDS=$(xcrun simctl list devices booted -j 2>/dev/null |
      /usr/bin/python3 -c 'import json,sys
data=json.load(sys.stdin)["devices"]
print("\n".join(d["udid"] for v in data.values() for d in v if d.get("state")=="Booted"))' || true)
    BOOTED_N=$(printf "%s" "$BOOTED_IDS" | grep -c . || true)
    BUSY_N=$(ps -Ao args | grep -o "id=[0-9A-Fa-f-]\{36\}" | sed "s/^id=//" | sort -u |
      grep -Fxf <(printf "%s" "$BOOTED_IDS") 2>/dev/null | grep -c . || true)
    echo "  simulators booted: ${BOOTED_N:-?}, of them being tested on: ${BUSY_N:-?}"
    echo
    echo "Three causes, and the load average tells them apart badly. This machine"
    echo "has been seen killing the host above roughly 70 — but a second run on"
    echo "the same simulator does this too, at any load, and drives the load up"
    echo "while it does it (#221). The lock above should prevent that; if this"
    echo "line is printing anyway, check for another xcodebuild before reading"
    echo "anything into which test failed."
    echo
    echo "The third is idle simulators (#247). A booted runtime carries dozens of"
    echo "daemons whether or not anything runs on it, so devices left behind by"
    echo "runs that already finished can push the machine past the threshold on"
    echo "their own. If the two numbers above are far apart, that is this:"
    echo "  Tools/reap-simulators.sh --dry-run"
    if [ -n "$ASSERTIONS" ]; then
      echo
      echo "Assertions also present, which may or may not be related:"
      echo "$ASSERTIONS"
    fi
  elif [ -n "$ASSERTIONS" ]; then
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

# The evidence of where the run happened, on the same page as the verdict —
# CI publishes summary.md, and "passed" without "on what" is the gap #286 is
# about.
if [ -f "$RUN/summary.md" ]; then
  {
    echo
    echo "Ran on: $DEVICE_NAME — \`$RUNTIME_ID\`"
  } >> "$RUN/summary.md"
fi

if [ "$STATUS" -ne 0 ] || [ "$VALIDATION" -ne 0 ]; then
  echo
  echo "Evidence for this run is in $RUN"
  if grep -q "Render baseline" "$LOG" 2>/dev/null && grep -q "✘.*signature" "$LOG" 2>/dev/null; then
    # The baseline is per OS major where one is committed (#286): a run on a
    # runtime that has its own file must approve into that file, not into the
    # current runtime's.
    RUNTIME_MAJOR=$(printf '%s' "$RUNTIME_ID" | sed 's/.*iOS-\([0-9][0-9]*\)-.*/\1/')
    BASELINE="RenderTests/Baselines/render-signatures.json"
    if [ -f "RenderTests/Baselines/render-signatures-ios${RUNTIME_MAJOR}.json" ]; then
      BASELINE="RenderTests/Baselines/render-signatures-ios${RUNTIME_MAJOR}.json"
    fi
    echo
    echo "The render baseline moved. If the change was intended, approve it:"
    echo "  cp $RUN/attachments/named/render-signatures-actual*.json \\"
    echo "     $BASELINE"
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
