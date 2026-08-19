#!/usr/bin/env bash
#
# Reports whether the App Group is actually provisioned.
#
#     Tools/check-app-group.sh
#
# Exists because every failure mode here is silent. The entitlements file is in
# the repo, CODE_SIGN_ENTITLEMENTS is set, SystemCapabilities is in the project,
# the build succeeds, and codesign strips the entitlement anyway because the
# profile it picked never granted the group. Nothing warns you; the only symptom
# is a widget that shows no habits.

set -uo pipefail

cd "$(dirname "$0")/.."

GROUP="group.com.georgklock.glow"
BUNDLE="com.georgklock.glow"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
STATUS=0

echo "== Provisioning profiles granting $GROUP =="
FOUND=0
shopt -s nullglob
for f in "$PROFILES"/*.mobileprovision; do
  PLIST=$(security cms -D -i "$f" 2>/dev/null) || continue
  NAME=$(printf '%s' "$PLIST" | plutil -extract Name raw - 2>/dev/null)
  if printf '%s' "$PLIST" | plutil -p - 2>/dev/null | grep -q "$GROUP"; then
    echo "  yes: $NAME"
    FOUND=1
  fi
done
if [ "$FOUND" -eq 0 ]; then
  echo "  none. Apple has not registered the App Group against the App ID yet."
  echo "  Open Glow.xcodeproj in Xcode, add App Groups to BOTH targets, then"
  echo "  build to a device once from Xcode so it mints a profile."
  STATUS=1
fi

echo
echo "== Last built app =="
APP=$(find build/device/Build/Products -maxdepth 3 -name "Glow.app" 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "  no device build found; run a device build first"
else
  for TARGET in "$APP" "$APP/PlugIns/GlowWidget.appex"; do
    [ -e "$TARGET" ] || continue
    LABEL=$(basename "$TARGET")
    if codesign -d --entitlements :- "$TARGET" 2>/dev/null | grep -q "$GROUP"; then
      echo "  $LABEL: has $GROUP"
    else
      echo "  $LABEL: MISSING $GROUP (stripped at signing)"
      STATUS=1
    fi
  done
fi

echo
if [ "$STATUS" -eq 0 ]; then
  echo "App Group is provisioned. The widget can read the store."
else
  echo "App Group is NOT provisioned. The app works; the widget will show nothing."
fi
exit "$STATUS"
