#!/bin/bash
# install.sh — 安装 agent-team-cli skill 到 ~/.claude/skills/ 并注册 SessionStart 恢复 hook
# 用法：./install.sh [--link] [--no-hook] [--yes]
#   --link     用符号链接而非复制（开发者模式：仓库改动即时生效）
#   --no-hook  不修改 ~/.claude/settings.json（不注册恢复 hook；hook 只影响上下文压缩后的自动恢复，不装也能跑）
#   --yes      跳过确认提示
# 环境变量：CLAUDE_HOME（默认 ~/.claude），主要供测试隔离
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/skills/agent-team-cli"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DEST="$CLAUDE_HOME/skills/agent-team-cli"
SETTINGS="$CLAUDE_HOME/settings.json"
HOOK_CMD="bash ~/.claude/skills/agent-team-cli/scripts/session-recover.sh"
[ "$CLAUDE_HOME" != "$HOME/.claude" ] && HOOK_CMD="bash $DEST/scripts/session-recover.sh"

LINK=0; NOHOOK=0; YES=0
for a in "$@"; do
  case "$a" in
    --link) LINK=1 ;; --no-hook) NOHOOK=1 ;; --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "未知参数: $a" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }

# ---------- 前置检查 ----------
[ "$(uname -s)" = "Darwin" ] || warn "当前系统不是 macOS。本框架 v0.1 仅支持 macOS（开窗依赖 Terminal.app + AppleScript），继续安装但无法运行。"
[ -f "$SRC/SKILL.md" ] || die "找不到 $SRC/SKILL.md，请在仓库根目录运行本脚本"
if ! command -v claude >/dev/null 2>&1; then
  warn "PATH 中未找到 claude 命令。请先安装 Claude Code（https://code.claude.com）并确认版本 ≥ 2.1.224。"
fi
if [ "$NOHOOK" = 0 ] && ! command -v python3 >/dev/null 2>&1; then
  warn "未找到 python3（用于安全合并 settings.json）。macOS 可执行: xcode-select --install"
  warn "本次将跳过 hook 注册。你也可以稍后手动把下面这段加入 $SETTINGS 的 hooks.SessionStart 数组："
  cat <<EOF
  {"matcher": "startup|resume|compact", "hooks": [{"type": "command", "command": "$HOOK_CMD", "timeout": 10}]}
EOF
  NOHOOK=1
fi

# ---------- 告知与确认 ----------
say "将执行："
if [ "$LINK" = 1 ]; then say "  1) 符号链接 $DEST -> $SRC"; else say "  1) 复制 $SRC -> $DEST"; fi
if [ "$NOHOOK" = 0 ]; then
  say "  2) 修改 ${SETTINGS}：在 hooks.SessionStart 追加一条恢复 hook（先备份，幂等）"
  say "     command: $HOOK_CMD"
else
  say "  2) （跳过 hook 注册）"
fi
if [ "$YES" = 0 ]; then
  printf '继续？[y/N] '; read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) say "已取消"; exit 0 ;; esac
fi

# ---------- 安装 skill ----------
mkdir -p "$CLAUDE_HOME/skills"
if [ -L "$DEST" ] || [ -e "$DEST" ]; then
  if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
    say "已存在指向本仓库的符号链接，保持不变"
  else
    # 备份放到 skills/ 之外，避免备份目录被 Claude Code 当作同名 skill 加载
    BK="$CLAUDE_HOME/agent-team-cli.backup"
    rm -rf "$BK"; mkdir -p "$(dirname "$BK")"
    mv "$DEST" "$BK"
    say "已将原有 $DEST 备份为 ${BK}（只保留最近一份）"
  fi
  # 清理旧版本遗留在 skills/ 内的备份（会被误加载为 skill）
  rm -rf "$DEST.bak" "$DEST".bak-* 2>/dev/null || true
fi
if [ ! -e "$DEST" ]; then
  if [ "$LINK" = 1 ]; then ln -s "$SRC" "$DEST"; else cp -R "$SRC" "$DEST"; fi
fi
chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true
say "skill 已安装: $DEST"

# ---------- 注册 hook（python3 合并，备份，幂等） ----------
if [ "$NOHOOK" = 0 ]; then
  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  HOOK_CMD="$HOOK_CMD" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys, shutil, time
p = os.environ["SETTINGS"]; cmd = os.environ["HOOK_CMD"]
try:
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
except json.JSONDecodeError as e:
    print(f"错误: {p} 不是合法 JSON（{e}），未修改。请手动修复后重跑或使用 --no-hook", file=sys.stderr); sys.exit(1)
if not isinstance(d, dict): d = {}
hooks = d.get("hooks")
if not isinstance(hooks, dict): hooks = {}; d["hooks"] = hooks
ss = hooks.get("SessionStart")
if not isinstance(ss, list): ss = []; hooks["SessionStart"] = ss
exists = any(isinstance(h, dict) and h.get("command") == cmd
             for e in ss if isinstance(e, dict) for h in (e.get("hooks") or []))
if exists:
    print("hook 已存在，跳过（幂等，settings.json 未改动）")
else:
    bk = f"{p}.bak-{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copyfile(p, bk)
    ss.append({"matcher": "startup|resume|compact",
               "hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
    with open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2); f.write("\n")
    print(f"hook 已注册（原文件已备份为 {bk}）")
PY
fi

say ""
say "安装完成。下一步："
say "  1) 新开一个 Claude Code 会话（hook 对新会话生效）"
say "  2) 运行自检: bash $DEST/scripts/doctor.sh"
say "  3) 在你的项目目录: claude --name main  →  /agent-team-cli <任务描述>"
