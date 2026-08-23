#!/bin/bash
# Archive, sign for the App Store, and upload to TestFlight.
#
# Needs an App Store Connect API key: the .p8 in
# ~/.appstoreconnect/private_keys/, and its identifiers in Tools/local.env —
# machine-local values, never committed:
#
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   TEAM_ID=XXXXXXXXXX
#
# Signing is cloud-managed through that key, overriding the project's manual
# development profiles for this build only: the manual pins exist so device
# builds work without an Apple ID in Xcode, and they would otherwise fight an
# App Store export.
#
# The build number is stamped with the current UTC time rather than taken from
# project.yml, so every upload is unique without a commit per upload and
# without touching MARKETING_VERSION, which is not this script's to move.
# Stamping it works on both bundles only since #133: the host target did not
# read CURRENT_PROJECT_VERSION at all, so this override moved the widget's
# build number and left the app's at xcodegen's literal 1.
#
# Nothing is uploaded that has not been validated. Tools/check-release-build.py
# reads the archive before the export and the exported .ipa before the upload —
# the same script CI runs on its Release build, so a version mismatch is caught
# on a pull request rather than by App Store Connect after the fact.
#
#     Tools/ship-testflight.sh [--skip-tests]
#
# --skip-tests is deliberate and says so on the way past: a build that goes to
# testers without the suite having run is a decision, not a default.

set -euo pipefail
cd "$(dirname "$0")/.."

RUN_TESTS=1
for argument in "$@"; do
  case "$argument" in
    --skip-tests) RUN_TESTS=0 ;;
    *)
      echo "error: unknown argument $argument. Usage: Tools/ship-testflight.sh [--skip-tests]" >&2
      exit 1
      ;;
  esac
done

ENV_FILE="Tools/local.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE is missing." >&2
  echo "Create it with ASC_KEY_ID, ASC_ISSUER_ID and TEAM_ID — see the header of this script." >&2
  exit 1
fi
source "$ENV_FILE"

for var in ASC_KEY_ID ASC_ISSUER_ID TEAM_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var is not set in $ENV_FILE." >&2
    exit 1
  fi
done

KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [[ ! -f "$KEY_PATH" ]]; then
  echo "error: $KEY_PATH is missing. Put the downloaded .p8 there." >&2
  exit 1
fi

BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Glow.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
BUILD_NUMBER=$(date -u +%Y%m%d%H%M)

# Regenerate before archiving, always.
#
# The project, the entitlements and both Info.plists are build artifacts
# generated from project.yml, and archiving whatever happens to be on disk
# ships whatever state that disk was left in. It has already cost one build:
# a stale Glow/Info.plist went up without ITSAppUsesNonExemptEncryption and
# TestFlight asked for the compliance answer the plist exists to pre-empt.
# Generating here costs a second and removes the whole class.
echo "==> Generating the project"
Tools/generate.sh

if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo "==> Running the suite before archiving"
  Tools/test.sh
else
  echo "==> Skipping the suite (--skip-tests). This build has not been tested."
fi

echo "==> Archiving (build $BUILD_NUMBER)"
xcodebuild \
  -project Glow.xcodeproj \
  -scheme Glow \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_STYLE=Automatic \
  PROVISIONING_PROFILE_SPECIFIER= \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -quiet

# Before the export, because an export takes minutes and a version mismatch is
# already decided by now. Signing is not asserted here — the archive is signed
# for distribution, but the thing that goes up is the .ipa, and that is where
# the entitlement and the profile are checked.
echo "==> Validating the archive"
/usr/bin/python3 Tools/check-release-build.py "$ARCHIVE"

echo "==> Exporting for App Store"
EXPORT_PLIST="$BUILD_DIR/exportOptions.plist"
mkdir -p "$BUILD_DIR"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -quiet

# Not `ls … | head -1`. Two .ipas in the export directory means the last export
# left one behind, and uploading whichever sorted first is how a stale build
# reaches testers.
shopt -s nullglob
EXPORTED=("$EXPORT_DIR"/*.ipa)
if [[ ${#EXPORTED[@]} -ne 1 ]]; then
  echo "error: the export directory holds ${#EXPORTED[@]} .ipa files; it should hold one." >&2
  # `"${EXPORTED[@]}"` on its own is an unbound variable in bash 3.2 — which is
  # the bash macOS ships — so the zero case would die reporting the wrong thing.
  if [[ ${#EXPORTED[@]} -gt 0 ]]; then
    printf '  %s\n' "${EXPORTED[@]}" >&2
  fi
  echo "Delete $BUILD_DIR and run this again." >&2
  exit 1
fi
IPA="${EXPORTED[0]}"

# The last thing before the upload, on the artifact that is uploaded — not on
# the archive it came from, because the export re-signs. --require-signing adds
# what only a signed bundle can answer: that the App Group survived codesign,
# and that the embedded profile has not expired.
echo "==> Validating $IPA"
/usr/bin/python3 Tools/check-release-build.py --require-signing "$IPA"

echo "==> Uploading $IPA"
xcrun altool --upload-app --type ios \
  -f "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploaded build $BUILD_NUMBER. TestFlight will process it shortly."
