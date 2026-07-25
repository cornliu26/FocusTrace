#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swiftpm-common.sh"
cd "$FOCUS_TRACE_ROOT"

if xcrun --find xctest >/dev/null 2>&1; then
  echo "[1/3] Running Swift unit tests"
else
  echo "[1/3] Building Swift unit tests (Command Line Tools has no xctest runner)"
  echo "      Executable behavior coverage continues in FocusTraceVerification."
fi
swift test "${SWIFTPM_COMMON_ARGS[@]}"

echo "[2/3] Verifying the Codex decision-brief file contract"
/usr/bin/python3 Scripts/test-codex-review-contract.py

echo "[3/3] Running FocusTrace regression, privacy, and performance gates"
swift run "${SWIFTPM_COMMON_ARGS[@]}" FocusTraceVerification
