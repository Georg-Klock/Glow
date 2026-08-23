#!/usr/bin/env bash
#
# Shut down booted simulators nothing is testing on.
#
# A booted runtime is not free: each one carries dozens of daemons whether or
# not anything runs on it. Ten booted devices with two in use measured 1,770
# CoreSimulator processes and a load average of 797 on this machine — past the
# threshold where the test host gets killed during bootstrap, which reads as a
# failing test rather than as a busy machine. See #247, and #221 for the
# failure signatures that load produces.
#
# Shuts down rather than deletes. A shutdown device costs nothing, and
# `xcodebuild -destination id=…` boots it again on demand, so the next run pays
# one boot instead of losing a suite.
#
# A device is spared when a live `xcodebuild` names its UDID. That is the whole
# safety rule: this never touches a device something is testing on.
#
# Usage:
#   Tools/reap-simulators.sh           shut down every idle booted device
#   Tools/reap-simulators.sh --dry-run say what it would do
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

BOOTED=$(xcrun simctl list devices booted -j |
  /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
for runtime, devices in data.items():
    for device in devices:
        if device.get("state") == "Booted":
            print(device["udid"], device["name"])
')

if [ -z "$BOOTED" ]; then
  echo "no booted simulators"
  exit 0
fi

# Every UDID a live xcodebuild is pointed at. `ps` rather than a lock file: a
# run killed by the load this script exists to prevent never releases a lock,
# and a stale lock would make the reaper spare a device forever.
BUSY=$(ps -Ao args | grep -o 'id=[0-9A-Fa-f-]\{36\}' | sed 's/^id=//' | sort -u || true)

TOTAL=0
IDLE=0
while read -r udid name; do
  [ -n "$udid" ] || continue
  TOTAL=$((TOTAL + 1))
  case "$BUSY" in
    *"$udid"*) echo "  keeping  $name — a test run is on it"; continue ;;
  esac
  IDLE=$((IDLE + 1))
  if [ "$DRY" = "1" ]; then
    echo "  would shut down  $name ($udid)"
  else
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 && echo "  shut down  $name ($udid)"
  fi
done <<EOF
$BOOTED
EOF

echo "$TOTAL booted, $IDLE idle"
