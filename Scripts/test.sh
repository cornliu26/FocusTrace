#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swiftpm-common.sh"
cd "$FOCUS_TRACE_ROOT"

swift test "${SWIFTPM_COMMON_ARGS[@]}"
swift run "${SWIFTPM_COMMON_ARGS[@]}" FocusTraceVerification
