#!/bin/bash
# doctor.sh — agent-team-cli 环境自检（只读，不改任何东西）
# 用法：bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh [项目目录]
set -u
PROJ="${1:-$PWD}"
[ $# -eq 0 ] && echo "提示: 未传项目目录参数，项目相关检查针对当前目录 ${PWD}（建议: doctor.sh <你的项目目录>）"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
MIN_VER="2.1.224"
ok()   { printf '  ✅ %s\n' "$*"; }
bad()  { printf '  ❌ %s\n' "$*"; FAIL=1; }
warn() { printf '  ⚠️  %s\n' "$*"; }
FAIL=0

# 带超时的 osascript：无窗口服务器/授权未决的环境下 osascript 会无限阻塞而非报错，
# 自检工具尤其不能卡住。超时按失败处理。用法：osa <秒> osascript ...
osa() {
  local secs="$1"; shift
  local out pid watcher rc
  out="$(mktemp)"
  "$@" >"$out" 2>&1 &
  pid=$!
  # 下面的 >/dev/null 是承重的，别当冗余删掉：kill -9 杀不掉子 shell 底下正在跑的 sleep，
  # 它会成为孤儿并继承 stdout；若 stdout 是管道（CI runner 用管道捕获输出），读端就永远
  # 等不到 EOF，命令明明结束了调用方却一直挂着。
  { sleep "$secs"; kill -9 "$pid" 2>/dev/null; } >/dev/null 2>&1 &
  watcher=$!
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  kill -9 "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  cat "$out"; rm -f "$out"
  return "$rc"
}
OSA_T="${ATC_OSA_TIMEOUT:-8}"

echo "== 系统 =="
if [ "$(uname -s)" = "Darwin" ]; then ok "macOS $(sw_vers -productVersion 2>/dev/null)"; else bad "非 macOS（v0.1 仅支持 macOS：开窗依赖 Terminal.app + AppleScript）"; fi
if osa "$OSA_T" osascript -e 'application "Terminal" is running' 2>/dev/null | grep -q true; then
  if osa "$OSA_T" osascript -e 'tell application "Terminal" to get name' >/dev/null 2>&1; then ok "可通过 AppleScript 控制 Terminal.app（自动化授权已通过）"; else warn "无法控制 Terminal.app或调用超时：若已拒绝授权，到 系统设置→隐私与安全性→自动化 开启；无图形界面的环境（CI/SSH）超时属正常"; fi
else warn "Terminal.app 未运行或 osascript 超时，跳过自动化授权预检；首次开窗时 macOS 会弹「<运行主控的应用> 想要控制 Terminal」授权，请允许"; fi
command -v python3 >/dev/null 2>&1 && ok "python3 存在（install/uninstall 合并 settings 用）" || warn "未找到 python3（仅影响 install/uninstall 的 hook 自动合并；运行本身不需要）"

echo "== Claude Code =="
if command -v claude >/dev/null 2>&1; then
  V="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$V" ]; then
    if [ "$(printf '%s\n%s\n' "$MIN_VER" "$V" | sort -V | head -1)" = "$MIN_VER" ]; then ok "claude ${V}（≥ ${MIN_VER}，支持跨会话消息）"; else bad "claude $V 低于 ${MIN_VER}，请升级（跨会话消息不可用）"; fi
  else warn "无法解析 claude 版本号"; fi
else bad "PATH 中找不到 claude 命令"; fi
# 2026-08-21 实测：CLI 凭据与桌面客户端各自独立。客户端能用不代表 CLI 能用；
# 凭据失效时角色窗口会停在 "Login expired"，启动指令根本不执行、也不发 READY，
# 主控只会看到"READY 收不齐"，极易误判成消息通路问题。
if command -v claude >/dev/null 2>&1; then
  AUTH="$(claude auth status 2>/dev/null | tr -d ' \n')"
  case "${AUTH}" in
    *'"loggedIn":true'*) ok "CLI 已登录（角色会话能正常启动）" ;;
    *'"loggedIn":false'*) bad "CLI 未登录——角色窗口会停在 Login expired、不发 READY。请在任一终端运行 claude 后执行 /login" ;;
    *) warn "无法解析 claude auth status，请自行确认 CLI 登录状态" ;;
  esac
fi

for v in CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DO_NOT_TRACK DISABLE_GROWTHBOOK; do
  [ -n "${!v:-}" ] && warn "环境变量 $v 已设置——可能关闭跨会话消息所依赖的功能开关（见官方文档 Availability 一节）"
done
warn "请在任一会话内输入 /list-agents 确认跨会话消息可用（识别该命令即可用；Bedrock/Vertex/Foundry 上不可用）"

echo "== skill 安装 =="
S="$CLAUDE_HOME/skills/agent-team-cli"
if [ -f "$S/SKILL.md" ]; then ok "SKILL 已安装: $S$( [ -L "$S" ] && echo "（符号链接 → $(readlink "$S")）")"; else bad "未找到 $S/SKILL.md，请运行 ./install.sh"; fi
for f in launch-team.sh shutdown-team.sh session-recover.sh; do [ -x "$S/scripts/$f" ] && ok "scripts/$f 可执行" || bad "scripts/$f 缺失或不可执行"; done
if [ -f "$CLAUDE_HOME/settings.json" ] && grep -q "agent-team-cli/scripts/session-recover.sh" "$CLAUDE_HOME/settings.json" 2>/dev/null; then ok "SessionStart 恢复 hook 已注册"; else warn "未注册恢复 hook（可选：影响上下文压缩后的自动恢复；./install.sh 可注册）"; fi

