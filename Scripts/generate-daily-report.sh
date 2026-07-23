#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOCUS_TRACE_PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
FOCUS_TRACE_STORE="${FOCUSTRACE_STORE_PATH:-$HOME/Library/Application Support/FocusTrace/store.json}"
FOCUS_TRACE_REPORT_BIN="$FOCUS_TRACE_PROJECT/dist/FocusTraceReport"
FOCUS_TRACE_REPORT_DIR="$FOCUS_TRACE_PROJECT/.focustrace/reports"
FOCUS_TRACE_BRIDGE_DIR="${FOCUSTRACE_BRIDGE_DIR:-$HOME/Library/Application Support/FocusTrace/CodexBridge}"

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

# Register only the aggregate report directory. The app never reads store.json
# through this bridge, and Codex writes its aggregate-only interpretation back
# beside the dated report that it analyzed.
mkdir -p "$FOCUS_TRACE_BRIDGE_DIR"
/usr/bin/python3 - "$FOCUS_TRACE_BRIDGE_DIR/bridge.json" "$FOCUS_TRACE_REPORT_DIR" <<'PY'
import datetime
import json
import os
import pathlib
import sys

destination, report_directory = sys.argv[1:]
destination_path = pathlib.Path(destination)
temporary_path = destination_path.with_suffix(".tmp")
payload = {
    "schemaVersion": 1,
    "reportDirectory": str(pathlib.Path(report_directory).resolve()),
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(
        timespec="seconds"
    ).replace("+00:00", "Z"),
}
temporary_path.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
os.replace(temporary_path, destination_path)
PY

echo "FocusTrace Codex 文件桥已连接：$FOCUS_TRACE_BRIDGE_DIR/bridge.json"
