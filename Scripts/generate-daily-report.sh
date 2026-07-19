#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOCUS_TRACE_PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
FOCUS_TRACE_STORE="${FOCUSTRACE_STORE_PATH:-$HOME/Library/Application Support/FocusTrace/store.json}"
FOCUS_TRACE_REPORT_BIN="$FOCUS_TRACE_PROJECT/dist/FocusTraceReport"
FOCUS_TRACE_REPORT_DIR="$FOCUS_TRACE_PROJECT/.focustrace/reports"

cd "$FOCUS_TRACE_PROJECT"

if [[ -x "$FOCUS_TRACE_REPORT_BIN" ]]; then
  "$FOCUS_TRACE_REPORT_BIN" \
    --store "$FOCUS_TRACE_STORE" \
    --output-dir "$FOCUS_TRACE_REPORT_DIR"
else
  source "$SCRIPT_DIR/swiftpm-common.sh"
  swift run -c release "${SWIFTPM_COMMON_ARGS[@]}" FocusTraceReport \
    --store "$FOCUS_TRACE_STORE" \
    --output-dir "$FOCUS_TRACE_REPORT_DIR"
fi