echo "== 模型/参数（当前 shell 环境）=="
MD="${ATC_MODEL_DEFAULT:-}"; ED="${ATC_EFFORT_DEFAULT:-}"
echo "  planner: model=${ATC_MODEL_PLANNER:-${MD:-claude-fable-5}} effort=${ATC_EFFORT_PLANNER:-${ED:-xhigh}}"
echo "  plan-reviewer: model=${ATC_MODEL_PLAN_REVIEWER:-${MD:-claude-fable-5}} effort=${ATC_EFFORT_PLAN_REVIEWER:-${ED:-xhigh}}"
echo "  executor: model=${ATC_MODEL_EXECUTOR:-${MD:-claude-opus-5}} effort=${ATC_EFFORT_EXECUTOR:-${ED:-high}}"
echo "  verifier: model=${ATC_MODEL_VERIFIER:-${MD:-claude-fable-5}} effort=${ATC_EFFORT_VERIFIER:-${ED:-xhigh}}"
echo "  权限模式: ${ATC_PERMISSION_MODE:-bypassPermissions}"
echo "  osascript 超时: ${ATC_OSA_TIMEOUT:-8} 秒（无图形界面环境下防止无限阻塞）"
warn "请确认你的账号能使用上述模型；无 Fable/Opus 权限时可 export ATC_MODEL_DEFAULT=sonnet（会作用于全部角色，含 executor）"

echo "== 项目目录: $PROJ =="
if git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then ok "是 git 仓库（bypassPermissions 的回滚兜底）"; else warn "不是 git 仓库——skill 会在 P1 自动 git init；建议自行先 init 并提交"; fi
# ---------- 主控自身：inbound 通路与注册名 ----------
# 这两项任一不满足 → 角色的 READY 会被静默扣住或寻址失败，团队卡死；
# 桌面版没有批准框，失败时屏幕上毫无线索，所以必须在启动前查出来。
# 沿进程树向上找自己所属的 claude 会话：直接用 $PPID 只在"脚本由会话直接调用"时成立，
# 中间隔一层 shell 就会落空（2026-08-21 实测）。最多上溯 6 层。
find_self_session() {
  local pid="${PPID}" i=0 f
  while [ "$i" -lt 6 ] && [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
    f="${CLAUDE_HOME}/sessions/${pid}.json"
    if [ -f "$f" ]; then printf '%s' "$f"; return 0; fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    i=$((i+1))
  done
  return 1
}
SELF="$(find_self_session || true)"
if [ -f "${SELF}" ]; then
  SELF_NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SELF}" | head -1)"
  SELF_ENTRY="$(sed -n 's/.*"entrypoint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SELF}" | head -1)"
  SELF_SRC="$(sed -n 's/.*"nameSource"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SELF}" | head -1)"
  ok "主控会话: name=${SELF_NAME} entrypoint=${SELF_ENTRY}"
  case "$(printf '%s' "${SELF_NAME}" | tr 'A-Z' 'a-z')" in
    main) bad "主控名是保留字 main——角色无法按名字回报，团队必然卡死；请改名（launch-team.sh 也会拒绝）" ;;
  esac
  if [ "${SELF_ENTRY}" = "claude-desktop" ]; then
    if grep -q '"crossSessionInbound"[[:space:]]*:[[:space:]]*"accept"' "${CLAUDE_HOME}/settings.json" 2>/dev/null; then
      ok "用户级 crossSessionInbound=accept 已配置（桌面版主控靠它收角色消息）"
    else
      bad "桌面版主控缺少用户级 accept：在 ${CLAUDE_HOME}/settings.json 顶层加 \"crossSessionInbound\": \"accept\" 并重启客户端。否则角色 READY 会被静默扣住（桌面版不显示批准框）"
    fi
    if [ "${SELF_SRC}" = "derived" ]; then
      warn "主控注册名是派生值（会话进程重建后会变）。建议用斜杠命令 /rename <稳定名> 固定——注意选带 Custom command 标注的那个，弹窗式 Rename this session 只改对话标题、不改注册名"
    else
      ok "主控注册名为用户指定，跨会话寻址稳定"
    fi
  else
    warn "终端主控：请确认启动时带了 --settings '{\"crossSessionInbound\":\"accept\"}'（显式值优先，与权限模式无关）。项目级 settings.local.json 写该键是空操作"
  fi
else
  warn "无法读取自身会话信息（${SELF} 不存在）——若你不是主控会话可忽略"
fi
if [ -f "$PROJ/.claude/agent-team-cli/windows.txt" ]; then warn "存在上次团队记录 .claude/agent-team-cli/windows.txt（若窗口已关，脚本会自动清理；仍开着则需先关闭）"; fi
[ -s "$PROJ/.claude/agent-team-cli/token" ] && echo "  ℹ️  当前团队令牌: $(cat "$PROJ/.claude/agent-team-cli/token")（主控派活消息须携带）"

echo
if [ "$FAIL" = 0 ]; then echo "结论: 未发现阻断问题（⚠️ 项请按提示确认）"; else echo "结论: 存在 ❌ 阻断问题，请先修复"; exit 1; fi
