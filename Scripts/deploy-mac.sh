#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RUN_TESTS=true
LAUNCH_APP=true
INSTALL_ROOT="$HOME/Applications"

usage() {
  cat <<'EOF'
Usage: ./Scripts/deploy-mac.sh [options]

Build, sign, install, and restart FocusTrace on this Mac.

Options:
  --skip-tests          Skip the test suite before building.
  --no-launch           Install without launching FocusTrace.
  --install-dir PATH    Install under PATH (default: ~/Applications).
  -h, --help            Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests)
      RUN_TESTS=false
      shift
      ;;
    --no-launch)
      LAUNCH_APP=false
      shift
      ;;
    --install-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --install-dir requires a path" >&2
        exit 2
      fi
      INSTALL_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: FocusTrace deployment requires macOS" >&2
  exit 1
fi

if [[ "$INSTALL_ROOT" != /* ]]; then
  INSTALL_ROOT="$(cd "$PROJECT_ROOT" && mkdir -p "$INSTALL_ROOT" && cd "$INSTALL_ROOT" && pwd)"
fi

SOURCE_APP="$PROJECT_ROOT/dist/FocusTrace.app"
TARGET_APP="$INSTALL_ROOT/FocusTrace.app"
TARGET_EXECUTABLE="$TARGET_APP/Contents/MacOS/FocusTrace"
BACKUP_APP="$INSTALL_ROOT/.FocusTrace.previous.app"
STAGING_DIR=""
HAD_PREVIOUS=false

cleanup_staging() {
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi
}
trap cleanup_staging EXIT

restore_previous_install() {
  if [[ -e "$TARGET_APP" ]]; then
    rm -rf -- "$TARGET_APP"
  fi
  if [[ "$HAD_PREVIOUS" == true && -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$TARGET_APP"
  fi
}

cd "$PROJECT_ROOT"

if [[ "$RUN_TESTS" == true ]]; then
  echo "[1/4] Running tests"
  "$SCRIPT_DIR/test.sh"
else
  echo "[1/4] Skipping tests"
fi

echo "[2/4] Building and signing FocusTrace.app"
"$SCRIPT_DIR/build-app.sh"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"

echo "[3/4] Installing to $TARGET_APP"
mkdir -p "$INSTALL_ROOT"
STAGING_DIR="$(mktemp -d "$INSTALL_ROOT/.focustrace-deploy.XXXXXX")"
STAGED_APP="$STAGING_DIR/FocusTrace.app"
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

if /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application id "com.local.FocusTrace" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

if /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
  /usr/bin/pkill -TERM -x FocusTrace >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

if /usr/bin/pgrep -x FocusTrace >/dev/null 2>&1; then
  echo "error: the existing FocusTrace process did not stop" >&2
  exit 1
fi

if [[ -e "$BACKUP_APP" ]]; then
  rm -rf -- "$BACKUP_APP"
fi
if [[ -e "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$BACKUP_APP"
  HAD_PREVIOUS=true
fi

if ! mv "$STAGED_APP" "$TARGET_APP"; then
  restore_previous_install
  echo "error: failed to install FocusTrace.app; restored the previous app" >&2
  exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$TARGET_APP"; then
  restore_previous_install
  echo "error: installed app failed signature verification; restored the previous app" >&2
  exit 1
fi

if [[ "$LAUNCH_APP" == true ]]; then
  echo "[4/4] Launching FocusTrace"
  if ! /usr/bin/open "$TARGET_APP"; then
    restore_previous_install
    echo "error: FocusTrace failed to launch; restored the previous app" >&2
    exit 1
  fi

  STARTED=false
  for _ in {1..20}; do
    if /usr/bin/pgrep -f -x "$TARGET_EXECUTABLE" >/dev/null 2>&1; then
      STARTED=true
      break
    fi
    sleep 0.25
  done
  if [[ "$STARTED" == true ]]; then
    sleep 2
    if ! /usr/bin/pgrep -f -x "$TARGET_EXECUTABLE" >/dev/null 2>&1; then
      STARTED=false
    fi
  fi
  if [[ "$STARTED" != true ]]; then
    restore_previous_install
    echo "error: FocusTrace did not remain running after launch; restored the previous app" >&2
    exit 1
  fi
else
  echo "[4/4] Launch skipped"
fi

if [[ -e "$BACKUP_APP" ]]; then
  rm -rf -- "$BACKUP_APP"
fi

echo "Deployed FocusTrace successfully: $TARGET_APP"
echo "Local activity data and preferences were not modified."
