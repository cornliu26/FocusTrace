#!/bin/bash
set -euo pipefail

FOCUS_TRACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOCUS_TRACE_CACHE="$FOCUS_TRACE_ROOT/.build/caches"

mkdir -p \
  "$FOCUS_TRACE_CACHE/clang" \
  "$FOCUS_TRACE_CACHE/swiftpm" \
  "$FOCUS_TRACE_CACHE/config" \
  "$FOCUS_TRACE_CACHE/security"

export CLANG_MODULE_CACHE_PATH="$FOCUS_TRACE_CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$FOCUS_TRACE_CACHE/clang"
export SWIFT_EXEC="$FOCUS_TRACE_ROOT/Scripts/swiftc-compatible.sh"

SWIFTPM_COMMON_ARGS=(
  --disable-sandbox
  --cache-path "$FOCUS_TRACE_CACHE/swiftpm"
  --config-path "$FOCUS_TRACE_CACHE/config"
  --security-path "$FOCUS_TRACE_CACHE/security"
)
