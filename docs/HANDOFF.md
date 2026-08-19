# 维护交接（给下一个维护会话）

> 本仓库由一次长会话从零建成并发布 v0.1.0。以下是继续维护所需的最少上下文。

## 项目是什么
Claude Code 的多会话 Agent Team 编排 skill：主控开 4 个 Terminal 窗口启动 planner / plan-reviewer / executor / verifier 独立会话，用原生跨会话消息驱动状态机。详见 [README](../README.md)、[architecture](architecture.md)、[design-decisions](design-decisions.md)。

## 唯一真源与本机安装关系
- 仓库 `skills/agent-team-cli/` 是唯一真源。
- 维护者本机 `~/.claude/skills/agent-team-cli` 是指向仓库该目录的**符号链接**（`./install.sh --link`），仓库改动即时生效；**不要**在本机再装插件版（同名冲突 + hook 双触发）。
- 维护者本机 `~/.claude/settings.json` 已注册 SessionStart hook → `~/.claude/skills/agent-team-cli/scripts/session-recover.sh`（经符号链接生效）。

## 改动流程（见 CLAUDE.md）
1. 改 SKILL / roles / scripts → `tests/run.sh` 必须全绿
2. 涉及 SKILL / roles / launch 的实质改动 → 按 `docs/manual-e2e-checklist.md` 人工回归一次
3. 更新 `CHANGELOG.md`；语义化版本；发版打 tag + GitHub Release

## 验证状态（截至 v0.1.0）
- 端到端实测两次通过（番茄钟任务，见 examples/；发布前又以 wordcount 小任务回归了参数化/tty 定位/ensure-inbound/slug 后缀/单角色重启，并由此引入令牌协议；令牌协议随后做了单角色活体验证：无令牌拒绝、有令牌执行、回报直达）
- claude 会话优雅退出需 3–10 秒：shutdown/restart 脚本先 TERM 再等最多 15 秒再 KILL，然后才 close 窗口，否则 Terminal 会弹终止确认框：开窗、READY 握手、规划环 2 轮、执行验证环 1 轮、终验、两个卡点、看门狗唤醒、闲置 2 天唤醒。
- 实测后新增/改动并已回归的：模型/权限参数化（DRY_RUN）、去 python3 的 hook 脚本（三场景）、install/uninstall（隔离 HOME 幂等/精确移除）、doctor、TOFU 双通道来源校验（改措辞）、slug 后缀命名（DRY_RUN）、陈旧记录自动清理（真实窗口场景）。
- 发布前做过一次"陌生人首次安装"视角的对抗性审查并修复（CI 缺 claude、示例断链、备份目录被当 skill、首次运行需重启主控的流程、settings 合并无脚本、git init 护栏、窗口 ID 竞态、放弃任务后 hook 持续注入、来源校验协议不一致 等）。

## 仓库与门禁（2026-08-18 起）
- 公开仓库：https://github.com/Pengyf04/claude-agent-team-cli （MIT）
- `main` 受分支保护：必须走 PR；必需检查 `test`（CI 汇总作业）；禁 force push、禁删分支、要求线性历史。
  「对管理员强制」故意设为关闭——单人维护者不能被自己锁在门外，但 force push / 删分支的禁令对所有人生效。
- 发版：打 tag `vX.Y.Z` 并推送即可，`release.yml` 会重跑测试并自动建 Release。别手工 `gh release create`（绕过门禁）。

## 曾踩过的坑（别再踩）· CI 篇
- **headless 环境下 `osascript` 会无限阻塞，不会报错**。首次 CI 就因此卡死 21 分钟：屏幕几何查询位于
  DRY_RUN 判断之前，`|| true` 兜底只防失败、防不住挂起。现已统一走 `osa` 超时包装器，
  `tests/run.sh` 有伪造阻塞型 osascript 的回归用例守住。新增任何 osascript 调用都必须经 `osa`。
- workflow 不写 `timeout-minutes` 时默认上限是 **360 分钟**，挂死会一直烧。
- 用 matrix 会把检查名变成 `test (macos-14)` 这种形式，**直接让分支保护的必需检查失效**；
  所以保留一个名为 `test` 的汇总作业专门给分支保护盯。
- `brew install shellcheck` 在 macOS runner 上很慢，先 `command -v` 探测再决定装。
- **后台进程继承 stdout 会让 CI 步骤永远结束不了**：runner 用管道捕获步骤输出，任何仍持有该
  管道的后台进程都会让读端等不到 EOF —— 脚本早跑完了，步骤却一直挂着。
  `kill -9` 只杀得掉子 shell，杀不掉它底下正在跑的 `sleep`，那个孤儿会继续持有管道。
  两个对策都要在：后台块一律 `>/dev/null 2>&1`（osa 里那句是承重的），
  以及看门狗用「多次短 sleep」而非「一次长 sleep」，把孤儿存活压到 1 秒内。
  判定方法：`bash tests/run.sh > 文件` 秒退但 `bash tests/run.sh | tail` 挂住，就是这个问题。
- **别写 `cmd_that_never_ends | head -c N` 这类「无限生产者 + 提前退出消费者」的管道**。
  它依赖 head 退出后生产者被 SIGPIPE 杀死；而 SIGPIPE 一旦被忽略（`SIG_IGN` 会被子进程继承，
  Node 写的 GitHub Actions runner 正是如此），生产者会 98% CPU 无限空转，命令替换永远等不到它。
  令牌生成踩过这个坑，现改为 `od -N 32` 有界读取。判定方法：
  `bash -c "trap '' PIPE; bash 你的脚本"` 能复现，正常环境不能。
- `tests/run.sh` 自带看门狗（`TEST_TIMEOUT`，默认 600 秒）：超时会打印**最后进入的检查点**再中止。
  这样作业是正常失败而非被强制取消——被取消时缓冲日志会丢，挂死点就无从定位。

## 已知限制 / Roadmap
macOS only；仅 Claude 系模型；Fast 需手动；中文 prompt。Roadmap：英文包、插件分发、Linux/WSL2 后端、executor 调 codex exec。

## 曾踩过的坑（别再踩）
- AppleScript 里 `STOP` 等是保留字，布局脚本变量不能这么命名。
- 桌面版主控的显示名 ≠ `--name`，且角色无法观测 READY 送达地址 → 来源校验用团队令牌（不靠名字/地址）。
- 角色向裸 socket 地址发过一次消息后，其后续消息会持续被扣 → 协议：回报只按主控名发一次；坏了用 restart-role.sh。
- 桌面版会话不读项目级 settings.local.json 的 crossSessionInbound、不显示批准框、无 /status。
- 主控跑 launch/shutdown/restart 脚本必须非沙箱（AppleScript + 杀进程）。
- 角色对 runs/ 的通配符 rm 会触发 bypass 也拦不住的确认框 → 协议：mktemp -d。
- 短时间内重发一模一样的消息会被系统去重丢弃，重发要换措辞。
- SendMessage 目标不在"本会话"时要用 `名字 [ref]` 形式。
- 主控空闲不会自己醒：任何"超时"都必须靠后台 `sleep` 看门狗。
- 不要在 `/goal` 等自动续跑模式下运行 skill——人工卡点会被反复催促（SKILL 已加固：绝不替用户放行）。
