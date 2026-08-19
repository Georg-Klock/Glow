#!/bin/bash
#
# Prints the widget's trace off a tethered iPhone.
#
#     Tools/pull-widget-log.sh [device-identifier]
#
# A widget extension is invisible from the outside: its own process, under a
# second of animation, nothing to pause. On a Mac whose `log stream` still takes
# `--device-name` you can watch it live —
#
#     log stream --device-name "<phone>" --predicate 'subsystem == "com.georgklock.glow"'
#
# — but newer ones dropped that flag. The app also writes each line into the App
# Group's defaults, and that plist is the one thing `devicectl` fetches reliably
# from a group container (see WidgetTrace for what else was tried). This reads it.
#
# The phone must be unlocked. A locked iPhone reports as "unavailable", which
# reads identically to "not plugged in".
set -euo pipefail

GROUP="group.com.georgklock.glow"
KEY="widgetTrace"

device="${1:-}"
if [ -z "$device" ]; then
  device=$(xcrun devicectl list devices 2>/dev/null \
    | awk '$0 ~ /connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }')
fi

if [ -z "$device" ]; then
  echo "pull-widget-log: no connected device." >&2
  echo "  Plug the phone in and unlock it, then: xcrun devicectl list devices" >&2
  exit 1
fi

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

xcrun devicectl device copy from \
  --device "$device" \
  --domain-type appGroupDataContainer \
  --domain-identifier "$GROUP" \
  --source "Library/Preferences/$GROUP.plist" \
  --destination "$out/group.plist" \
  --quiet >/dev/null 2>&1 || {
    echo "pull-widget-log: could not read the App Group container." >&2
    echo "  Check the entitlement with Tools/check-app-group.sh." >&2
    exit 1
  }

lines=$(plutil -extract "$KEY" raw -o - "$out/group.plist" 2>/dev/null || true)
if [ -z "$lines" ]; then
  echo "pull-widget-log: no trace yet." >&2
  echo "  A line appears once the widget builds a timeline or a slot is tapped." >&2
  echo "  Defaults are flushed lazily, so give it a few seconds." >&2
  exit 1
fi

plutil -extract "$KEY" json -o - "$out/group.plist" \
  | python3 -c 'import json,sys; [print(l) for l in json.load(sys.stdin)]'
