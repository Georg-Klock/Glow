#!/usr/bin/env bash
#
# Approve the render baselines — both of them, from one command.
#
# A visual change moves two committed files: RenderTests/Baselines/
# render-signatures.json, measured on whatever runtime is newest here, and
# render-signatures-ios<major>.json, measured on the runtime the minimum-iOS
# lane pins (#286). They are two measurements of the same change, so approving
# one and forgetting the other is not the smaller half of the job — it leaves a
# committed baseline that disagrees with the app on a runtime this project
# ships to. Since 2026-08-29 the lane that notices runs after the merge rather
# than in front of it, which makes the forgetting cheaper to do and slower to
# find. See docs/decisions.md, "Pull-request latency".")
#
# So: render on both, approve both, and refuse to approve either when the run
# failed for any reason beyond the signatures moving. Copying an "actual" out
# of a run whose build was broken is how a real failure becomes a committed
# baseline that every later run then agrees with.
#
# The full suite runs on each lane rather than the render tests alone. That is
# the point, not an oversight: "nothing else failed" is the precondition for
# approving anything, and a subset run cannot establish it.
#
#   Tools/approve-baseline.sh            render both, write what moved
#   Tools/approve-baseline.sh --check    render both, write nothing, exit 1
#                                        if either baseline is out of date
#
# "Out of date" is `Tools/compare-signatures.py`'s answer, not `cmp`'s. Every
# number in a signature is compared exactly except the tone counts, where a
# single pixel of the iOS 18.5 renderer's own noise moves the count by one in
# either direction — measured, over 60 renders on two devices, against 48
# bit-identical ones on iOS 26.5. No cell mean and no ground share moved in any
# of them. A difference that small is reported and not written: whichever of
# the two values were committed, half the later runs on that lane would render
# the other. See #431 and the tool's own header.
#
# GLOW_MIN_IOS_MAJOR overrides the minimum major (default 18); it has to match
# the major the CI lane pins, or this approves a file that lane never reads.

set -euo pipefail

cd "$(dirname "$0")/.."

MIN_MAJOR="${GLOW_MIN_IOS_MAJOR:-18}"

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
  shift
fi
if [ "$#" -gt 0 ]; then
  echo "usage: Tools/approve-baseline.sh [--check]" >&2
  exit 2
fi

MOVED=()
UNCHANGED=()

