#!/bin/bash
set -euo pipefail

# macOS beta Command Line Tools can briefly ship a Swift compiler one patch
# newer than the SDK's .swiftinterface files. Detect that patch skew instead
# of baking in a version, so the wrapper becomes a no-op after CLT updates.
SWIFTC_BIN="$(xcrun --find swiftc)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_INTERFACE="$SDK_PATH/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"

SDK_COMPILER_VERSION=""
if [[ -f "$SDK_INTERFACE" ]]; then
  SDK_COMPILER_VERSION="$(sed -nE 's#// swift-compiler-version: Apple Swift version ([0-9.]+).*#\1#p' "$SDK_INTERFACE" | head -1)"
fi

CURRENT_COMPILER_VERSION="$($SWIFTC_BIN --version 2>&1 | sed -nE 's#.*Apple Swift version ([0-9.]+).*#\1#p' | head -1)"

if [[ -n "$SDK_COMPILER_VERSION" && "$SDK_COMPILER_VERSION" != "$CURRENT_COMPILER_VERSION" ]]; then
  exec "$SWIFTC_BIN" \
    -Xfrontend -interface-compiler-version \
    -Xfrontend "$SDK_COMPILER_VERSION" \
    "$@"
fi

exec "$SWIFTC_BIN" "$@"
