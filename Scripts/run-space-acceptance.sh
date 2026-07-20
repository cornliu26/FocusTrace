#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/swiftpm-common.sh"
cd "$FOCUS_TRACE_ROOT"

"$SCRIPT_DIR/build-space-acceptance-app.sh"
open "$FOCUS_TRACE_ROOT/dist/FocusTraceSpaceAcceptance.app"
