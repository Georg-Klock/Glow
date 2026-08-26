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
#     Tools/ship-testflight.sh [--skip-tests] [--preflight-only] [--allow-unverified-ci]
#
# --skip-tests is deliberate and says so on the way past: a build that goes to
# testers without the suite having run is a decision, not a default. It skips
# the local suite only; the source preflight below does not care about it.
#
# --preflight-only answers "would this checkout be allowed to ship?" and stops
# there — no credentials read, no archive, no upload.
#
# --allow-unverified-ci is the one narrow override (#287): it covers exactly
# the CI-verdict proof, for the machine that cannot reach GitHub or the SHA
# whose run genuinely cannot be consulted. It is printed loudly and recorded in
# the provenance file. There is deliberately no override for a dirty tree or a
# ref that is not origin/main — an unreproducible release is not a flag away.

set -euo pipefail
cd "$(dirname "$0")/.."

RUN_TESTS=1
PREFLIGHT_ONLY=0
ALLOW_UNVERIFIED_CI=0
for argument in "$@"; do
  case "$argument" in
    --skip-tests) RUN_TESTS=0 ;;
    --preflight-only) PREFLIGHT_ONLY=1 ;;
    --allow-unverified-ci) ALLOW_UNVERIFIED_CI=1 ;;
    *)
      echo "error: unknown argument $argument. Usage: Tools/ship-testflight.sh [--skip-tests] [--preflight-only] [--allow-unverified-ci]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------- preflight
#
# Before credentials, before generation, before anything that costs a minute:
# the questions below are about *which source* this is, and every one of them
# is already answered by the time an archive exists. The existing validators
# ask "is this bundle internally consistent and correctly signed?"; this asks
# "which reviewed commit produced it?" — and a cleanly signed build of a dirty,
# stale or unreviewed tree passes the first question perfectly. See #287.

echo "==> Preflight: verifying the source tree"

# The remote's opinion is the one that matters, and it cannot be consulted
# from a cache. No fetch, no release — offline is a fact, not an emergency.
if ! git fetch origin --tags 2>/dev/null; then
  echo "error: could not fetch origin. A release ref is a claim about the" >&2
  echo "remote, and this machine cannot currently ask it. Get online and" >&2
  echo "run this again — there is no offline override for the source ref." >&2
  exit 1
fi

# A dirty tree has no override. `--porcelain` lists tracked modifications and
# untracked non-ignored files alike; ignored build products do not appear.
DIRTY=$(git status --porcelain)
if [[ -n "$DIRTY" ]]; then
  echo "error: the working tree is not clean:" >&2
  printf '%s\n' "$DIRTY" | sed 's/^/  /' >&2
  echo "A build of a dirty tree cannot be reproduced from any commit." >&2
  echo "Commit, stash or remove the changes above. There is no override." >&2
  exit 1
fi

HEAD_SHA=$(git rev-parse HEAD)
MAIN_SHA=$(git rev-parse origin/main)
RELEASE_REF=""
if [[ "$HEAD_SHA" == "$MAIN_SHA" ]]; then
  RELEASE_REF="origin/main"
else
  # Not main; the only other allowed source is an annotated release tag that
  # the remote holds, pointing exactly here. A lightweight local tag is a
  # bookmark, not a release decision.
  TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || true)
  if [[ -n "$TAG" ]] && [[ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null)" == "tag" ]]; then
    REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}' | head -1)
    LOCAL_TAG_OBJECT=$(git rev-parse "refs/tags/$TAG")
    if [[ -n "$REMOTE_TAG" && "$REMOTE_TAG" == "$LOCAL_TAG_OBJECT" ]]; then
      RELEASE_REF="tag $TAG"
    fi
  fi
fi

if [[ -z "$RELEASE_REF" ]]; then
  echo "error: HEAD ($HEAD_SHA) is not fetched origin/main ($MAIN_SHA)" >&2
  echo "and no annotated tag on origin points at it. A TestFlight build" >&2
  echo "comes from the reviewed branch or from a pushed release tag —" >&2
  echo "not from whatever happened to be checked out. There is no override." >&2
  exit 1
fi

