#!/bin/bash
# tests/run.sh — 不依赖真实 Claude 会话与开窗的自动化测试
# 覆盖：bash 语法、SKILL frontmatter、DRY_RUN 冒烟（默认/覆盖/非法值/后缀）、陈旧记录判定、
#       hook 三场景、install/uninstall 幂等与精确移除（隔离 CLAUDE_HOME）、个人信息残留检查
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/skills/agent-team-cli"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$*"; }
ko()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$*"; }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

echo "== 1. 语法 =="
for f in "$ROOT"/install.sh "$ROOT"/uninstall.sh "$SKILL"/scripts/*.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f'"
done

echo "== 2. SKILL frontmatter / 角色文件 =="
check "SKILL.md 有 name: agent-team-cli" "grep -q '^name: agent-team-cli$' '$SKILL/SKILL.md'"
check "SKILL.md 有 description" "grep -q '^description: ' '$SKILL/SKILL.md'"
for r in planner plan-reviewer executor verifier; do
  check "roles/$r.md 存在且含通信协议" "grep -q '通信协议' '$SKILL/roles/$r.md'"
done
for r in planner plan-reviewer executor verifier; do
  check "roles/$r.md 含令牌校验/名字回报/mktemp 纪律" "grep -q '团队令牌' '$SKILL/roles/$r.md' && grep -q '绝不发往 socket 地址' '$SKILL/roles/$r.md' && grep -q 'mktemp -d' '$SKILL/roles/$r.md'"
done
check "restart-role.sh 语法" "bash -n '$SKILL/scripts/restart-role.sh'"
check "restart-role.sh 拒绝非法角色" "! bash '$SKILL/scripts/restart-role.sh' '$TMP' bogus >/dev/null 2>&1"

echo "== 3. launch-team.sh DRY_RUN =="
P="$TMP/proj"; mkdir -p "$P"
DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" main demo >/dev/null 2>&1
check "默认: planner 用 claude-fable-5/xhigh" "grep -q -- '--model \"claude-fable-5\"' '$P/.claude/agent-team-cli/run-planner.sh' && grep -q -- '--effort \"xhigh\"' '$P/.claude/agent-team-cli/run-planner.sh'"
check "默认: executor 用 claude-opus-5/high" "grep -q -- '--model \"claude-opus-5\"' '$P/.claude/agent-team-cli/run-executor.sh' && grep -q -- '--effort \"high\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "默认: 权限 bypassPermissions" "grep -q -- '--permission-mode \"bypassPermissions\"' '$P/.claude/agent-team-cli/run-verifier.sh'"
check "后缀: 会话名 executor-demo, 主控名 main" "grep -q -- '--name \"executor-demo\"' '$P/.claude/agent-team-cli/run-executor.sh' && grep -q '主控会话名为「main」' '$P/.claude/agent-team-cli/run-executor.sh'"
check "runner 含 crossSessionInbound accept 与角色 prompt 注入" "grep -q 'crossSessionInbound' '$P/.claude/agent-team-cli/run-planner.sh' && grep -q -- '--append-system-prompt' '$P/.claude/agent-team-cli/run-planner.sh'"
check "runner 含 claude 检测" "grep -q 'command -v claude' '$P/.claude/agent-team-cli/run-planner.sh'"
check "生成了团队令牌文件且注入 runner 启动指令" "[ -s '$P/.claude/agent-team-cli/token' ] && grep -q \"团队令牌为「\$(cat '$P/.claude/agent-team-cli/token')」\" '$P/.claude/agent-team-cli/run-planner.sh'"
TOK1="$(cat "$P/.claude/agent-team-cli/token")"
DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" main demo >/dev/null 2>&1
check "重复生成 runner 时令牌保持不变" "[ \"\$(cat '$P/.claude/agent-team-cli/token')\" = '$TOK1' ]"
check "runner 语法" "bash -n '$P/.claude/agent-team-cli/run-planner.sh'"
rm -rf "$P/.claude"
ATC_MODEL_DEFAULT=opus ATC_MODEL_PLAN_REVIEWER=sonnet ATC_EFFORT_EXECUTOR=medium ATC_PERMISSION_MODE=acceptEdits DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" main demo >/dev/null 2>&1
check "覆盖: ATC_MODEL_DEFAULT→planner=opus" "grep -q -- '--model \"opus\"' '$P/.claude/agent-team-cli/run-planner.sh'"
check "覆盖: ATC_MODEL_DEFAULT 也作用于 executor" "grep -q -- '--model \"opus\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "覆盖: ATC_MODEL_PLAN_REVIEWER=sonnet" "grep -q -- '--model \"sonnet\"' '$P/.claude/agent-team-cli/run-plan-reviewer.sh'"
check "覆盖: ATC_EFFORT_EXECUTOR=medium" "grep -q -- '--effort \"medium\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "覆盖: ATC_PERMISSION_MODE=acceptEdits" "grep -q -- '--permission-mode \"acceptEdits\"' '$P/.claude/agent-team-cli/run-executor.sh'"
rm -rf "$P/.claude"
check "非法权限模式被拒绝" "! ATC_PERMISSION_MODE=yolo DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' main demo >/dev/null 2>&1"
check "路径含单引号被拒绝" "! DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' \"$TMP/it's\" main demo >/dev/null 2>&1"
rm -rf "$P/.claude"; DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" main >/dev/null 2>&1
check "无后缀: 裸角色名" "grep -q -- '--name \"executor\"' '$P/.claude/agent-team-cli/run-executor.sh'"

echo "== 3b. ensure-inbound.sh =="
E="$SKILL/scripts/ensure-inbound.sh"; Q="$TMP/proj2"; mkdir -p "$Q/.claude" && git -C "$Q" init -q 2>/dev/null
printf '{"permissions":{"allow":["Bash(ls)"]}}\n' > "$Q/.claude/settings.local.json"
check "首次写入输出 NEW 且保留其他键" "[ \"\$(bash '$E' '$Q')\" = NEW ] && grep -q 'Bash(ls)' '$Q/.claude/settings.local.json' && grep -q '\"crossSessionInbound\": \"accept\"' '$Q/.claude/settings.local.json'"
check "再次运行输出 EXISTS" "[ \"\$(bash '$E' '$Q')\" = EXISTS ]"
check ".git/info/exclude 含运行时产物" "grep -qxF '.claude/agent-team-cli/' '$Q/.git/info/exclude' && grep -qxF '.claude/settings.local.json' '$Q/.git/info/exclude'"

echo "== 3c. shutdown-team.sh --abandon =="
mkdir -p "$Q/runs/demo" && printf 'skill: agent-team-cli/SKILL.md\n阶段: [2] 执行验证环\n' > "$Q/runs/demo/state.md"
bash "$SKILL/scripts/shutdown-team.sh" "$Q" --abandon demo >/dev/null 2>&1
check "--abandon 把阶段改为已放弃完成" "grep -q '^阶段: \[P5\] 完成（已放弃）' '$Q/runs/demo/state.md'"
check "无 windows.txt 时 shutdown 温和退出(0)" "bash '$SKILL/scripts/shutdown-team.sh' '$Q' >/dev/null 2>&1"

echo "== 3d. PATH 无 claude 时 DRY_RUN 仍可用（CI 场景）=="
rm -rf "$P/.claude"
check "无 claude 也能 DRY_RUN" "env -i HOME='$HOME' PATH=/usr/bin:/bin DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' main demo >/dev/null 2>&1 && [ -f '$P/.claude/agent-team-cli/run-planner.sh' ]"

echo "== 4. 陈旧记录判定 =="
rm -rf "$P/.claude"; mkdir -p "$P/.claude/agent-team-cli"
printf 'main=0\nplanner=99999991\nexecutor=99999992\n' > "$P/.claude/agent-team-cli/windows.txt"
OUT="$(DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" main demo 2>&1)"
check "窗口均不存在 → 自动清理并继续" "echo \"\$OUT\" | grep -q '陈旧' && echo \"\$OUT\" | grep -q 'DRY_RUN'"

echo "== 5. session-recover.sh 三场景 =="
H="$SKILL/scripts/session-recover.sh"
mkdir -p "$TMP/empty"; cd "$TMP/empty"
check "无任务目录 → 静默" "[ -z \"\$(echo '{\"source\":\"startup\"}' | bash '$H')\" ]"
mkdir -p "$TMP/done/runs/x" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\nmain会话名: main\n阶段: [P5] 完成\n' > "$TMP/done/runs/x/state.md"; cd "$TMP/done"
check "已完成任务 → 静默" "[ -z \"\$(echo '{\"source\":\"compact\"}' | bash '$H')\" ]"
mkdir -p "$TMP/aband/runs/z" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\n阶段: [P5] 完成（已放弃）\n' > "$TMP/aband/runs/z/state.md"; cd "$TMP/aband"
check "已放弃任务 → 静默" "[ -z \"\$(echo '{\"source\":\"compact\"}' | bash '$H')\" ]"
mkdir -p "$TMP/live/runs/y" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\nmain会话名: main\n阶段: [2] 执行验证环\n正在等待: verifier\n' > "$TMP/live/runs/y/state.md"; cd "$TMP/live"
OUT="$(echo '{"source":"compact"}' | bash "$H")"
check "进行中任务 → 注入且识别 compact" "echo \"\$OUT\" | grep -q 'agent-team-cli-recovery' && echo \"\$OUT\" | grep -q '上下文刚被压缩' && echo \"\$OUT\" | grep -q '正在等待: verifier'"
OUT2="$(bash "$H" </dev/null)"
check "无 stdin 也不报错" "echo \"\$OUT2\" | grep -q 'agent-team-cli-recovery'"
cd "$ROOT"

echo "== 6. install / uninstall（隔离 CLAUDE_HOME）=="
FAKE="$TMP/home"; mkdir -p "$FAKE"
printf '{"permissions":{"defaultMode":"default"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo keep"}]}]}}\n' > "$FAKE/settings.json"
if command -v python3 >/dev/null 2>&1; then
  CLAUDE_HOME="$FAKE" bash "$ROOT/install.sh" --yes >/dev/null 2>&1
  check "install: skill 已复制" "[ -f '$FAKE/skills/agent-team-cli/SKILL.md' ]"
  cnt() { python3 -c "import json;d=json.load(open('$FAKE/settings.json'));print(sum(1 for e in d.get('hooks',{}).get('SessionStart',[]) for h in e.get('hooks',[]) if 'session-recover' in h.get('command','')))"; }
  check "install: hook 恰好 1 条" "[ \"\$(cnt)\" = 1 ]"
  CLAUDE_HOME="$FAKE" bash "$ROOT/install.sh" --yes >/dev/null 2>&1
  check "install 幂等: 再装仍 1 条 hook" "[ \"\$(cnt)\" = 1 ]"
  check "install: 其他 hooks/permissions 保留" "python3 -c \"import json;d=json.load(open('$FAKE/settings.json'));assert d['permissions']['defaultMode']=='default' and len(d['hooks']['PreToolUse'])==1\""
  check "install: 备份在 skills/ 之外且 skills/ 内无 .bak" "[ -d '$FAKE/agent-team-cli.backup' ] && [ -z \"\$(ls -d '$FAKE'/skills/agent-team-cli.bak* 2>/dev/null)\" ]"
  check "install: 幂等重装不新增 settings 备份" "[ \"\$(ls '$FAKE'/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' ')\" = 1 ]"
  CLAUDE_HOME="$FAKE" bash "$ROOT/install.sh" --link --yes >/dev/null 2>&1
  check "install --link: 是符号链接" "[ -L '$FAKE/skills/agent-team-cli' ]"
  CLAUDE_HOME="$FAKE" bash "$ROOT/uninstall.sh" --yes >/dev/null 2>&1
  check "uninstall: skill 已删" "[ ! -e '$FAKE/skills/agent-team-cli' ]"
  check "uninstall: 备份目录已清理" "[ ! -e '$FAKE/agent-team-cli.backup' ]"
  check "uninstall: hook 已删且其他保留" "[ \"\$(cnt)\" = 0 ] && python3 -c \"import json;d=json.load(open('$FAKE/settings.json'));assert 'PreToolUse' in d['hooks'] and 'permissions' in d\""
  rm -rf "$FAKE"; mkdir -p "$FAKE"; echo '{}' > "$FAKE/settings.json"
  CLAUDE_HOME="$FAKE" bash "$ROOT/install.sh" --no-hook --yes >/dev/null 2>&1
  check "install --no-hook: 不改 settings" "[ \"\$(cat '$FAKE/settings.json')\" = '{}' ] && [ -f '$FAKE/skills/agent-team-cli/SKILL.md' ]"
else
  ko "python3 不可用，跳过 install/uninstall 测试"
fi

echo "== 7. 仓库卫生 =="
LEAK_PAT="$(printf '%s\\|%s\\|%s' 'pengyuan''feng' 'agent-''d2' '/tmp/cc-''socks')"
check "无个人路径/会话名残留" "! grep -rn \"\$LEAK_PAT\" '$ROOT' --exclude-dir=.git --exclude=plan.md -q"
check "runs/ 与运行时目录未入库" "! git -C '$ROOT' ls-files 2>/dev/null | grep -qE '^runs/|\.claude/agent-team-cli/'"

echo
echo "通过 $PASS，失败 $FAIL"
[ "$FAIL" = 0 ]
