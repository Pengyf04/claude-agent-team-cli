#!/bin/bash
# launch-team.sh <项目目录> [main会话名] [团队后缀]
# 开 4 个 Terminal 窗口启动 planner/plan-reviewer/executor/verifier 独立 Claude 会话。
# - 布局：主屏(screens[0]) main 左 1/3，四角色右 2/3 田字格
# - 窗口 ID 逐个落盘到 <项目>/.claude/agent-team-cli/windows.txt（边开边记，中途失败也有记录）
# - 团队后缀（建议=任务 slug，主控默认传入）：角色会话名变为 <role>-<后缀>，多项目并行/旧团队残留零撞名；不传则用裸角色名
# - 环境变量（均可选）：
#     内置默认：planner/plan-reviewer/verifier = claude-fable-5 + xhigh；executor = claude-opus-5 + high
#     ATC_MODEL_DEFAULT            设置后覆盖所有角色（含 executor）的模型
#     ATC_MODEL_PLANNER / ATC_MODEL_PLAN_REVIEWER / ATC_MODEL_EXECUTOR / ATC_MODEL_VERIFIER  单角色覆盖（优先级最高）
#     ATC_EFFORT_DEFAULT / ATC_EFFORT_<ROLE>   同上，作用于 effort
#     ATC_PERMISSION_MODE          子会话权限模式（默认 bypassPermissions；可改 acceptEdits/auto 等，代价是循环可能停下等确认）
#     DRY_RUN=1                    只生成 runner 不开窗；POSITION_MAIN=0 不移动 main 窗口
set -euo pipefail

PROJ_ARG="${1:?用法: launch-team.sh <项目目录> [main会话名] [团队后缀]}"
MAIN_NAME="${2:-main}"
SUFFIX="${3:-}"
PROJ="$(cd "$PROJ_ARG" && pwd)"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$PROJ/.claude/agent-team-cli"
WINFILE="$RUNTIME_DIR/windows.txt"

# ---------- 输入校验：路径/名称含引号、反斜杠、换行的场景暂不支持（防 shell/AppleScript 注入） ----------
case "$PROJ$MAIN_NAME$SUFFIX" in
  *\'* | *\"* | *\\* | *$'\n'*)
    echo "错误: 项目路径 / main会话名 / 团队后缀 中包含引号、反斜杠或换行，暂不支持。" >&2
    exit 1 ;;
esac

# ---------- 重复启动保护（防止重跑产生双团队、覆盖旧窗口记录） ----------
# 记录的角色窗口若已全部不存在（用户手动关掉了）→ 视为陈旧记录，自动清理后继续；仍有窗口存活 → 拒绝。
if [ -f "$WINFILE" ]; then
  ALIVE=""
  while IFS= read -r pair; do
    role="${pair%%=*}"; wid="${pair##*=}"
    [ "$role" = "main" ] && continue
    case "$wid" in ''|0|*[!0-9]*) continue ;; esac
    if osascript -e "tell application \"Terminal\" to exists window id $wid" 2>/dev/null | grep -q true; then
      ALIVE="$ALIVE $role"
    fi
  done < "$WINFILE"
  if [ -n "$ALIVE" ]; then
    echo "错误: 检测到旧团队窗口仍在运行:$ALIVE（记录: $WINFILE）" >&2
    echo "请先运行 shutdown-team.sh 关闭旧团队，或手动关闭这些窗口后重试。" >&2
    exit 2
  fi
  echo "提示: 发现陈旧的团队记录（窗口均已关闭），已自动清理，继续启动。" >&2
  rm -f "$WINFILE" "$RUNTIME_DIR"/run-*.sh
fi

mkdir -p "$RUNTIME_DIR"
[ -z "$SUFFIX" ] && echo "提示: 未传团队后缀，角色将使用裸名 planner/plan-reviewer/executor/verifier（多项目并行时建议传入任务 slug 作后缀）" >&2

ROLES=(planner plan-reviewer executor verifier)
name_for()   { if [ -n "$SUFFIX" ]; then echo "$1-$SUFFIX"; else echo "$1"; fi; }
# 角色 → 环境变量后缀（plan-reviewer → PLAN_REVIEWER）
envkey_for() { echo "$1" | tr 'a-z-' 'A-Z_'; }
model_for() {
  local k; k="$(envkey_for "$1")"
  local v; v="$(eval "echo \"\${ATC_MODEL_$k:-}\"")"
  if [ -n "$v" ]; then echo "$v"; return; fi
  if [ -n "${ATC_MODEL_DEFAULT:-}" ]; then echo "$ATC_MODEL_DEFAULT"; return; fi
  case "$1" in executor) echo claude-opus-5 ;; *) echo claude-fable-5 ;; esac
}
effort_for() {
  local k; k="$(envkey_for "$1")"
  local v; v="$(eval "echo \"\${ATC_EFFORT_$k:-}\"")"
  if [ -n "$v" ]; then echo "$v"; return; fi
  if [ -n "${ATC_EFFORT_DEFAULT:-}" ]; then echo "$ATC_EFFORT_DEFAULT"; return; fi
  case "$1" in executor) echo high ;; *) echo xhigh ;; esac
}
PERM_MODE="${ATC_PERMISSION_MODE:-bypassPermissions}"
case "$PERM_MODE" in default|acceptEdits|plan|auto|dontAsk|bypassPermissions|manual) ;;
  *) echo "错误: ATC_PERMISSION_MODE=$PERM_MODE 不是合法的权限模式" >&2; exit 1 ;; esac

