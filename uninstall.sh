#!/bin/bash
# uninstall.sh — 移除 agent-team-cli skill 与其注册的 SessionStart hook（只删自己那一条）
# 用法：./uninstall.sh [--yes]
# 环境变量：CLAUDE_HOME（默认 ~/.claude）
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DEST="$CLAUDE_HOME/skills/agent-team-cli"
SETTINGS="$CLAUDE_HOME/settings.json"
YES=0
for a in "$@"; do case "$a" in --yes|-y) YES=1 ;; -h|--help) sed -n '2,4p' "$0"; exit 0 ;; *) echo "未知参数: $a" >&2; exit 1 ;; esac; done

say() { printf '%s\n' "$*"; }
say "将执行："
say "  1) 删除 $DEST（符号链接只删链接，不动仓库）"
say "  2) 从 $SETTINGS 的 hooks.SessionStart 中移除 command 含 agent-team-cli/scripts/session-recover.sh 的条目（先备份）"
say "  注意：不会删除各项目内的 runs/、.claude/agent-team-cli/、.claude/settings.local.json"
if [ "$YES" = 0 ]; then printf '继续？[y/N] '; read -r ans; case "$ans" in y|Y|yes|YES) ;; *) say "已取消"; exit 0 ;; esac; fi

if [ -L "$DEST" ]; then rm "$DEST"; say "已删除符号链接 $DEST"
elif [ -d "$DEST" ]; then rm -rf "$DEST"; say "已删除目录 $DEST"
else say "未发现 $DEST，跳过"; fi

if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
  SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys
p = os.environ["SETTINGS"]
try:
    d = json.load(open(p, encoding="utf-8"))
except json.JSONDecodeError as e:
    print(f"错误: {p} 不是合法 JSON（{e}），未修改", file=sys.stderr); sys.exit(1)
ss = d.get("hooks", {}).get("SessionStart", [])
before = len(ss)
kept = []
for e in ss:
    hs = [h for h in e.get("hooks", []) if "agent-team-cli/scripts/session-recover.sh" not in str(h.get("command", ""))]
    if hs:
        e = dict(e); e["hooks"] = hs; kept.append(e)
if kept != ss:
    d["hooks"]["SessionStart"] = kept
    if not kept: del d["hooks"]["SessionStart"]
    if not d["hooks"]: del d["hooks"]
    json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
    print("hook 已移除")
else:
    print("未发现本工具注册的 hook，settings.json 未改动")
PY
elif [ -f "$SETTINGS" ]; then
  say "未找到 python3，无法自动移除 hook；请手动编辑 $SETTINGS 删除 command 含 agent-team-cli/scripts/session-recover.sh 的 SessionStart 条目"
fi
say "卸载完成。"
