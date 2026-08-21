#!/bin/bash
# tests/run.sh — 不依赖真实 Claude 会话与开窗的自动化测试
# 覆盖：bash 语法、SKILL frontmatter、DRY_RUN 冒烟（默认/覆盖/非法值/后缀）、陈旧记录判定、
#       hook 三场景、install/uninstall 幂等与精确移除（隔离 CLAUDE_HOME）、个人信息残留检查、
#       osascript 阻塞回归、文档完整性与配置项同步
# 不覆盖（按设计，需真实 GUI 与 Claude 会话）：开窗布局、READY 握手、角色状态机流转、
#       上下文压缩恢复的真实行为 —— 这些走 docs/manual-e2e-checklist.md 人工回归。
set -uo pipefail
# 无图形界面环境下 osascript 会阻塞；测试里把超时压到 1 秒，避免每次调用白等默认的 8 秒
export ATC_OSA_TIMEOUT=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/skills/agent-team-cli"
TMP="$(mktemp -d)"
# ---------- 看门狗 ----------
# 测试套件自己限时中止，而不是等 CI 作业超时被强制取消：被取消时缓冲的日志会丢失，
# 挂死点就无从定位（2026-08-18 首次 CI 事故正是栽在这上面）。
# 同时它也保证「测试套件本身绝不会永久挂死」。
MARKER="$TMP/marker"; printf '%s' '启动' > "$MARKER"
mark() { printf '%s' "$*" > "$MARKER"; }
SUITE_TIMEOUT="${TEST_TIMEOUT:-600}"
MAINPID=$$
(
  # 用「多次短 sleep」而不是「一次长 sleep」：kill -9 只能杀掉子 shell，
  # 它底下正在跑的 sleep 会成为孤儿继续存活，并且继承着 stdout。
  # 若 stdout 是管道（CI runner 正是用管道捕获步骤输出），读端就永远等不到 EOF ——
  # 脚本明明跑完了，步骤却一直挂着。短 sleep 把孤儿存活时间压到 1 秒以内。
  _i=0
  while [ "$_i" -lt "$SUITE_TIMEOUT" ]; do sleep 1; _i=$((_i+1)); done
  printf '\n\xe2\x9d\x8c\xe2\x9d\x8c 测试套件整体超时（%s 秒）。最后进入的检查点: %s\n' \
    "$SUITE_TIMEOUT" "$(cat "$MARKER" 2>/dev/null)"
  printf '（这是 tests/run.sh 自带的看门狗，用于精确定位挂死位置）\n'
  kill -9 "$MAINPID" 2>/dev/null
) &
WATCHDOG=$!
disown "$WATCHDOG" 2>/dev/null || true   # 免得被杀时 bash 打印 "Killed: 9" 污染 CI 日志
trap 'kill -9 "$WATCHDOG" 2>/dev/null; rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$*"; }
ko()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$*"; }
check() { mark "检查: $1"; if eval "$2"; then ok "$1"; else ko "$1"; fi; }

