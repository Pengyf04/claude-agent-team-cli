#!/bin/bash
# prepare-project.sh <项目目录>
# 把本框架的运行时产物加入 <项目>/.git/info/exclude，避免它们污染用户仓库的 git 状态。
# 幂等；不是 git 仓库时静默跳过。输出 OK。
#
# 历史：本脚本原名 ensure-inbound.sh，还会把 {"crossSessionInbound":"accept"} 写进项目级
# .claude/settings.local.json。该写入被证实为**结构性空操作**——Claude Code 解析该键时，
# 项目级来源（localSettings / projectSettings）只在取值比当前更严格时才被采纳，
# 而 accept 是最宽松的一档（accept=0 < hold=1 < refuse=2），永远无法满足"更严格"，
# 因此项目级 accept 在任何配置组合下都不会生效。
# 主控要能收到 bypass 角色的消息，须在启动时带 --settings（属 flagSettings，取到即用）：
#   claude --name <主控名> --settings '{"crossSessionInbound":"accept"}'
# 角色 runner 一直就是这么做的，所以角色侧从未受影响。
set -euo pipefail
PROJ="$(cd "${1:?用法: prepare-project.sh <项目目录>}" && pwd)"

if [ -d "$PROJ/.git" ]; then
  mkdir -p "$PROJ/.git/info"
  for pat in ".claude/agent-team-cli/" ".claude/settings.local.json"; do
    grep -qxF "$pat" "$PROJ/.git/info/exclude" 2>/dev/null || echo "$pat" >> "$PROJ/.git/info/exclude"
  done
fi
echo "OK"
