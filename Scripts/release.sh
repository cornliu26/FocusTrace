#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: ./Scripts/release.sh vX.Y.Z" >&2
  exit 2
fi

TAG="$1"
VERSION="${TAG#v}"
cd "$PROJECT_ROOT"

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "error: releases must start from the protected main branch" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree must be clean before release" >&2
  exit 1
fi

APP_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    Packaging/Info.plist
)"
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  echo "error: tag $TAG does not match app version $APP_VERSION" >&2
  exit 1
fi

echo "[release 1/4] Confirming protected main is current"
git fetch origin main
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_MAIN_SHA="$(git rev-parse origin/main)"
if [[ "$HEAD_SHA" != "$REMOTE_MAIN_SHA" ]]; then
  echo "error: local main is not identical to origin/main" >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/tags/$TAG"; then
  echo "error: local tag already exists: $TAG" >&2
  exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "error: remote tag already exists: $TAG" >&2
  exit 1
fi

echo "[release 2/4] Running tests, packaging, and update acceptance"
"$SCRIPT_DIR/package-release.sh" "$TAG"

if [[ "$(git rev-parse HEAD)" != "$HEAD_SHA" || -n "$(git status --porcelain)" ]]; then
  echo "error: source changed during release preflight" >&2
  exit 1
fi

echo "[release 3/4] Creating annotated tag $TAG"
git tag -a "$TAG" -m "FocusTrace $TAG"

echo "[release 4/4] Pushing tag and starting the draft release workflow"
if ! git push origin "$TAG"; then
  git tag -d "$TAG" >/dev/null
  echo "error: tag push failed; the newly created local tag was rolled back" >&2
  exit 1
fi

echo "Release workflow started for $TAG."
echo "The GitHub Release remains a draft until uploaded assets pass verification."