mark "小节 1. 语法"; echo "== 1. 语法 =="
for f in "$ROOT"/install.sh "$ROOT"/uninstall.sh "$SKILL"/scripts/*.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f'"
done

mark "小节 2. SKILL frontmatter / 角色文件"; echo "== 2. SKILL frontmatter / 角色文件 =="
check "SKILL.md 有 name: agent-team-cli" "grep -q '^name: agent-team-cli$' '$SKILL/SKILL.md'"
check "SKILL 含桌面版 inbound 指引（用户级 accept）" "grep -q 'claude-desktop' '$SKILL/SKILL.md' && grep -q '用户级' '$SKILL/SKILL.md'"
check "SKILL 警示两个 rename 入口" "grep -q 'Custom command' '$SKILL/SKILL.md'"
check "SKILL 重入时比对注册名并要求先改回" "grep -q '先核对自己的注册名' '$SKILL/SKILL.md'"
check "SKILL 恢复后补 ping 正在等待的角色" "grep -q '补 ping' '$SKILL/SKILL.md'"
check "SKILL.md 有 description" "grep -q '^description: ' '$SKILL/SKILL.md'"
for r in planner plan-reviewer executor verifier; do
  check "roles/$r.md 存在且含通信协议" "grep -q '通信协议' '$SKILL/roles/$r.md'"
done
for r in planner plan-reviewer executor verifier; do
  check "roles/${r}.md 含交付前清理临时产物纪律" "grep -q '交付前清理临时产物' '$SKILL/roles/$r.md' && grep -q '不要对' '$SKILL/roles/$r.md'"
  check "roles/$r.md 含令牌校验/名字回报/mktemp 纪律" "grep -q '团队令牌' '$SKILL/roles/$r.md' && grep -q '绝不发往 socket 地址' '$SKILL/roles/$r.md' && grep -q 'mktemp -d' '$SKILL/roles/$r.md'"
done
check "restart-role.sh 语法" "bash -n '$SKILL/scripts/restart-role.sh'"
check "restart-role.sh 拒绝非法角色" "! bash '$SKILL/scripts/restart-role.sh' '$TMP' bogus >/dev/null 2>&1"

mark "小节 3. launch-team.sh DRY_RUN"; echo "== 3. launch-team.sh DRY_RUN =="
P="$TMP/proj"; mkdir -p "$P"
DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" atc-main demo >/dev/null 2>&1
check "默认: planner 用 claude-fable-5/xhigh" "grep -q -- '--model \"claude-fable-5\"' '$P/.claude/agent-team-cli/run-planner.sh' && grep -q -- '--effort \"xhigh\"' '$P/.claude/agent-team-cli/run-planner.sh'"
check "默认: executor 用 claude-opus-5/high" "grep -q -- '--model \"claude-opus-5\"' '$P/.claude/agent-team-cli/run-executor.sh' && grep -q -- '--effort \"high\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "默认: 权限 bypassPermissions" "grep -q -- '--permission-mode \"bypassPermissions\"' '$P/.claude/agent-team-cli/run-verifier.sh'"
check "后缀: 会话名 executor-demo, 主控名 atc-main" "grep -q -- '--name \"executor-demo\"' '$P/.claude/agent-team-cli/run-executor.sh' && grep -q '主控会话名为「atc-main」' '$P/.claude/agent-team-cli/run-executor.sh'"
check "runner 含 crossSessionInbound accept 与角色 prompt 注入" "grep -q 'crossSessionInbound' '$P/.claude/agent-team-cli/run-planner.sh' && grep -q -- '--append-system-prompt' '$P/.claude/agent-team-cli/run-planner.sh'"
check "runner 含 claude 检测" "grep -q 'command -v claude' '$P/.claude/agent-team-cli/run-planner.sh'"
check "生成了团队令牌文件且注入 runner 启动指令" "[ -s '$P/.claude/agent-team-cli/token' ] && grep -q \"团队令牌为「\$(cat '$P/.claude/agent-team-cli/token')」\" '$P/.claude/agent-team-cli/run-planner.sh'"
TOK1="$(cat "$P/.claude/agent-team-cli/token")"
DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" atc-main demo >/dev/null 2>&1
check "重复生成 runner 时令牌保持不变" "[ \"\$(cat '$P/.claude/agent-team-cli/token')\" = '$TOK1' ]"
check "runner 语法" "bash -n '$P/.claude/agent-team-cli/run-planner.sh'"
rm -rf "$P/.claude"
ATC_MODEL_DEFAULT=opus ATC_MODEL_PLAN_REVIEWER=sonnet ATC_EFFORT_EXECUTOR=medium ATC_PERMISSION_MODE=acceptEdits DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" atc-main demo >/dev/null 2>&1
check "覆盖: ATC_MODEL_DEFAULT→planner=opus" "grep -q -- '--model \"opus\"' '$P/.claude/agent-team-cli/run-planner.sh'"
check "覆盖: ATC_MODEL_DEFAULT 也作用于 executor" "grep -q -- '--model \"opus\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "覆盖: ATC_MODEL_PLAN_REVIEWER=sonnet" "grep -q -- '--model \"sonnet\"' '$P/.claude/agent-team-cli/run-plan-reviewer.sh'"
check "覆盖: ATC_EFFORT_EXECUTOR=medium" "grep -q -- '--effort \"medium\"' '$P/.claude/agent-team-cli/run-executor.sh'"
check "覆盖: ATC_PERMISSION_MODE=acceptEdits" "grep -q -- '--permission-mode \"acceptEdits\"' '$P/.claude/agent-team-cli/run-executor.sh'"
rm -rf "$P/.claude"
check "非法权限模式被拒绝" "! ATC_PERMISSION_MODE=yolo DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' atc-main demo >/dev/null 2>&1"
check "路径含单引号被拒绝" "! DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' \"$TMP/it's\" atc-main demo >/dev/null 2>&1"
# 回归 2026-08-19 E2E：主控名叫 main 时，角色按名字回报被 SendMessage 拦成
# "You are the main conversation" —— main 是保留收件人，且无绕过（ListAgents 给的 ref
# 不可达，系统自己建议的 ref 也照样落回拦截）。团队会卡死在 P3 握手。
# 已在 2.1.229 与 2.1.235 上复现，不是某版本回归。必须在开窗前就拒绝。
for n in main MAIN Main; do
  check "拒绝保留字主控名 ${n}（否则团队卡死在握手）" "! DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' $n demo >/dev/null 2>&1"
done
rm -rf "$P/.claude"
check "非保留字主控名可正常启动" "DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' atc-main demo >/dev/null 2>&1"
rm -rf "$P/.claude"
rm -rf "$P/.claude"; DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" atc-main >/dev/null 2>&1
check "无后缀: 裸角色名" "grep -q -- '--name \"executor\"' '$P/.claude/agent-team-cli/run-executor.sh'"

mark "小节 3b. prepare-project.sh"; echo "== 3b. prepare-project.sh =="
E="$SKILL/scripts/prepare-project.sh"; Q="$TMP/proj2"; mkdir -p "$Q/.claude" && git -C "$Q" init -q 2>/dev/null
printf '{"permissions":{"allow":["Bash(ls)"]}}\n' > "$Q/.claude/settings.local.json"
check "输出 OK" "[ \"\$(bash '$E' '$Q')\" = OK ]"
check ".git/info/exclude 含运行时产物" "grep -qxF '.claude/agent-team-cli/' '$Q/.git/info/exclude' && grep -qxF '.claude/settings.local.json' '$Q/.git/info/exclude'"
bash "$E" "$Q" >/dev/null
check "幂等：重复运行不重复追加" "[ \"\$(grep -cxF '.claude/agent-team-cli/' '$Q/.git/info/exclude')\" = 1 ]"
check "不碰用户自己的 settings.local.json" "grep -q 'Bash(ls)' '$Q/.claude/settings.local.json'"
# 回归 2026-08-19：项目级 crossSessionInbound 是结构性空操作（该键的项目级来源只在收紧时
# 才被采纳，而 accept 是最宽松档），本脚本绝不能再写它 —— 否则又会给用户虚假的安全感。
check "绝不写入 crossSessionInbound（项目级写它是空操作）" "! grep -q crossSessionInbound '$Q/.claude/settings.local.json'"
check "脚本自身不含 crossSessionInbound 写入逻辑" "! grep -vE '^#' '$E' | grep -q 'crossSessionInbound'"
NG="$TMP/proj-nogit"; mkdir -p "$NG"
check "非 git 目录静默跳过且不报错" "[ \"\$(bash '$E' '$NG')\" = OK ]"

mark "小节 3b2. shutdown 如实报告（不谎报关窗）"; echo "== 3b2. shutdown 如实报告 =="
# 回归 2026-08-21 桌面主控 E2E：查 tty 失败时静默跳过杀进程、关窗失败也被吞掉，
# 脚本却打印"已关闭"。"报告成功但实际没做"是最危险的失败模式。
FB="${TMP}/fakebin2"; mkdir -p "${FB}"
printf '#!/bin/bash\nsleep 120\n' > "${FB}/osascript"; chmod +x "${FB}/osascript"
SD3="${TMP}/sd3"; mkdir -p "${SD3}/.claude/agent-team-cli"
printf 'main=0\nplanner-zz=99999991\n' > "${SD3}/.claude/agent-team-cli/windows.txt"
echo tok > "${SD3}/.claude/agent-team-cli/token"
echo '#!/bin/bash' > "${SD3}/.claude/agent-team-cli/run-planner.sh"
bash -c 'exec -a "claude --name planner-zz --model x" sleep 300' & FAKEPID=$!
sleep 1
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用
SD3OUT="$(PATH="${FB}:$PATH" ATC_OSA_TIMEOUT=1 bash "${SKILL}/scripts/shutdown-team.sh" "${SD3}" 2>&1)"; SD3RC=$?
sleep 1
check "osascript 阻塞时按会话名兜底结束角色进程" "! ps -p ${FAKEPID} >/dev/null 2>&1"
check "无法确认关窗时不谎报已关闭" "! printf '%s' \"\${SD3OUT}\" | grep -q '已关闭 planner-zz'"
check "无法确认关窗时如实告警" "printf '%s' \"\${SD3OUT}\" | grep -q '未能确认关闭'"
check "有残留时以非零码退出" "[ ${SD3RC} -ne 0 ]"
check "有残留时保留 windows.txt 便于重试" "[ -f '${SD3}/.claude/agent-team-cli/windows.txt' ]"
check "有残留时仍作废令牌" "[ ! -f '${SD3}/.claude/agent-team-cli/token' ]"
kill -9 ${FAKEPID} 2>/dev/null || true

mark "小节 3b3. doctor 桌面版/登录检查"; echo "== 3b3. doctor 桌面版与登录检查 =="
check "doctor 含 CLI 登录检查" "grep -q 'claude auth status' '${SKILL}/scripts/doctor.sh'"
check "doctor 含桌面版用户级 accept 检查" "grep -q 'crossSessionInbound' '${SKILL}/scripts/doctor.sh' && grep -q 'claude-desktop' '${SKILL}/scripts/doctor.sh'"
check "doctor 警示两个 rename 入口的陷阱" "grep -q 'Custom command' '${SKILL}/scripts/doctor.sh'"
check "doctor 自身会话检测上溯进程树（不硬依赖父进程号）" "grep -q 'find_self_session' '${SKILL}/scripts/doctor.sh'"
check "doctor 拒绝保留字主控名" "grep -q '保留字 main' '${SKILL}/scripts/doctor.sh'"

mark "小节 5b. 恢复 hook 主控名比对"; echo "== 5b. 恢复 hook 主控名比对 =="
# 用隔离的 CLAUDE_CONFIG_DIR 注入一个假会话注册文件，让比对有确定输入 ——
# 不能依赖"跑测试的机器上恰好有个 claude 会话"（本地有、CI 没有，会造成本地绿 CI 红）。
NM="${TMP}/namechk"; mkdir -p "${NM}/runs/x"
FAKEHOME="${TMP}/fakeclaude"; mkdir -p "${FAKEHOME}/sessions"
printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\nmain会话名: some-old-name ｜ slug: x\n阶段: [2] 执行验证环\n正在等待: executor-x\n' > "${NM}/runs/x/state.md"
# 假装当前 shell 的父进程就是一个注册在案的 claude 会话
printf '{"pid":%s,"name":"current-derived-name","entrypoint":"claude-desktop","cwd":"%s"}\n' "$$" "${NM}" > "${FAKEHOME}/sessions/$$.json"
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用
NMOUT="$(cd "${NM}" && echo '{"source":"startup"}' | CLAUDE_CONFIG_DIR="${FAKEHOME}" bash "${SKILL}/scripts/session-recover.sh" 2>&1)"
check "记录名与当前名不符时主动报警" "printf '%s' \"\${NMOUT}\" | grep -q '主控名不一致'"
check "报警点明记录名与当前名" "printf '%s' \"\${NMOUT}\" | grep -q 'some-old-name' && printf '%s' \"\${NMOUT}\" | grep -q 'current-derived-name'"
check "报警附带 /rename 恢复命令" "printf '%s' \"\${NMOUT}\" | grep -q '/rename some-old-name'"
check "报警区分两个 rename 入口" "printf '%s' \"\${NMOUT}\" | grep -q 'Custom command'"
# 名字一致时不应误报
printf '{"pid":%s,"name":"some-old-name","entrypoint":"cli","cwd":"%s"}\n' "$$" "${NM}" > "${FAKEHOME}/sessions/$$.json"
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用
NMOUT2="$(cd "${NM}" && echo '{"source":"startup"}' | CLAUDE_CONFIG_DIR="${FAKEHOME}" bash "${SKILL}/scripts/session-recover.sh" 2>&1)"
check "名字一致时不误报" "printf '%s' \"\${NMOUT2}\" | grep -q '主控名一致' && ! printf '%s' \"\${NMOUT2}\" | grep -q '主控名不一致'"

mark "小节 3c. shutdown-team.sh --abandon"; echo "== 3c. shutdown-team.sh --abandon =="
mkdir -p "$Q/runs/demo" && printf 'skill: agent-team-cli/SKILL.md\n阶段: [2] 执行验证环\n' > "$Q/runs/demo/state.md"
bash "$SKILL/scripts/shutdown-team.sh" "$Q" --abandon demo >/dev/null 2>&1
check "--abandon 把阶段改为已放弃完成" "grep -q '^阶段: \[P5\] 完成（已放弃）' '$Q/runs/demo/state.md'"
# 团队令牌必须随团队一同作废：令牌要能区分团队世代，否则侥幸存活的旧角色窗口
# 仍能接受新团队指令——正好是它要防的场景。
SD="${TMP}/shutdown"; mkdir -p "${SD}/.claude/agent-team-cli" "${SD}/runs/t1"
printf 'main=1\nplanner=99999991\n' > "${SD}/.claude/agent-team-cli/windows.txt"
echo "tok12345" > "${SD}/.claude/agent-team-cli/token"
printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\n阶段: [2] 执行验证环\n' > "${SD}/runs/t1/state.md"
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用，shellcheck 无法看穿 eval
SDOUT="$(bash "${SKILL}/scripts/shutdown-team.sh" "${SD}" 2>&1)"
check "shutdown 后团队令牌已作废" "[ ! -f '${SD}/.claude/agent-team-cli/token' ]"
check "shutdown 未传 --abandon 时提示孤儿状态" "printf '%s' \"\${SDOUT}\" | grep -q '仍标记为进行中'"
check "该提示给出可直接执行的 --abandon 命令" "printf '%s' \"\${SDOUT}\" | grep -q -- '--abandon t1'"

check "无 windows.txt 时 shutdown 温和退出(0)" "bash '$SKILL/scripts/shutdown-team.sh' '$Q' >/dev/null 2>&1"

echo "== 3d. PATH 无 claude 时 DRY_RUN 仍可用（CI 场景）=="
rm -rf "$P/.claude"
check "无 claude 也能 DRY_RUN" "env -i HOME='$HOME' PATH=/usr/bin:/bin DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$P' atc-main demo >/dev/null 2>&1 && [ -f '$P/.claude/agent-team-cli/run-planner.sh' ]"

mark "小节 4. 陈旧记录判定"; echo "== 4. 陈旧记录判定 =="
rm -rf "$P/.claude"; mkdir -p "$P/.claude/agent-team-cli"
printf 'main=0\nplanner=99999991\nexecutor=99999992\n' > "$P/.claude/agent-team-cli/windows.txt"
OUT="$(DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$P" atc-main demo 2>&1)"
check "窗口均不存在 → 自动清理并继续" "echo \"\$OUT\" | grep -q '陈旧' && echo \"\$OUT\" | grep -q 'DRY_RUN'"

echo "== 4b. osascript 阻塞时不挂死（headless/CI 回归）=="
# 回归 2026-08-18 首次 CI 事故：屏幕几何查询位于 DRY_RUN 判断之前，headless 环境下
# osascript 无限阻塞（不是失败），原有 `|| true` 兜底永远走不到，CI 卡死 21 分钟。
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/bash\nsleep 120\n' > "$FAKEBIN/osascript"; chmod +x "$FAKEBIN/osascript"
R="$TMP/proj-hang"; mkdir -p "$R"
T0=$(date +%s)
PATH="$FAKEBIN:$PATH" DRY_RUN=1 bash "$SKILL/scripts/launch-team.sh" "$R" atc-main demo >"$TMP/hang.out" 2>&1
HRC=$?; T1=$(date +%s)
check "osascript 永久阻塞时 launch-team.sh 仍正常退出" "[ $HRC -eq 0 ]"
check "且在 30 秒内结束（实测 $((T1-T0)) 秒）" "[ $((T1-T0)) -lt 30 ]"
check "打印超时警告并改用兜底屏幕尺寸" "grep -q '兜底值' '$TMP/hang.out'"
T2=$(date +%s)
PATH="$FAKEBIN:$PATH" bash "$SKILL/scripts/doctor.sh" "$R" >/dev/null 2>&1
T3=$(date +%s)
RR="${TMP}/proj-restart"; mkdir -p "${RR}/.claude/agent-team-cli"
printf 'main=1\nplanner=99999991\n' > "${RR}/.claude/agent-team-cli/windows.txt"
echo '#!/bin/bash' > "${RR}/.claude/agent-team-cli/run-planner.sh"
T6=$(date +%s)
PATH="${FAKEBIN}:$PATH" bash "${SKILL}/scripts/restart-role.sh" "${RR}" planner >/dev/null 2>&1
RRC=$?; T7=$(date +%s)
check "restart-role.sh 在 osascript 阻塞时不挂死（实测 $((T7-T6)) 秒）" "[ $((T7-T6)) -lt 30 ]"
check "restart-role.sh 开窗超时时报错退出而非静默" "[ ${RRC} -ne 0 ]"
check "restart-role.sh 超时不会把空窗口 id 写进 windows.txt" "! grep -qE '^planner=$' '${RR}/.claude/agent-team-cli/windows.txt'"
check "doctor.sh 同环境下也在 30 秒内结束（实测 $((T3-T2)) 秒）" "[ $((T3-T2)) -lt 30 ]"

# 回归 2026-08-19：SIGPIPE 被忽略时（SIG_IGN 会被子进程继承，Node 写的 GitHub Actions
# runner 正是如此），`tr -dc ... </dev/urandom | head -c N` 里的 tr 不再会被 head 的退出
# 杀死，而是 98% CPU 无限空转，命令替换永远等不到它 —— CI 就是这么挂死的。
R2="$TMP/proj-sigpipe"; mkdir -p "$R2"
T4=$(date +%s)
bash -c "trap '' PIPE; DRY_RUN=1 bash '$SKILL/scripts/launch-team.sh' '$R2' atc-main demo" >/dev/null 2>&1
SRC=$?; T5=$(date +%s)
check "SIGPIPE 被忽略时 launch-team.sh 不空转挂死（实测 $((T5-T4)) 秒）" "[ $SRC -eq 0 ] && [ $((T5-T4)) -lt 30 ]"
check "该环境下仍能正常生成 8 位令牌" "[ \"\$(wc -c < '$R2/.claude/agent-team-cli/token' | tr -d ' ')\" = 9 ]"

mark "小节 5. session-recover.sh 三场景"; echo "== 5. session-recover.sh 三场景 =="
H="$SKILL/scripts/session-recover.sh"
mkdir -p "$TMP/empty"; cd "$TMP/empty" || exit 1
check "无任务目录 → 静默" "[ -z \"\$(echo '{\"source\":\"startup\"}' | bash '$H')\" ]"
mkdir -p "$TMP/done/runs/x" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\nmain会话名: main\n阶段: [P5] 完成\n' > "$TMP/done/runs/x/state.md"; cd "$TMP/done" || exit 1
check "已完成任务 → 静默" "[ -z \"\$(echo '{\"source\":\"compact\"}' | bash '$H')\" ]"
mkdir -p "$TMP/aband/runs/z" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\n阶段: [P5] 完成（已放弃）\n' > "$TMP/aband/runs/z/state.md"; cd "$TMP/aband" || exit 1
check "已放弃任务 → 静默" "[ -z \"\$(echo '{\"source\":\"compact\"}' | bash '$H')\" ]"
mkdir -p "$TMP/live/runs/y" && printf 'skill: ~/.claude/skills/agent-team-cli/SKILL.md\nmain会话名: main\n阶段: [2] 执行验证环\n正在等待: verifier\n' > "$TMP/live/runs/y/state.md"; cd "$TMP/live" || exit 1
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用，shellcheck 无法看穿 eval
OUT="$(echo '{"source":"compact"}' | bash "$H")"
check "进行中任务 → 注入且识别 compact" "echo \"\$OUT\" | grep -q 'agent-team-cli-recovery' && echo \"\$OUT\" | grep -q '上下文刚被压缩' && echo \"\$OUT\" | grep -q '正在等待: verifier'"
# shellcheck disable=SC2034  # 在 check 的 eval 字符串中使用，shellcheck 无法看穿 eval
OUT2="$(bash "$H" </dev/null)"
check "进行中但无角色在册 → 给出孤儿状态警告" "echo \"\${OUT}\" | grep -q '没有任何角色会话在册'"
check "孤儿状态警告附带 --abandon 处置命令" "echo \"\${OUT}\" | grep -q -- '--abandon'"
check "对 state.md 记录的主控名给出比对结论" "echo \"\${OUT}\" | grep -qE '主控名不一致|主控名一致|未能比对主控名'"
check "无 stdin 也不报错" "echo \"\$OUT2\" | grep -q 'agent-team-cli-recovery'"
cd "$ROOT" || exit 1

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

mark "小节 7. 仓库卫生"; echo "== 7. 仓库卫生 =="
LEAK_PAT="$(printf '%s\\|%s\\|%s' 'pengyuan''feng' 'agent-''d2' '/tmp/cc-''socks')"
# 只扫已入库文件：把关的是"发出去的内容"。扫目录树会被本地产物（worktree 的 .git 指针、
# 临时文件等）误报，而那些东西根本不会被推送。
leak_scan() { git -C "$ROOT" ls-files -z | xargs -0 grep -n "$LEAK_PAT"; }
check "已入库文件无个人路径/会话名残留" "[ -z \"\$(leak_scan)\" ]"
check "runs/ 与运行时目录未入库" "! git -C '$ROOT' ls-files 2>/dev/null | grep -qE '^runs/|\.claude/agent-team-cli/'"

mark "小节 7b. 文档完整性 / 配置项同步"; echo "== 7b. 文档完整性 / 配置项同步 =="
# 历史 bug：examples 断链导致新人照 README 走不通。链接是分发路径的一部分，必须自动把关。
BROKEN=""
while IFS= read -r f; do
  while IFS= read -r link; do
    case "$link" in http*|mailto:*|\#*) continue ;; esac
    tgt="$ROOT/$(dirname "$f")/${link%%\#*}"
    [ -e "$tgt" ] || BROKEN="$BROKEN$f -> $link; "
  done <<< "$(grep -oE '\]\([^)]+\)' "$ROOT/$f" 2>/dev/null | sed 's/^](//;s/)$//')"
done <<< "$(git -C "$ROOT" ls-files '*.md' 2>/dev/null)"
# 脚本拒绝了保留字，但文档若还教用户 `claude --name main`，用户照样一头撞上去。
# 这次事故的根本教训就是二者必须同时正确。
BADDOC="$(LC_ALL=C git -C "${ROOT}" ls-files '*.md' | while IFS= read -r f; do
  LC_ALL=C grep -nE 'claude --name +main([^-a-zA-Z0-9]|$)' "${ROOT}/$f" | sed "s|^|$f:|"
done)"
# 文档不得再"教用户去执行" ensure-inbound.sh：项目级写 crossSessionInbound 是空操作，
# 照做也会卡死（2026-08-19 实证）。只查调用写法，不查叙述性提及——
# CHANGELOG 是历史记录、design-decisions 与 HANDOFF 需要保留"原来叫什么、为什么废弃"。
BADCFG="$(LC_ALL=C git -C "${ROOT}" ls-files '*.md' | grep -v '^CHANGELOG.md$' | while IFS= read -r f; do
  LC_ALL=C grep -nE 'bash [^|]*ensure-inbound\.sh' "${ROOT}/$f" | sed "s|^|$f:|"
done)"
check "文档不再引导用户执行已废弃的 ensure-inbound.sh${BADCFG:+（${BADCFG}）}" "[ -z '$BADCFG' ]"

check "文档未教用户用保留字主控名 main${BADDOC:+（${BADDOC}）}" "[ -z '$BADDOC' ]"

check "Markdown 内部链接均可解析${BROKEN:+（断链: ${BROKEN}）}" "[ -z '$BROKEN' ]"

# CLAUDE.md 的人工约定「新增配置项须同步 README + doctor.sh」在此变成自动检查——
# 靠人记的规矩会烂掉，靠测试的不会。
MISSING=""
for v in $(grep -oE 'ATC_[A-Z]+[A-Z_]*' "$SKILL/scripts/launch-team.sh" | sed 's/_$//' | sort -u); do
  grep -q "$v" "$ROOT/README.md" 2>/dev/null || MISSING="$MISSING README缺:$v "
  grep -q "$v" "$SKILL/scripts/doctor.sh" 2>/dev/null || MISSING="$MISSING doctor缺:$v "
done
check "所有 ATC_* 配置项已同步到 README 与 doctor.sh${MISSING:+（${MISSING}）}" "[ -z '$MISSING' ]"

# 回归 2026-08-19：`$VAR` 紧挨中文字符时，UTF-8 locale 下 bash 会把中文的高位字节
# 并进变量名（"PASS?: unbound variable"）。本仓库提示信息全是中文，这个坑遍地都是。
# C locale 不触发 —— 维护者本机恰好是 C，于是一路没发现，直到 CI 暴露。
ADJ="$(LC_ALL=C git -C "${ROOT}" ls-files '*.sh' | while IFS= read -r f; do
  LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "${ROOT}/$f" | sed "s|^|$f:|"
done)"
check "无「\$VAR 紧挨非 ASCII」写法（须写成 \${VAR}）${ADJ:+（${ADJ}）}" "[ -z '$ADJ' ]"

echo
echo "通过 ${PASS}，失败 $FAIL"
echo "注: 本套测试不覆盖真实开窗/握手/状态机流转（需 GUI 与 Claude 会话），发版前请按 docs/manual-e2e-checklist.md 人工回归。"
[ "$FAIL" = 0 ]
