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
LEFT=""
[ -f "$WINFILE" ] || { echo "提示: 找不到 ${WINFILE}（团队未启动或窗口已手动关闭并清理）"; exit 0; }

while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  role="${pair%%=*}"; wid="${pair##*=}"
  [ "$role" = "main" ] && continue
  case "$wid" in ''|0|*[!0-9]*) echo "跳过 ${role}（无有效窗口 ID: '$wid'）"; continue ;; esac

  # ---- 1) 结束窗口内进程 ----
  # 2026-08-21 终端版回归实测：`pgrep -t` / `pkill -t` 在 macOS 上匹配不到目标进程
  # （同一 tty，`ps -t ttys001` 能列出 claude，`pgrep -t ttys001` 返回空），导致
  # "没杀 → 不等 → -9 升级从不触发" 三连空转，脚本却以为自己动过手。
  # 现在一律先取 pid 再按 pid 操作：pid 是唯一可靠的抓手。
  PIDS=""
  TTY="$(osa "${OSA_T}" osascript -e "tell application \"Terminal\" to get tty of tab 1 of window id $wid" 2>/dev/null || true)"
  # osa 会把 osascript 的报错文本也一并返回（窗口已不存在时尤其明显），
  # 因此必须校验形态，只接受真正的 tty，否则当作取不到、走兜底。
  case "${TTY}" in
    /dev/tty*|tty*) ;;
    *) TTY="" ;;
  esac
  if [ -n "${TTY}" ]; then
    # ps -t 可靠；从中挑出本角色的 claude 进程（避免误杀同 tty 的 shell / MCP 子进程）
    PIDS="$(ps -t "${TTY#/dev/}" -o pid=,command= 2>/dev/null | grep -F -- "--name ${role} " | awk '{print $1}' || true)"
  fi
  if [ -z "${PIDS}" ]; then
    # 兜底：按会话名精确匹配（名字由 launch-team.sh 生成，全机唯一）
    PIDS="$(pgrep -f -- "claude --name ${role} " 2>/dev/null || true)"
  fi

  if [ -n "${PIDS}" ]; then
    # shellcheck disable=SC2086  # PIDS 为空白分隔的纯数字列表，需按多参数展开
    kill -TERM ${PIDS} 2>/dev/null || true
    # claude 优雅退出通常 3–10 秒；给足 20 秒，仍在则 KILL
    for _ in $(seq 1 20); do
      STILL_P=""
      for pp in ${PIDS}; do kill -0 "$pp" 2>/dev/null && STILL_P="${STILL_P} $pp"; done
      [ -z "${STILL_P}" ] && break
      sleep 1
    done
    STILL_P=""
    for pp in ${PIDS}; do kill -0 "$pp" 2>/dev/null && STILL_P="${STILL_P} $pp"; done
    if [ -n "${STILL_P}" ]; then
      echo "提示: ${role} 未在 20 秒内优雅退出，升级为强制结束:${STILL_P}" >&2
      # shellcheck disable=SC2086
      kill -9 ${STILL_P} 2>/dev/null || true
      sleep 2
    fi
  else
    echo "提示: 未找到 ${role} 的 claude 进程（可能已自行退出）" >&2
  fi
  if pgrep -f -- "claude --name ${role} " >/dev/null 2>&1; then
    echo "警告: ${role} 的 claude 进程仍在运行，未能结束——请手动处理" >&2
  fi

  # ---- 2) 关窗，然后回查是否真的关了（AppleScript 的返回值不可信：弹了确认框也会"成功"）----
  osa "${OSA_T}" osascript -e "tell application \"Terminal\" to close window id $wid" >/dev/null 2>&1 || true
  sleep 1
  STILL="$(osa "${OSA_T}" osascript -e "tell application \"Terminal\" to exists window id $wid" 2>/dev/null || echo unknown)"
  case "$STILL" in
    false) echo "已关闭 $role 窗口 (id=$wid)" ;;
    true)  echo "警告: $role 窗口 (id=$wid) 仍然存在——可能弹出了终止确认框，请手动点击终止或关闭" >&2; LEFT="${LEFT} ${role}" ;;
    *)     echo "警告: 无法确认 $role 窗口 (id=$wid) 是否已关闭（osascript 无响应），请目视检查" >&2; LEFT="${LEFT} ${role}" ;;
  esac
done < "$WINFILE"

if [ -n "${LEFT}" ]; then
  echo "" >&2
  echo "注意: 以下角色窗口未能确认关闭:${LEFT}" >&2
  echo "      已清理 runner 与令牌，但保留 ${WINFILE} 以便重试；手动关窗后可再次运行本脚本完成清理。" >&2
  rm -f "${RUNTIME_DIR}"/run-*.sh "${RUNTIME_DIR}/token"
  SHUTDOWN_RC=3
else
  rm -f "${WINFILE}" "${RUNTIME_DIR}"/run-*.sh "${RUNTIME_DIR}/token"
  echo "团队窗口清理完成（团队令牌已作废，下次开团队会重新生成）。"
  SHUTDOWN_RC=0
fi
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
exit "${SHUTDOWN_RC:-0}"
