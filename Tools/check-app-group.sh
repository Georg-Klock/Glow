#!/usr/bin/env bash
#
# Reports whether the App Group is actually provisioned.
#
#     Tools/check-app-group.sh [path/to/Glow.app]
#
# Exists because every failure mode here is silent. The entitlements file is in
# the repo, CODE_SIGN_ENTITLEMENTS is set, SystemCapabilities is in the project,
# the build succeeds, and codesign strips the entitlement anyway because the
# profile it picked never granted the group. Nothing warns you; the only symptom
# is a widget that shows no habits.
#
# The app is named, not searched for, and its absence is a failure rather than a
# shrug: this used to take whichever Glow.app `find` listed first and report
# success when there was none, which is a check that passes hardest when there
# is nothing to check. See #133.

set -uo pipefail

cd "$(dirname "$0")/.."

GROUP="group.com.georgklock.glow"
BUNDLE="com.georgklock.glow"
DEFAULT_APP="build/device/Build/Products/Debug-iphoneos/Glow.app"
APP="${1:-$DEFAULT_APP}"
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
echo "== $APP =="
if [ ! -d "$APP" ]; then
  echo "  no such app. A device build is what this half of the check reads:"
  echo "    xcodebuild build -project Glow.xcodeproj -scheme Glow \\"
  echo "      -destination 'generic/platform=iOS' -derivedDataPath build/device"
  echo "  or pass the path to one: Tools/check-app-group.sh path/to/Glow.app"
  STATUS=1
else
  # The identifier is read, not assumed. A signed app whose bundle id is not
  # this one has entitlements that say nothing about this app.
  FOUND_BUNDLE=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist" 2>/dev/null)
  if [ "$FOUND_BUNDLE" != "$BUNDLE" ]; then
    echo "  identifier is ${FOUND_BUNDLE:-unreadable}, not $BUNDLE — this is not the app."
    STATUS=1
  fi

  WIDGET="$APP/PlugIns/GlowWidget.appex"
  if [ ! -d "$WIDGET" ]; then
    echo "  GlowWidget.appex: not embedded, so there is no widget to grant anything to."
    STATUS=1
  fi

  for TARGET in "$APP" "$WIDGET"; do
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
  echo "App Group is provisioned and survived signing. The widget can read the store."
else
  echo "Not verified. Until every line above says yes, the app works and the"
  echo "widget shows nothing — and an unread build is not a passing one."
fi
exit "$STATUS"
