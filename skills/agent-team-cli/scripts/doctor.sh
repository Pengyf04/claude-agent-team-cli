#!/bin/bash
# doctor.sh — agent-team-cli 环境自检（只读，不改任何东西）
# 用法：bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh [项目目录]
set -u
PROJ="${1:-$PWD}"
[ $# -eq 0 ] && echo "提示: 未传项目目录参数，项目相关检查针对当前目录 $PWD（建议: doctor.sh <你的项目目录>）"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
MIN_VER="2.1.224"
ok()   { printf '  ✅ %s\n' "$*"; }
bad()  { printf '  ❌ %s\n' "$*"; FAIL=1; }
warn() { printf '  ⚠️  %s\n' "$*"; }
FAIL=0

echo "== 系统 =="
if [ "$(uname -s)" = "Darwin" ]; then ok "macOS $(sw_vers -productVersion 2>/dev/null)"; else bad "非 macOS（v0.1 仅支持 macOS：开窗依赖 Terminal.app + AppleScript）"; fi
if osascript -e 'application "Terminal" is running' 2>/dev/null | grep -q true; then
  if osascript -e 'tell application "Terminal" to get name' >/dev/null 2>&1; then ok "可通过 AppleScript 控制 Terminal.app（自动化授权已通过）"; else warn "无法控制 Terminal.app：若已拒绝授权，到 系统设置→隐私与安全性→自动化 开启"; fi
else warn "Terminal.app 未运行，跳过自动化授权预检；首次开窗时 macOS 会弹「<运行主控的应用> 想要控制 Terminal」授权，请允许"; fi
command -v python3 >/dev/null 2>&1 && ok "python3 存在（install/uninstall 合并 settings 用）" || warn "未找到 python3（仅影响 install/uninstall 的 hook 自动合并；运行本身不需要）"

echo "== Claude Code =="
if command -v claude >/dev/null 2>&1; then
  V="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$V" ]; then
    if [ "$(printf '%s\n%s\n' "$MIN_VER" "$V" | sort -V | head -1)" = "$MIN_VER" ]; then ok "claude $V（≥ $MIN_VER，支持跨会话消息）"; else bad "claude $V 低于 $MIN_VER，请升级（跨会话消息不可用）"; fi
  else warn "无法解析 claude 版本号"; fi
else bad "PATH 中找不到 claude 命令"; fi
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
warn "请确认你的账号能使用上述模型；无 Fable/Opus 权限时可 export ATC_MODEL_DEFAULT=sonnet（会作用于全部角色，含 executor）"

echo "== 项目目录: $PROJ =="
if git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then ok "是 git 仓库（bypassPermissions 的回滚兜底）"; else warn "不是 git 仓库——skill 会在 P1 自动 git init；建议自行先 init 并提交"; fi
if [ -f "$PROJ/.claude/settings.local.json" ] && grep -q '"crossSessionInbound"[[:space:]]*:[[:space:]]*"accept"' "$PROJ/.claude/settings.local.json"; then ok "项目已配置 crossSessionInbound=accept"; else warn "项目尚未配置 crossSessionInbound=accept：建议启动主控前运行 bash $S/scripts/ensure-inbound.sh $PROJ，或以 claude --name main --settings '{\"crossSessionInbound\":\"accept\"}' 启动主控（否则 skill 在 P1 写入后需重启主控一次）"; fi
if [ -f "$PROJ/.claude/agent-team-cli/windows.txt" ]; then warn "存在上次团队记录 .claude/agent-team-cli/windows.txt（若窗口已关，脚本会自动清理；仍开着则需先关闭）"; fi

echo
if [ "$FAIL" = 0 ]; then echo "结论: 未发现阻断问题（⚠️ 项请按提示确认）"; else echo "结论: 存在 ❌ 阻断问题，请先修复"; exit 1; fi
