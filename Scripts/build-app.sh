#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swiftpm-common.sh"
cd "$FOCUS_TRACE_ROOT"

BUILD_ARGS=(-c release "${SWIFTPM_COMMON_ARGS[@]}")
if [[ -n "${FOCUS_TRACE_BUILD_ARCH:-}" ]]; then
  BUILD_ARGS+=(--arch "$FOCUS_TRACE_BUILD_ARCH")
fi

swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build --show-bin-path "${BUILD_ARGS[@]}")"

APP_PATH="$FOCUS_TRACE_ROOT/dist/FocusTrace.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
CODEX_BRIDGE_RESOURCES="$RESOURCES_DIR/CodexBridge"

if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CODEX_BRIDGE_RESOURCES"
install -m 755 "$BIN_DIR/FocusTrace" "$MACOS_DIR/FocusTrace"
install -m 755 "$BIN_DIR/FocusTraceUpdater" "$MACOS_DIR/FocusTraceUpdater"
install -m 755 "$BIN_DIR/FocusTraceReport" "$FOCUS_TRACE_ROOT/dist/FocusTraceReport"
install -m 755 "$BIN_DIR/FocusTraceReport" "$CODEX_BRIDGE_RESOURCES/FocusTraceReport"
install -m 755 \
  "$FOCUS_TRACE_ROOT/Scripts/install-codex-review.py" \
  "$CODEX_BRIDGE_RESOURCES/install-codex-review.py"
install -m 644 "$FOCUS_TRACE_ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
install -m 644 "$FOCUS_TRACE_ROOT/Packaging/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - --identifier com.local.FocusTrace "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "$APP_PATH"
