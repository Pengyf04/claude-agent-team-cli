#!/bin/bash
# shutdown-team.sh <项目目录> [--abandon <slug>]
# 关闭 launch-team.sh 记录的角色窗口：先结束窗口内进程（轮询确认退出，超时升级 kill -9），
# 再关窗口（避免 Terminal 弹"终止进程"确认框）。不动 main 窗口。清理 runner 脚本与记录文件。
# --abandon <slug>：把 runs/<slug>/state.md 的阶段标记为已放弃完成，避免恢复 hook 继续注入。
# 团队令牌随团队一同作废（删除 token 文件），下次开团队会重新生成——令牌要能区分团队世代，
# 否则一个侥幸存活的旧角色窗口仍能接受新团队的指令，正好是它要防的场景。
set -euo pipefail

# ---------- 带超时的 osascript ----------
# 无窗口服务器 / 自动化授权未决的环境下 osascript 会无限阻塞而非报错。超时按失败处理。
# 下面的 >/dev/null 是承重的：kill -9 杀不掉子 shell 底下正在跑的 sleep，那个孤儿会继承
# stdout；若 stdout 是管道，读端就永远等不到 EOF。
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

PROJ="$(cd "${1:?用法: shutdown-team.sh <项目目录> [--abandon <slug>]}" && pwd)"
ABANDON=""
if [ "${2:-}" = "--abandon" ]; then ABANDON="${3:?--abandon 需要 <slug>}"; fi
if [ -n "$ABANDON" ]; then
  ST="$PROJ/runs/$ABANDON/state.md"
  if [ -f "$ST" ]; then
    if grep -q '^阶段:' "$ST"; then sed -i '' 's/^阶段:.*/阶段: [P5] 完成（已放弃）/' "$ST"; else printf '阶段: [P5] 完成（已放弃）\n' >> "$ST"; fi
    echo "已将 $ST 标记为已放弃，恢复 hook 不再注入"
  else
    echo "警告: 未找到 $ST" >&2
  fi
fi
RUNTIME_DIR="$PROJ/.claude/agent-team-cli"
WINFILE="$RUNTIME_DIR/windows.txt"
[ -f "$WINFILE" ] || { echo "提示: 找不到 ${WINFILE}（团队未启动或窗口已手动关闭并清理）"; exit 0; }

while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  role="${pair%%=*}"; wid="${pair##*=}"
  [ "$role" = "main" ] && continue
  case "$wid" in ''|0|*[!0-9]*) echo "跳过 ${role}（无有效窗口 ID: '$wid'）"; continue ;; esac

  TTY="$(osa "${OSA_T}" osascript -e "tell application \"Terminal\" to get tty of tab 1 of window id $wid" 2>/dev/null || true)"
  if [ -n "$TTY" ]; then
    TSHORT="${TTY#/dev/}"
    pkill -t "$TSHORT" 2>/dev/null || true
    # claude 优雅退出通常需要 3–10 秒：轮询最多 15 秒等进程退出，仍在则 kill -9 再等 2 秒
    for _ in $(seq 1 15); do
      pgrep -t "$TSHORT" >/dev/null 2>&1 || break
      sleep 1
    done
    if pgrep -t "$TSHORT" >/dev/null 2>&1; then
      pkill -9 -t "$TSHORT" 2>/dev/null || true
      sleep 2
    fi
  fi
  if osa "${OSA_T}" osascript -e "tell application \"Terminal\" to close window id $wid" >/dev/null 2>&1; then
    echo "已关闭 $role 窗口 (id=$wid)"
  else
    echo "警告: 关闭 $role 窗口失败或已关闭 (id=$wid)——若窗口仍在请手动关闭" >&2
  fi
done < "$WINFILE"

rm -f "${WINFILE}" "${RUNTIME_DIR}"/run-*.sh "${RUNTIME_DIR}/token"
echo "团队窗口清理完成（团队令牌已作废，下次开团队会重新生成）。"
# 关团队只改变了"团队是否活着"，没改变"任务是否进行中"。两者不一致会留下孤儿状态：
# state.md 说进行中、团队却已不存在，恢复 hook 会照着一个不成立的世界继续注入。
# 这里只提醒不自动放弃——shutdown 也可能是任务中途重启角色，自动放弃会误伤。
if [ -z "${ABANDON}" ]; then
  shopt -s nullglob
  for st in "${PROJ}"/runs/*/state.md; do
    head -20 "$st" 2>/dev/null | grep -Eq '^阶段:.*P5.*(完成|done|放弃)' && continue
    slug="$(basename "$(dirname "$st")")"
    echo ""
    echo "注意: runs/${slug}/state.md 仍标记为进行中，但团队已关闭。"
    echo "      恢复 hook 会继续把它注入新会话（含可能已作废的主控名）。"
    echo "      任务确实要放弃请执行：shutdown-team.sh \"${PROJ}\" --abandon ${slug}"
    echo "      若只是中途重启角色、任务还要继续，则无需处理。"
  done
fi
echo "提示: 团队窗口与运行时产物已清理。"
