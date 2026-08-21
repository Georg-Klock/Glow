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

set -euo pipefail
cd "$(dirname "$0")/.."

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

IPA=$(ls "$EXPORT_DIR"/*.ipa | head -1)
echo "==> Uploading $IPA"
xcrun altool --upload-app --type ios \
  -f "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploaded build $BUILD_NUMBER. TestFlight will process it shortly."