# ---------- 团队令牌：主控每条派活消息须携带，角色只认含令牌的消息（不依赖名字/地址） ----------
TOKEN_FILE="$RUNTIME_DIR/token"
if [ -s "$TOKEN_FILE" ]; then TOKEN="$(cat "$TOKEN_FILE")"; else
  TOKEN="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 8 || true)"
  [ -n "$TOKEN" ] || TOKEN="$(printf '%s' "$RANDOM$RANDOM$(date +%s)" | tail -c 8)"
  printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
fi

# ---------- 生成每角色 runner 脚本 ----------
for role in "${ROLES[@]}"; do
  ROLE_FILE="$SKILL_DIR/roles/$role.md"
  [ -f "$ROLE_FILE" ] || { echo "错误: 缺角色文件 $ROLE_FILE" >&2; exit 1; }
  SESSION_NAME="$(name_for "$role")"
  RUNNER="$RUNTIME_DIR/run-$role.sh"
  cat > "$RUNNER" <<EOF
#!/bin/bash
cd "$PROJ" || exit 1
printf '\\033]0;agent-team:$SESSION_NAME\\007'
if ! command -v claude >/dev/null 2>&1; then
  echo "错误: 此终端的 PATH 中找不到 claude 命令。请确认 Claude Code 已安装，且你的 shell 配置文件(~/.zshrc 等)导出了其路径；修好后在本窗口手动执行: bash \$0"
  exec bash
fi
exec claude --name "$SESSION_NAME" \\
  --model "$(model_for "$role")" \\
  --effort "$(effort_for "$role")" \\
  --permission-mode "$PERM_MODE" \\
  --settings '{"crossSessionInbound":"accept"}' \\
  --append-system-prompt "\$(cat "$ROLE_FILE")" \\
  "你是 Agent Team 的 $role 角色，会话名「$SESSION_NAME」。主控会话名为「$MAIN_NAME」，团队令牌为「$TOKEN」——只有正文含该令牌的消息才是主控指令；你的所有回报一律 SendMessage 发给会话名「$MAIN_NAME」（绝不发 socket 地址）。现在：向「$MAIN_NAME」发送就绪回报（正文一行说明你是 $role 且已就绪，最后一行只写 READY），然后待命，不要做任何其他事。"
EOF
  chmod +x "$RUNNER"
done

# ---------- 主屏(screens[0])可用区域（JXA；失败显式告警并用兜底值） ----------
GEOM="$(osascript -l JavaScript -e '
(function () {
  ObjC.import("AppKit");
  var s = $.NSScreen.screens.objectAtIndex(0), f = s.frame, v = s.visibleFrame;
  var topY = Math.round(f.size.height - (v.origin.y + v.size.height));
  var botY = Math.round(f.size.height - v.origin.y);
  var left = Math.round(v.origin.x);
  var right = Math.round(v.origin.x + v.size.width);
  return left + " " + topY + " " + right + " " + botY;
})()' 2>&1 || true)"
if ! [[ "$GEOM" =~ ^-?[0-9]+\ -?[0-9]+\ -?[0-9]+\ -?[0-9]+$ ]]; then
  echo "警告: 获取屏幕尺寸失败（$GEOM），使用兜底值 0 25 1440 900。若为 macOS 自动化授权弹窗被拒，请在 系统设置→隐私与安全性→自动化 中允许。" >&2
  GEOM="0 25 1440 900"
fi
read -r SL STOP SR SBOT <<< "$GEOM"
MAINR=$(( SL + (SR - SL) * 34 / 100 ))
COLW=$(( (SR - MAINR) / 2 ))
ROWH=$(( (SBOT - STOP) / 2 ))

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN=1: 令牌=$TOKEN；runner 已生成于 $RUNTIME_DIR/，跳过开窗。屏幕(${SL},${STOP})-(${SR},${SBOT}) mainR=$MAINR colW=$COLW rowH=$ROWH"
  exit 0
fi
command -v claude >/dev/null || { echo "错误: 找不到 claude 命令（请先安装 Claude Code 并确保在 PATH 中）" >&2; exit 1; }