# The commit is the right one; now the proof that CI agreed with it. All check
# runs for the SHA must have completed without failing, and at least one must
# have succeeded — phrased that way rather than by job name, so adding a lane
# tightens this gate instead of dodging it.
CI_VERDICT="unverified"
set +e
CHECKS_JSON=$(gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs?per_page=100" 2>&1)
CHECKS_STATUS=$?
set -e
if [[ $CHECKS_STATUS -eq 0 ]]; then
  CI_VERDICT=$(printf '%s' "$CHECKS_JSON" | /usr/bin/python3 -c '
import json, sys
runs = json.load(sys.stdin).get("check_runs", [])
if not runs:
    print("no-runs"); sys.exit(0)
pending = [r["name"] for r in runs if r.get("status") != "completed"]
failed = [r["name"] for r in runs
          if r.get("status") == "completed"
          and r.get("conclusion") not in ("success", "neutral", "skipped")]
succeeded = [r["name"] for r in runs if r.get("conclusion") == "success"]
if failed:
    print("failed: " + ", ".join(sorted(set(failed))))
elif pending:
    print("pending: " + ", ".join(sorted(set(pending))))
elif not succeeded:
    print("no-runs")
else:
    print("success")
')
fi

if [[ "$CI_VERDICT" != "success" ]]; then
  if [[ $CHECKS_STATUS -ne 0 ]]; then
    echo "warning: could not ask GitHub for $HEAD_SHA's checks (gh exited $CHECKS_STATUS)." >&2
  else
    echo "warning: CI for $HEAD_SHA is not a clean success: $CI_VERDICT" >&2
  fi
  if [[ "$ALLOW_UNVERIFIED_CI" -eq 1 ]]; then
    echo "==> Proceeding WITHOUT a CI verdict for $HEAD_SHA (--allow-unverified-ci)."
    echo "    This is recorded in the provenance file."
    CI_VERDICT="overridden: $CI_VERDICT"
  else
    echo "error: no successful CI verdict for $HEAD_SHA." >&2
    echo "Wait for the run to finish (gh run list --commit $HEAD_SHA), fix it," >&2
    echo "or — if GitHub genuinely cannot be consulted — rerun with" >&2
    echo "--allow-unverified-ci, which says so in the provenance record." >&2
    exit 1
  fi
fi

BUILD_NUMBER=$(date -u +%Y%m%d%H%M)
XCODE_VERSION=$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')
MARKETING_VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')

# The record that binds the upload to its source. private/ is the repository's
# durable-but-not-shipping place, and gitignored, so the trail survives
# `rm -rf build` without ever becoming a commit. No secrets: the key id, the
# issuer and every path stay in Tools/local.env where they live.
PROVENANCE_DIR="private/provenance"
mkdir -p "$PROVENANCE_DIR"
PROVENANCE="$PROVENANCE_DIR/$(date -u +%Y%m%d-%H%M%S)-${HEAD_SHA:0:12}.json"
/usr/bin/python3 - "$PROVENANCE" <<PY
import json, sys
json.dump({
    "sourceSHA": "$HEAD_SHA",
    "releaseRef": "$RELEASE_REF",
    "ciVerdict": "$CI_VERDICT",
    "xcode": "$XCODE_VERSION",
    "marketingVersion": "$MARKETING_VERSION",
    "buildNumber": "$BUILD_NUMBER",
    "testsRun": $([[ "$RUN_TESTS" -eq 1 ]] && echo True || echo False),
    "recordedAtUTC": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "uploaded": False,
}, open(sys.argv[1], "w"), indent=2)
PY

echo "==> Preflight passed: $RELEASE_REF at $HEAD_SHA"
echo "    CI: $CI_VERDICT"
echo "    Provenance: $PROVENANCE"

if [[ "$PREFLIGHT_ONLY" -eq 1 ]]; then
  echo "==> --preflight-only: stopping before credentials, build and upload."
  exit 0
fi

# ------------------------------------------------------------ credentials

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
# BUILD_NUMBER was stamped by the preflight above, so the provenance record
# and the archive cannot disagree about which build this is.

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

# The upload happened; the provenance record now says so, next to the SHA it
# already named. This is the line that turns "a build was made from X" into
# "the build testers have came from X".
/usr/bin/python3 - "$PROVENANCE" <<'PY'
import json, sys
path = sys.argv[1]
record = json.load(open(path))
record["uploaded"] = True
json.dump(record, open(path, "w"), indent=2)
PY

echo "==> Uploaded build $BUILD_NUMBER from $RELEASE_REF at $HEAD_SHA."
echo "    Provenance: $PROVENANCE"
echo "    TestFlight will process it shortly."
