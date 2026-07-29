#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: ./Scripts/verify-release-assets.sh TAG ARCHIVE MANIFEST" >&2
  exit 2
fi

TAG="$1"
ARCHIVE="$2"
MANIFEST="$3"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag must match vX.Y.Z" >&2
  exit 2
fi
if [[ ! -f "$ARCHIVE" || ! -f "$MANIFEST" ]]; then
  echo "error: release archive or manifest is missing" >&2
  exit 1
fi

VERSION="${TAG#v}"
MANIFEST_SCHEMA="$(plutil -extract schemaVersion raw "$MANIFEST")"
MANIFEST_VERSION="$(plutil -extract version raw "$MANIFEST")"
MANIFEST_BUILD="$(plutil -extract build raw "$MANIFEST")"
MANIFEST_BUNDLE="$(plutil -extract bundleIdentifier raw "$MANIFEST")"
MANIFEST_URL="$(plutil -extract assetURL raw "$MANIFEST")"
MANIFEST_SHA="$(plutil -extract sha256 raw "$MANIFEST")"
MANIFEST_SIZE="$(plutil -extract size raw "$MANIFEST")"

[[ "$MANIFEST_SCHEMA" == "1" ]]
[[ "$MANIFEST_VERSION" == "$VERSION" ]]
[[ "$MANIFEST_BUILD" =~ ^[0-9]+$ ]]
[[ "$MANIFEST_BUNDLE" == "com.local.FocusTrace" ]]
[[ "$MANIFEST_URL" == \
  "https://github.com/cornliu26/FocusTrace/releases/download/$TAG/FocusTrace-macOS-arm64.zip" ]]

ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
ACTUAL_SIZE="$(/usr/bin/stat -f '%z' "$ARCHIVE")"
[[ "$ACTUAL_SHA" == "$MANIFEST_SHA" ]]
[[ "$ACTUAL_SIZE" == "$MANIFEST_SIZE" ]]

/usr/bin/unzip -t "$ARCHIVE" >/dev/null
VERIFY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focustrace-release-verify.XXXXXX")"
cleanup() {
  rm -rf -- "$VERIFY_ROOT"
}
trap cleanup EXIT

/usr/bin/ditto -x -k "$ARCHIVE" "$VERIFY_ROOT"
APP_PATH="$VERIFY_ROOT/FocusTrace.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

/usr/bin/codesign --verify --deep --strict "$APP_PATH"
[[ "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$INFO_PLIST"
)" == "$VERSION" ]]
[[ "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "$INFO_PLIST"
)" == "$MANIFEST_BUILD" ]]
[[ -x "$APP_PATH/Contents/MacOS/FocusTraceUpdater" ]]
[[ -x "$APP_PATH/Contents/Resources/CodexBridge/FocusTraceReport" ]]
[[ -x "$APP_PATH/Contents/Resources/CodexBridge/install-codex-review.py" ]]

echo "Release assets verified: $TAG ($ACTUAL_SIZE bytes, sha256 $ACTUAL_SHA)"
