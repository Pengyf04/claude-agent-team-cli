#!/bin/bash
# shutdown-team.sh <项目目录>
# 关闭 launch-team.sh 记录的角色窗口：先结束窗口内进程（轮询确认退出，超时升级 kill -9），
# 再关窗口（避免 Terminal 弹"终止进程"确认框）。不动 main 窗口。清理 runner 脚本与记录文件。
set -euo pipefail

PROJ="$(cd "${1:?用法: shutdown-team.sh <项目目录>}" && pwd)"
RUNTIME_DIR="$PROJ/.claude/agent-team-cli"
WINFILE="$RUNTIME_DIR/windows.txt"
[ -f "$WINFILE" ] || { echo "错误: 找不到 $WINFILE（未用 launch-team.sh 启动过？）" >&2; exit 1; }

while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  role="${pair%%=*}"; wid="${pair##*=}"
  [ "$role" = "main" ] && continue
  case "$wid" in ''|0|*[!0-9]*) echo "跳过 $role（无有效窗口 ID: '$wid'）"; continue ;; esac

  TTY="$(osascript -e "tell application \"Terminal\" to get tty of tab 1 of window id $wid" 2>/dev/null || true)"
  if [ -n "$TTY" ]; then
    TSHORT="${TTY#/dev/}"
    pkill -t "$TSHORT" 2>/dev/null || true
    # 轮询最多 5 秒等进程退出，仍在则 kill -9 再等 2 秒
    for _ in 1 2 3 4 5; do
      pgrep -t "$TSHORT" >/dev/null 2>&1 || break
      sleep 1
    done
    if pgrep -t "$TSHORT" >/dev/null 2>&1; then
      pkill -9 -t "$TSHORT" 2>/dev/null || true
      sleep 2
    fi
  fi
  if osascript -e "tell application \"Terminal\" to close window id $wid" 2>/dev/null; then
    echo "已关闭 $role 窗口 (id=$wid)"
  else
    echo "警告: 关闭 $role 窗口失败或已关闭 (id=$wid)——若窗口仍在请手动关闭" >&2
  fi
done < "$WINFILE"

rm -f "$WINFILE" "$RUNTIME_DIR"/run-*.sh
echo "团队窗口清理完成。"
echo "提示: 项目 .claude/settings.local.json 中的 crossSessionInbound=accept 仍然生效；若本项目不再跑团队，建议移除该键。"