# One lane: run the suite, refuse on anything that is not the baseline moving,
# then compare and copy. $1 is what to call it, $2 the file it approves into,
# and the rest is environment for Tools/test.sh.
approve_lane() {
  local label="$1" baseline="$2"
  shift 2

  echo
  echo "==> $label"

  # test.sh exits non-zero when the baseline moved, which is the ordinary case
  # here rather than an error. What the run was is decided below, from the
  # validator's own verdict, not from this status.
  set +e
  env ${@+"$@"} Tools/test.sh
  set -e

  local run
  run="$(readlink Artifacts/latest 2>/dev/null || true)"
  if [ -z "$run" ] || [ ! -d "Artifacts/$run" ]; then
    echo "error: that run left no Artifacts/latest to read. Nothing is approved." >&2
    exit 1
  fi
  run="Artifacts/$run"

  if [ ! -f "$run/validation.json" ]; then
    echo "error: $run has no validation.json — the run did not reach the validator," >&2
    echo "       so there is no verdict to approve against. Nothing is approved." >&2
    exit 1
  fi

  # The gate on approving at all. A signature that moved is the thing this
  # script exists to accept; a compile error, a lost bundle, a failure anywhere
  # outside GlowRenderTests is not, and must not be laundered into a baseline.
  if ! /usr/bin/python3 - "$run/validation.json" <<'PY'
import json, sys

verdict = json.load(open(sys.argv[1]))
unrelated = [
    failure for failure in verdict["failures"]
    if not failure.startswith("GlowRenderTests: ")
    and not failure.startswith("the run reports ")
]
if unrelated:
    print("       this run failed for reasons a baseline cannot explain:")
    for failure in unrelated:
        print(f"         - {failure.splitlines()[0]}")
    raise SystemExit(1)
PY
  then
    echo "error: refusing to approve $baseline." >&2
    echo "       Fix those first; a baseline approved over them agrees with the bug." >&2
    exit 1
  fi

  # Whether the gate itself went red on this lane, read here and kept apart
  # from the reading of the file below, so that it can outrank it.
  local RENDER_GATE
  RENDER_GATE="$(/usr/bin/python3 - "$run/validation.json" <<'GATE'
import json, sys

verdict = json.load(open(sys.argv[1]))
red = any(failure.startswith("GlowRenderTests: ") for failure in verdict["failures"])
print("red" if red else "green")
GATE
)"

  local actual
  actual="$(ls "$run"/attachments/named/render-signatures-actual*.json 2>/dev/null | head -1)"
  if [ -z "$actual" ]; then
    echo "error: $run attached no render-signatures-actual.json, so this run" >&2
    echo "       measured nothing to approve. Nothing is approved." >&2
    exit 1
  fi

  # Was `cmp`, and on the current runtime `cmp` was right — 48 renders across
  # eight processes on iOS 26.5 are bit-identical. On iOS 18.5 they are not:
  # 60 renders across ten processes on two devices differ by up to 601 pixels,
  # all of it single-level noise, most of it in the material the surface is
  # drawn on, and the one statistic a single pixel can move is the tone census.
  # So the comparison is exact everywhere that was measured exact, and allows
  # the measured noise and no more in the one place it was not. The reasoning,
  # the numbers and what it stops catching are all in the tool. See #431.
  local report verdict reasons
  local settled="$actual.settled"
  if ! report="$(/usr/bin/python3 Tools/compare-signatures.py \
                   --actual "$actual" --committed "$baseline" \
                   --emit "$settled")"; then
    echo "error: could not compare $baseline against this run's render." >&2
    exit 1
  fi
  verdict="$(printf '%s\n' "$report" | head -1)"
  reasons="$(printf '%s\n' "$report" | tail -n +2)"

  # A red gate outranks the comparison. `framesMatchBaseline` failing means the
  # picture moved by more than the gate allows, and no reading of the file is
  # allowed to talk that away.
  if [ "$RENDER_GATE" = "red" ]; then
    verdict="moved"
  fi

  case "$verdict" in
    same)
      UNCHANGED+=("$baseline")
      echo "    unchanged: $baseline"
      return
      ;;
    noise)
      # Deliberately not written, in either mode. Whichever of the two values
      # is committed, about half the runs on that lane render the other one, so
      # writing here commits a coin flip and moves the disagreement rather than
      # settling it. That is the specific mistake #431 was filed to prevent.
      UNCHANGED+=("$baseline")
      echo "    unchanged: $baseline"
      echo "        inside the renderer's measured noise, so nothing is written:"
      printf '%s\n' "$reasons" | sed 's/^/          /'
      return
      ;;
  esac

  if [ -n "$reasons" ]; then
    printf '%s\n' "$reasons" | sed 's/^/        /'
  fi

  if [ "$CHECK_ONLY" = "1" ]; then
    MOVED+=("$baseline")
    echo "    MOVED (not written, --check): $baseline"
  else
    # Not `cp "$actual"`. A file that moved is written whole, and that used to
    # carry every noisy cell's value from whichever run happened to approve it,
    # so the committed number never settled and each diff carried a line of
    # noise to recognise and dismiss (#443). The settled file is this run
    # everywhere except the cells the comparison just classified as the
    # renderer's own, which keep what is already committed.
    cp "$settled" "$baseline"
    MOVED+=("$baseline")
    echo "    approved: $baseline"
  fi
}

approve_lane "Current runtime (newest installed)" \
  "RenderTests/Baselines/render-signatures.json"

approve_lane "Minimum iOS (major $MIN_MAJOR)" \
  "RenderTests/Baselines/render-signatures-ios${MIN_MAJOR}.json" \
  "GLOW_EXPECTED_RUNTIME_MAJOR=$MIN_MAJOR"

echo
echo "==> Baselines"
for file in ${UNCHANGED[@]+"${UNCHANGED[@]}"}; do echo "    unchanged  $file"; done
for file in ${MOVED[@]+"${MOVED[@]}"}; do echo "    moved      $file"; done

if [ "${#MOVED[@]}" -eq 0 ]; then
  echo
  echo "Both baselines already describe this tree."
  exit 0
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo
  echo "Out of date. Run Tools/approve-baseline.sh to write them."
  exit 1
fi

echo
echo "Approved. Commit both files together, and say in the pull request what"
echo "moved and why — an approved baseline is a decision, not a formality."
