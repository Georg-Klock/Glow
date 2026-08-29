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

  local actual
  actual="$(ls "$run"/attachments/named/render-signatures-actual*.json 2>/dev/null | head -1)"
  if [ -z "$actual" ]; then
    echo "error: $run attached no render-signatures-actual.json, so this run" >&2
    echo "       measured nothing to approve. Nothing is approved." >&2
    exit 1
  fi

  if [ -f "$baseline" ] && cmp -s "$actual" "$baseline"; then
    UNCHANGED+=("$baseline")
    echo "    unchanged: $baseline"
    return
  fi

  if [ "$CHECK_ONLY" = "1" ]; then
    MOVED+=("$baseline")
    echo "    MOVED (not written, --check): $baseline"
  else
    cp "$actual" "$baseline"
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
