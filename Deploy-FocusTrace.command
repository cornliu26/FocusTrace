#!/bin/bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS=0
"$PROJECT_ROOT/Scripts/deploy-mac.sh" "$@" || STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo
  echo "FocusTrace 部署失败（退出码 $STATUS）。"
  read -r -p "按回车键关闭窗口。"
  exit "$STATUS"
fi

echo
echo "FocusTrace 已完成测试、安装并重新启动。"
