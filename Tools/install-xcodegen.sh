#!/usr/bin/env bash
#
# Installs the XcodeGen named by Tools/xcodegen.pin into a gitignored cache and
# prints the path to the binary.
#
# The point is that a fresh machine and a CI runner resolve the same bytes.
# `brew install xcodegen` resolves whatever is current on the day, and the
# generated project is not a pure function of project.yml — it is a function of
# project.yml *and* the generator. So the generator is pinned by digest: a
# release asset that has been re-cut, or a download that was tampered with in
# flight, fails here rather than producing a project nobody reviewed.
#
# Idempotent, and offline once the cache is warm.

set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=xcodegen.pin
source Tools/xcodegen.pin

CACHE="Tools/.xcodegen/${XCODEGEN_VERSION}"
BINARY="${CACHE}/xcodegen/bin/xcodegen"

if [ -x "$BINARY" ]; then
  echo "$PWD/$BINARY"
  exit 0
fi

URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
ARCHIVE=$(mktemp -t xcodegen.zip)
trap 'rm -f "$ARCHIVE"' EXIT

echo "install-xcodegen: fetching ${XCODEGEN_VERSION}" >&2
if ! curl --fail --silent --show-error --location --retry 3 --output "$ARCHIVE" "$URL"; then
  echo "error: could not download $URL" >&2
  exit 1
fi

ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
if [ "$ACTUAL" != "$XCODEGEN_SHA256" ]; then
  echo "error: XcodeGen ${XCODEGEN_VERSION} did not match its pinned digest." >&2
  echo "  expected $XCODEGEN_SHA256" >&2
  echo "  actual   $ACTUAL" >&2
  echo "The release asset changed, or the download did. Do not generate with it." >&2
  exit 1
fi

rm -rf "$CACHE"
mkdir -p "$CACHE"
unzip -q "$ARCHIVE" -d "$CACHE"

if [ ! -x "$BINARY" ]; then
  echo "error: the archive did not contain xcodegen/bin/xcodegen" >&2
  exit 1
fi

# The digest covered the archive; this covers the thing that will actually run.
# A binary with the right filename and the right --version string is exactly
# the substitution the pin exists to catch, so the version is read back from
# the binary that was just unpacked rather than trusted from the filename.
REPORTED=$("$BINARY" --version 2>/dev/null | tr -d '\r')
case "$REPORTED" in
  *"$XCODEGEN_VERSION"*) ;;
  *)
    rm -rf "$CACHE"
    echo "error: unpacked xcodegen reports '${REPORTED}', not ${XCODEGEN_VERSION}" >&2
    exit 1
    ;;
esac

echo "$PWD/$BINARY"
