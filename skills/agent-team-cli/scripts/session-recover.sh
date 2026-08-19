#!/bin/bash
# session-recover.sh — SessionStart hook（startup / resume / compact 时触发）
# 作用：若当前项目目录存在 agent-team-cli 的进行中任务（runs/*/state.md），把 state.md 内容与恢复指引
#       注入会话上下文，使主控在上下文压缩/重启后能确定性地恢复状态机；角色会话则被提示按各自协议继续待命。
# 保护：无 state.md、或全部已完成 → 静默退出（对其他项目零干扰）。
set -u

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
SKILL_MARK="agent-team-cli/SKILL.md"

# 读取 hook 输入（stdin JSON），提取触发来源，仅用于提示文案；纯 sed 解析，失败不影响主流程
SOURCE="$(cat 2>/dev/null | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"

shopt -s nullglob
FOUND=()
for f in "$PROJ"/runs/*/state.md; do
  head -10 "$f" 2>/dev/null | grep -q "$SKILL_MARK" || continue
  head -20 "$f" 2>/dev/null | grep -Eq '^阶段:.*P5.*(完成|done|放弃)' && continue
  FOUND+=("$f")
done
[ ${#FOUND[@]} -eq 0 ] && exit 0

case "$SOURCE" in
  compact) WHY="上下文刚被压缩" ;;
  resume)  WHY="会话刚被恢复(resume)" ;;
  startup) WHY="会话刚启动，且本项目存在未完成的团队任务" ;;
  *)       WHY="会话状态变更" ;;
esac

cat <<EOF
<agent-team-cli-recovery>
【agent-team-cli 状态恢复注入 · 触发原因：${WHY}】
本项目存在进行中的 Agent Team 任务。请先判断自己的身份：
- 若你是**主控(main)**：立即重读 ~/.claude/skills/agent-team-cli/SKILL.md，然后严格以下方 state.md 为准恢复状态机（阶段/轮次/正在等待谁/下一步），不要重复已完成的步骤，不要替用户通过任何人工卡点。若"正在等待"是某个角色且你不确定其是否已回报，先 ListAgents 确认在线，再向用户播报当前状态。
- 若你是**角色会话**（planner / plan-reviewer / executor / verifier）：忽略状态机细节，仅按你 system prompt 中的角色通信协议行事——有未完成的当前任务就继续并回报主控，否则保持待命。
EOF
# 团队活体校验：state.md 说"进行中"，不等于团队还活着。关团队时若没传 --abandon，
# 就会留下孤儿状态——照着一个不成立的世界恢复，还可能带着已作废的主控名。
# 纪律：只读文件与会话注册表，绝不调 osascript（本 hook 在任意项目启动时都会跑，
# 无图形界面环境下 osascript 会阻塞，那将拖垮每一次会话启动）。
SESS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
for f in "${FOUND[@]}"; do
  echo "--- ${f} ---"
  cat "$f"
  slug="$(basename "$(dirname "$f")")"
  alive=""
  if [ -d "$SESS_DIR" ]; then
    for sf in "$SESS_DIR"/*.json; do
      nm="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$sf" 2>/dev/null | head -1)"
      case "$nm" in
        planner-"$slug"|plan-reviewer-"$slug"|executor-"$slug"|verifier-"$slug") alive="${alive} ${nm}" ;;
      esac
    done
  fi
  echo "--- 团队活体校验（${slug}）---"
  if [ -f "${PROJ}/.claude/agent-team-cli/windows.txt" ]; then
    echo "窗口记录: 存在"
  else
    echo "窗口记录: 不存在（团队已关闭，或本次任务尚未开窗）"
  fi
  if [ -n "$alive" ]; then
    echo "在册角色会话:${alive}"
  else
    echo "在册角色会话: 无"
    echo "⚠️ 状态记录说任务进行中，但没有任何角色会话在册 —— 不要假设角色在线、不要直接续跑。"
    echo "   请先向用户播报现状，并让用户在「重开团队继续」与「放弃该任务」之间选择；"
    echo "   放弃请用: shutdown-team.sh \"${PROJ}\" --abandon ${slug}"
  fi
  echo "⚠️ 另注意上面 state.md 记录的「main会话名」：若与你当前会话名不符，说明主控已换名或重启，"
  echo "   角色按旧名字寻址会失败，需按新名字重开团队（主控名不能是保留字 main）。"
done
echo "</agent-team-cli-recovery>"
exit 0
