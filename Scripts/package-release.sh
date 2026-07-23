#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_TESTS=true

usage() {
  echo "Usage: ./Scripts/package-release.sh vX.Y.Z [--skip-tests]"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

TAG="$1"
if [[ "${2:-}" == "--skip-tests" ]]; then
  RUN_TESTS=false
elif [[ $# -eq 2 ]]; then
  usage >&2
  exit 2
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag must match vX.Y.Z" >&2
  exit 2
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Packaging/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_ROOT/Packaging/Info.plist")"
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PROJECT_ROOT/Packaging/Info.plist")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PROJECT_ROOT/Packaging/Info.plist")"

if [[ "$TAG" != "v$VERSION" ]]; then
  echo "error: tag $TAG does not match app version $VERSION" >&2
  exit 1
fi

cd "$PROJECT_ROOT"
if [[ "$RUN_TESTS" == true ]]; then
  "$SCRIPT_DIR/test.sh"
fi

FOCUS_TRACE_BUILD_ARCH=arm64 "$SCRIPT_DIR/build-app.sh"

RELEASE_DIR="$PROJECT_ROOT/dist/release"
ARCHIVE="$RELEASE_DIR/FocusTrace-macOS-arm64.zip"
MANIFEST="$RELEASE_DIR/latest.json"
rm -rf -- "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/dist/FocusTrace.app" "$ARCHIVE"

SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
SIZE="$(/usr/bin/stat -f '%z' "$ARCHIVE")"
ASSET_URL="https://github.com/cornliu26/FocusTrace/releases/download/$TAG/FocusTrace-macOS-arm64.zip"

/usr/bin/python3 - "$MANIFEST" "$VERSION" "$BUILD" "$MINIMUM_SYSTEM_VERSION" "$BUNDLE_IDENTIFIER" "$ASSET_URL" "$SHA256" "$SIZE" <<'PY'
import json
import pathlib
import sys

manifest, version, build, minimum, bundle_id, asset_url, sha256, size = sys.argv[1:]
payload = {
    "schemaVersion": 1,
    "version": version,
    "build": build,
    "minimumSystemVersion": minimum,
    "bundleIdentifier": bundle_id,
    "assetURL": asset_url,
    "sha256": sha256,
    "size": int(size),
}
pathlib.Path(manifest).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

echo "Release archive: $ARCHIVE"
echo "Update manifest: $MANIFEST"
echo "SHA-256: $SHA256"
