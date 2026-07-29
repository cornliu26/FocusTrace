#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$PROJECT_ROOT/dist/FocusTrace.app}"
RUN_LAUNCH=false

if [[ $# -gt 2 ]]; then
  echo "Usage: ./Scripts/test-update.sh [APP_PATH] [--launch]" >&2
  exit 2
fi
if [[ "${2:-}" == "--launch" ]]; then
  RUN_LAUNCH=true
elif [[ $# -eq 2 ]]; then
  echo "Usage: ./Scripts/test-update.sh [APP_PATH] [--launch]" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: update acceptance requires macOS" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: FocusTrace.app not found: $APP_PATH" >&2
  exit 1
fi

UPDATER_IN_APP="$APP_PATH/Contents/MacOS/FocusTraceUpdater"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -x "$UPDATER_IN_APP" || ! -f "$INFO_PLIST" ]]; then
  echo "error: candidate app is missing its updater or Info.plist" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focustrace-update-acceptance.XXXXXX")"
LAUNCHED_PROBE=false

cleanup() {
  if [[ "$LAUNCHED_PROBE" == true ]]; then
    /usr/bin/pkill -TERM -x FocusTrace >/dev/null 2>&1 || true
  fi
  chmod 755 "$WORK_ROOT/failure-install" >/dev/null 2>&1 || true
  rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT

make_old_fixture() {
  local target="$1"
  /usr/bin/ditto "$APP_PATH" "$target"
  /usr/libexec/PlistBuddy \
    -c 'Set :CFBundleShortVersionString 0.0.0' \
    "$target/Contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c 'Set :CFBundleVersion 0' \
    "$target/Contents/Info.plist"
  /usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --identifier com.local.FocusTrace \
    "$target" >/dev/null
}

echo "[update] Replacing a writable old app"
mkdir -p "$WORK_ROOT/success-install"
SUCCESS_TARGET="$WORK_ROOT/success-install/FocusTrace.app"
SUCCESS_RESULT="$WORK_ROOT/success-result.json"
SUCCESS_HELPER="$WORK_ROOT/FocusTraceUpdater-success"
make_old_fixture "$SUCCESS_TARGET"
cp "$SUCCESS_TARGET/Contents/MacOS/FocusTraceUpdater" "$SUCCESS_HELPER"
chmod 755 "$SUCCESS_HELPER"
"$SUCCESS_HELPER" \
  "$APP_PATH" \
  "$SUCCESS_TARGET" \
  0 \
  --no-launch \
  --result "$SUCCESS_RESULT"

INSTALLED_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$SUCCESS_TARGET/Contents/Info.plist"
)"
INSTALLED_BUILD="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "$SUCCESS_TARGET/Contents/Info.plist"
)"
[[ "$INSTALLED_VERSION" == "$VERSION" ]]
[[ "$INSTALLED_BUILD" == "$BUILD" ]]
[[ "$(plutil -extract outcome raw "$SUCCESS_RESULT")" == "succeeded" ]]
[[ "$(plutil -extract stage raw "$SUCCESS_RESULT")" == "completed" ]]
/usr/bin/codesign --verify --deep --strict "$SUCCESS_TARGET"

if find "$WORK_ROOT/success-install" -maxdepth 1 \
  \( -name '.focustrace-update-*' -o -name '.FocusTrace.update-backup-*.app' \) \
  -print -quit | rg -q '.'; then
  echo "error: updater left staging or backup files after success" >&2
  exit 1
fi

if [[ "$RUN_LAUNCH" == true ]]; then
  echo "[update] Relaunching the replaced app with an in-memory probe"
  if /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
    echo "error: close running FocusTrace instances before launch acceptance" >&2
    exit 1
  fi

  mkdir -p "$WORK_ROOT/launch-install"
  LAUNCH_TARGET="$WORK_ROOT/launch-install/FocusTrace.app"
  LAUNCH_RESULT="$WORK_ROOT/launch-result.json"
  LAUNCH_HELPER="$WORK_ROOT/FocusTraceUpdater-launch"
  make_old_fixture "$LAUNCH_TARGET"
  cp "$LAUNCH_TARGET/Contents/MacOS/FocusTraceUpdater" "$LAUNCH_HELPER"
  chmod 755 "$LAUNCH_HELPER"
  LAUNCHED_PROBE=true
  "$LAUNCH_HELPER" \
    "$APP_PATH" \
    "$LAUNCH_TARGET" \
    0 \
    --launch-probe \
    --result "$LAUNCH_RESULT"
  [[ "$(plutil -extract outcome raw "$LAUNCH_RESULT")" == "succeeded" ]]
  /usr/bin/pgrep -x FocusTrace >/dev/null
  /usr/bin/pkill -TERM -x FocusTrace
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
  if /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
    echo "error: launch acceptance app did not stop" >&2
    exit 1
  fi
  LAUNCHED_PROBE=false
fi

echo "[update] Preserving the old app when replacement is not writable"
mkdir -p "$WORK_ROOT/failure-install"
FAILURE_TARGET="$WORK_ROOT/failure-install/FocusTrace.app"
FAILURE_RESULT="$WORK_ROOT/failure-result.json"
FAILURE_HELPER="$WORK_ROOT/FocusTraceUpdater-failure"
make_old_fixture "$FAILURE_TARGET"
cp "$FAILURE_TARGET/Contents/MacOS/FocusTraceUpdater" "$FAILURE_HELPER"
chmod 755 "$FAILURE_HELPER"
chmod 555 "$WORK_ROOT/failure-install"

set +e
"$FAILURE_HELPER" \
  "$APP_PATH" \
  "$FAILURE_TARGET" \
  0 \
  --no-launch \
  --result "$FAILURE_RESULT"
FAILURE_STATUS=$?
set -e
chmod 755 "$WORK_ROOT/failure-install"

if [[ "$FAILURE_STATUS" -eq 0 ]]; then
  echo "error: updater unexpectedly replaced an app in a read-only directory" >&2
  exit 1
fi
[[ "$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$FAILURE_TARGET/Contents/Info.plist"
)" == "0.0.0" ]]
[[ "$(plutil -extract outcome raw "$FAILURE_RESULT")" == "failed" ]]
[[ "$(
  plutil -extract failureCode raw "$FAILURE_RESULT"
)" == "installLocationNotWritable" ]]
if rg -q '/Users/|workflow|activity' "$FAILURE_RESULT"; then
  echo "error: update result contains private path or behavior metadata" >&2
  exit 1
fi

echo "FocusTrace update acceptance passed: 0.0.0 (0) -> $VERSION ($BUILD)"
