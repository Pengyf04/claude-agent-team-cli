#!/bin/bash
# restart-role.sh <项目目录> <角色: planner|plan-reviewer|executor|verifier>
# 重启单个角色会话：结束其旧窗口进程并关窗 → 用同一 runner 重开（同名重新注册、重发 READY）→ 更新 windows.txt。
# 用途：某角色会话"坏了"（如曾向 socket 地址发消息导致其后续回报持续被扣、卡死、误关）时的恢复路径。
# 注意：需以非沙箱方式执行（要结束进程与控制 Terminal.app）。
set -euo pipefail

# ---------- 带超时的 osascript ----------
# 无窗口服务器 / 自动化授权未决的环境下 osascript 会无限阻塞而非报错。超时按失败处理。
# 本脚本是"角色坏掉时的救援工具"，它自己更不能挂死。
# 下面的 >/dev/null 是承重的：kill -9 杀不掉子 shell 底下正在跑的 sleep，那个孤儿会继承
# stdout；若 stdout 是管道，读端就永远等不到 EOF。
# 注意：后台执行的命令 stdin 会被 bash 重定向到 /dev/null，所以带 heredoc 的 osascript
# 不能直接套 osa —— 改把 AppleScript 写进临时文件、用 `osascript <文件>` 调用（见下）。
osa() {
  local secs="$1"; shift
  local out pid watcher rc
  out="$(mktemp)"
  "$@" >"$out" 2>&1 &
  pid=$!
  { sleep "$secs"; kill -9 "$pid" 2>/dev/null; } >/dev/null 2>&1 &
  watcher=$!
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  kill -9 "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  cat "$out"; rm -f "$out"
  return "$rc"
}
OSA_T="${ATC_OSA_TIMEOUT:-8}"
PROJ="$(cd "${1:?用法: restart-role.sh <项目目录> <角色>}" && pwd)"
ROLE="${2:?用法: restart-role.sh <项目目录> <角色>}"
case "$ROLE" in planner|plan-reviewer|executor|verifier) ;; *) echo "错误: 角色必须是 planner|plan-reviewer|executor|verifier" >&2; exit 1 ;; esac
RUNTIME_DIR="$PROJ/.claude/agent-team-cli"
WINFILE="$RUNTIME_DIR/windows.txt"
RUNNER="$RUNTIME_DIR/run-$ROLE.sh"
[ -f "$RUNNER" ] || { echo "错误: 找不到 ${RUNNER}（团队未用 launch-team.sh 启动过？）" >&2; exit 1; }
[ -f "$WINFILE" ] || { echo "错误: 找不到 $WINFILE" >&2; exit 1; }

# 找到该角色记录（会话名可能带后缀：<role> 或 <role>-<suffix>）
LINE="$(grep -E "^$ROLE(-[^=]*)?=" "$WINFILE" | head -1 || true)"
[ -n "$LINE" ] || { echo "错误: windows.txt 中没有 $ROLE 的记录" >&2; exit 1; }
NAME="${LINE%%=*}"; OLD="${LINE##*=}"

# 1) 结束旧窗口内进程（先 TERM，轮询等待，再 KILL）并关窗
if [ -n "$OLD" ] && [ "$OLD" != "0" ] && osa "${OSA_T}" osascript -e "tell application \"Terminal\" to exists window id $OLD" 2>/dev/null | grep -q true; then
  TTY="$(osa "${OSA_T}" osascript -e "tell application \"Terminal\" to get tty of tab 1 of window id $OLD" 2>/dev/null || true)"
  if [ -n "$TTY" ]; then
    T="${TTY#/dev/}"
    pkill -t "$T" 2>/dev/null || true
    for _ in $(seq 1 15); do pgrep -t "$T" >/dev/null 2>&1 || break; sleep 1; done   # claude 优雅退出需数秒
    pgrep -t "$T" >/dev/null 2>&1 && { pkill -9 -t "$T" 2>/dev/null || true; sleep 2; }
  fi
  osa "${OSA_T}" osascript -e "tell application \"Terminal\" to close window id $OLD" >/dev/null 2>&1 || true
  sleep 1
  osa "${OSA_T}" osascript -e "tell application \"Terminal\" to exists window id $OLD" 2>/dev/null | grep -q true && echo "警告: 旧窗口 $OLD 仍存在（可能弹出了终止确认框，请手动点击终止）" >&2
  echo "已关闭 $NAME 的旧窗口 (id=$OLD)"
else
  echo "旧窗口 $OLD 不存在，直接重开"
fi

# 2) 重开（tty 精确定位新窗口）
# AppleScript 写入临时文件再调用，从而能套 osa：heredoc 形式经后台执行会丢 stdin。
# 实测证明"创建窗口这条路径不必保护"的想法是错的 —— 阻塞型 osascript 下它不是快速
# 失败而是永久挂住，而本脚本正是角色坏掉时的救援工具，最不该挂死。
OSA_FILE="$(mktemp)"
cat >"$OSA_FILE" <<'OSA'
on run argv
  set runnerPath to item 1 of argv
  tell application "Terminal"
    activate
    set t to do script "bash " & quoted form of runnerPath
    set theTTY to ""
    repeat 30 times
      try
        set theTTY to tty of t
        if theTTY is not "" then exit repeat
      end try
      delay 0.1
    end repeat
    if theTTY is not "" then
      repeat with w in windows
        try
          if (tty of tab 1 of w) is theTTY then return id of w
        end try
      end repeat
    end if
    return id of front window
  end tell
end run
OSA
NEW="$(osa "${OSA_T}" osascript "$OSA_FILE" "$RUNNER" || true)"
rm -f "$OSA_FILE"
[ -n "${NEW}" ] || { echo "错误: 开窗失败或超时（osascript 无响应）——请检查 Terminal.app 自动化授权" >&2; exit 1; }
# 3) 更新记录（保留原顺序）
TMP="$(mktemp)"; sed "s/^$NAME=.*/$NAME=$NEW/" "$WINFILE" > "$TMP" && mv "$TMP" "$WINFILE"
echo "已重启 ${NAME}，新窗口 id=${NEW}（角色将重新向主控发 READY；新窗口位置可能需要手动摆放）"