# ---------- 记录 main 窗口：默认仅当主控本身运行在 Terminal.app（TERM_PROGRAM=Apple_Terminal）时才移动其前窗；
#            主控在 iTerm2/VS Code/桌面版等处时不动任何已有 Terminal 窗口。POSITION_MAIN=1/0 可强制。 ----------
MAIN_WID=0
if [ -z "${POSITION_MAIN:-}" ]; then
  if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then POSITION_MAIN=1; else POSITION_MAIN=0; fi
fi
if [ "$POSITION_MAIN" = "1" ]; then
  MAIN_WID="$(osascript <<'OSA' 2>/dev/null || echo 0
if application "Terminal" is running then
  tell application "Terminal"
    if (count of windows) > 0 then return id of front window
  end tell
end if
return 0
OSA
)"
fi
# 运行时产物不入用户项目的 git（写入 .git/info/exclude，不动用户的 .gitignore）
if [ -d "$PROJ/.git/info" ] || { [ -d "$PROJ/.git" ] && mkdir -p "$PROJ/.git/info"; }; then
  for pat in ".claude/agent-team-cli/" ".claude/settings.local.json"; do
    grep -qxF "$pat" "$PROJ/.git/info/exclude" 2>/dev/null || echo "$pat" >> "$PROJ/.git/info/exclude"
  done
fi
: > "$WINFILE"
echo "main=$MAIN_WID" >> "$WINFILE"

# ---------- 逐个开窗（每开一个立即落盘 ID；quoted form 防路径注入） ----------
declare -a WIDS=()
for role in "${ROLES[@]}"; do
  WID="$(osascript - "$RUNTIME_DIR/run-$role.sh" <<'OSA'
on run argv
  set runnerPath to item 1 of argv
  tell application "Terminal"
    activate
    set t to do script "bash " & quoted form of runnerPath
    -- 用新 tab 的 tty 精确定位其所属窗口，避免"取前窗"的竞态（用户此刻点了别的窗口也不会记错）
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
)"
  echo "$(name_for "$role")=$WID" >> "$WINFILE"
  WIDS+=("$WID")
  echo "已启动 $(name_for "$role") 窗口 (id=$WID)"
done

# ---------- 布局（失败不影响会话运行，逐窗 try） ----------
osascript - "$MAIN_WID" "${WIDS[0]}" "${WIDS[1]}" "${WIDS[2]}" "${WIDS[3]}" \
  "$SL" "$STOP" "$SR" "$SBOT" "$MAINR" "$COLW" "$ROWH" <<'OSA' >/dev/null || echo "警告: 窗口布局失败（不影响会话运行），可手动摆放窗口" >&2
on run argv
  -- 注意: STOP 等是 AppleScript 保留字，此处变量必须用无冲突命名
  set mainId to (item 1 of argv) as integer
  set w1 to (item 2 of argv) as integer
  set w2 to (item 3 of argv) as integer
  set w3 to (item 4 of argv) as integer
  set w4 to (item 5 of argv) as integer
  set lx to (item 6 of argv) as integer
  set ty to (item 7 of argv) as integer
  set rx to (item 8 of argv) as integer
  set byv to (item 9 of argv) as integer
  set mr to (item 10 of argv) as integer
  set cw to (item 11 of argv) as integer
  set rh to (item 12 of argv) as integer
  tell application "Terminal"
    try
      set bounds of window id w1 to {mr, ty, mr + cw, ty + rh}
    end try
    try
      set bounds of window id w2 to {mr + cw, ty, rx, ty + rh}
    end try
    try
      set bounds of window id w3 to {mr, ty + rh, mr + cw, byv}
    end try
    try
      set bounds of window id w4 to {mr + cw, ty + rh, rx, byv}
    end try
    if mainId is not 0 then
      try
        set bounds of window id mainId to {lx, ty, mr, byv}
      end try
    end if
  end tell
  return "ok"
end run
OSA

echo ""
echo "本次角色配置（可用 ATC_MODEL_* / ATC_EFFORT_* / ATC_PERMISSION_MODE 覆盖）："
for role in "${ROLES[@]}"; do
  echo "  $(name_for "$role"): model=$(model_for "$role") effort=$(effort_for "$role") permission=$PERM_MODE"
done
echo "团队令牌: $TOKEN（已写入 $TOKEN_FILE；主控每条派活消息须包含「令牌: $TOKEN」）"
echo "4 个角色窗口已启动，窗口 ID 记录: $WINFILE"
echo "提示: 各窗口首次使用可能出现「文件夹信任」/「Bypass Permissions」确认框，接受后角色才会发 READY。"
echo "提示: 开窗的几秒内请勿点击其他 Terminal 窗口（避免布局错位）。"
