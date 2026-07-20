#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swiftpm-common.sh"
cd "$FOCUS_TRACE_ROOT"

swift build -c release --product FocusTraceSpaceAcceptance "${SWIFTPM_COMMON_ARGS[@]}"
BIN_DIR="$(swift build -c release --show-bin-path "${SWIFTPM_COMMON_ARGS[@]}")"

APP_PATH="$FOCUS_TRACE_ROOT/dist/FocusTraceSpaceAcceptance.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"

if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi
mkdir -p "$MACOS_DIR"
install -m 755 "$BIN_DIR/FocusTraceSpaceAcceptance" "$MACOS_DIR/FocusTraceAccept"
install -m 644 "$FOCUS_TRACE_ROOT/Packaging/SpaceAcceptance-Info.plist" "$CONTENTS/Info.plist"

codesign --force --deep --sign - --identifier com.local.FocusTrace.SpaceAcceptance "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "$APP_PATH"
