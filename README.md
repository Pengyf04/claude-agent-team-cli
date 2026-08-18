# claude-agent-team-cli

**多窗口、多会话的 Claude Code Agent Team 编排框架。**
一个主控会话（main）自动开 4 个终端窗口，启动 planner / plan-reviewer / executor / verifier 四个**独立 Claude Code 会话**，用 Claude Code 原生的跨会话消息驱动「规划 → 评审 → 执行 ⇄ 验证 → 终验」状态机；每个角色的工作过程在各自窗口里实时可见、可介入；所有需要人拍板的事项统一经主控与你沟通。

> 这是 [claude-agent-team](https://github.com/Pengyf04/claude-agent-team)（单会话 subagent 版）的多会话形态：同一套「规划者 / 规划评审者 / 执行者 / 验证者」角色与状态机，但角色不再是同一会话里的 subagent，而是**各自独立的 CLI 会话**，互不共享上下文、各自可观察可介入。

---

## ⚠️ 适用前提（安装前务必先读）

1. **仅支持 macOS。** 开窗与布局依赖 Terminal.app + AppleScript。Linux / WSL2 在 roadmap（核心通信机制在 Linux 可用，缺的是开窗后端）；**原生 Windows 不可用**——Claude Code 的跨会话消息本身不支持原生 Windows，待官方支持后再评估。
2. **Claude Code ≥ 2.1.224**（跨会话消息 `ListAgents` / `SendMessage`）。在会话里输入 `/list-agents` 能被识别即可用。**Amazon Bedrock / Google Vertex / Microsoft Foundry 上不可用**（官方限制）。
3. **你的账号要能使用所选模型。** 默认 planner / plan-reviewer / verifier 用 `claude-fable-5`（effort xhigh），executor 用 `claude-opus-5`（effort high）。无 Fable 权限请 `export ATC_MODEL_DEFAULT=opus`（或 `sonnet`），见[参数](#参数)。
4. **用量提醒。** 主控 + 4 个角色 = 5 个并发 Claude 会话；等待中的角色不消耗 token，但一次完整任务的总消耗明显高于单会话。
5. **安全姿态。** 4 个角色会话默认以 `bypassPermissions` 运行（全自动循环不停下等确认），框架强制项目为 git 仓库作为回滚兜底；可用 `ATC_PERMISSION_MODE` 改为更保守的模式（代价是循环可能停下等你在各窗口批准）。详见[安全说明](#安全说明)。
6. 首次运行 macOS 会弹「"Claude" 想要控制 "Terminal"」的自动化授权，请允许。

---

## 安装

```bash
git clone https://github.com/Pengyf04/claude-agent-team-cli.git
cd claude-agent-team-cli && ./install.sh
```

`install.sh` 会：① 把 skill 复制到 `~/.claude/skills/agent-team-cli/`；② 在 `~/.claude/settings.json` 的 `hooks.SessionStart` 追加一条**上下文压缩后自动恢复状态**的 hook（先备份、幂等；不想改 settings 用 `--no-hook`，只影响压缩恢复，不装也能跑）。执行前会列出将做的改动并等你确认。

- 开发者模式（仓库改动即时生效）：`./install.sh --link`
- 自检：`bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh`
- 卸载：`./uninstall.sh`（只删自己的 skill 目录和自己那条 hook）
- 依赖：`git`、`python3`（macOS 装了 Command Line Tools 就都有；`python3` 只用于安全合并 settings.json）

安装后**新开**一个 Claude Code 会话（hook 对新会话生效）。

---

## 快速开始

```bash
cd /path/to/your/project        # 建议是 git 仓库
claude --name main              # 启动主控；模型/effort 按需自选
```
在主控会话里：
```
/agent-team-cli 用 Python 标准库实现一个命令行番茄钟，附 pytest 测试；验收标准：……
```
接下来会发生：

| 阶段 | 主控做什么 | 你做什么 |
|---|---|---|
| P0 目标对齐 | 分析任务，逐个问清疑点，确保有**可判定的验收标准** | 回答问题 / 给验收标准 |
| P1 环境准备 | 检查 git；写入项目 `.claude/settings.local.json` 的 `crossSessionInbound: accept`（跨会话消息不被拦截）；建 `runs/<slug>/` | 若提示"需重启 main"就重启一次再调用 |
| P2 开窗启动 | 开 4 个 Terminal 窗口（主屏均分：main 左 1/3，四角色右 2/3 田字格），按预设模型/权限启动 4 个会话 | 在各新窗口接受首次的「文件夹信任 / Bypass 警告」确认框 |
| 🔴 P3 就绪确认 | 收齐 4 个 READY 后提醒你核对各窗口配置 | 核对模型/effort（executor 想提速可手动 `/fast`）→ 回复「确认」 |
| P4 状态机 | 规划环（planner ⇄ reviewer，≤5 轮）→ **🔴 卡点 A**（plan 定稿给你确认）→ 执行验证环（executor ⇄ verifier，≤8 轮）→ 终验（planner，回退 ≤2 次）→ **🔴 卡点 B**（交付物 + 验证结论 + 风险给你终审） | 两个卡点回复确认或提修改意见 |
| P5 收尾 | 总结；问你是否关闭 4 个窗口 | 选择（手动关窗也可，脚本能识别） |

一次真实运行的完整产物见 [examples/pomodoro-cli/](examples/pomodoro-cli/)。

---

## 它是怎么工作的（30 秒版）

- **通信**：主控用 `SendMessage` 按会话名派活；角色完成后 `SendMessage` 回报，最后一行是结构化标记（`PLAN_READY` / `APPROVED` / `NEEDS_REVISION` / `EXECUTION_DONE` / `PASS` / `FAIL` / `FINAL_ACCEPT` / `FINAL_REJECT` / `BLOCKED`），主控据此走状态机。角色之间**不直接通信**，一切经主控——所以主控始终掌握全局。
- **唤醒**：空闲会话收到消息即自动开始新一轮（Claude Code 原生机制），零轮询；空闲不消耗 token；实测闲置 2 天仍可唤醒。
- **文件协议**：实质内容走项目内 `runs/<slug>/`（`task.md` / `plan.md` / `review-log.md` / `deliverable/` / `verify-report.md` / `state.md`），消息只传信号。
- **恢复**：主控每步全量重写 `state.md`；SessionStart hook 在上下文压缩/重启后自动把 state.md 与恢复指引注入会话。
- **防护**：循环硬上限（5 / 8 / 2）；角色对消息来源做校验（主控名匹配 或 首次握手锚定地址）；跨会话消息本身自带限流去重，两个会话互刷的死循环会被系统掐断。

细节见 [docs/architecture.md](docs/architecture.md)、设计取舍见 [docs/design-decisions.md](docs/design-decisions.md)。

---

## 参数

在启动主控的 shell 里 `export`（或让主控在 P2 运行脚本时前置）：

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `ATC_MODEL_DEFAULT` | `claude-fable-5` | planner / plan-reviewer / verifier 的模型 |
| `ATC_MODEL_EXECUTOR` | `claude-opus-5` | executor 的模型 |
| `ATC_MODEL_PLANNER` / `ATC_MODEL_PLAN_REVIEWER` / `ATC_MODEL_VERIFIER` | — | 单角色覆盖 |
| `ATC_EFFORT_DEFAULT` | `xhigh` | 默认 effort（`low` / `medium` / `high` / `xhigh` / `max`） |
| `ATC_EFFORT_EXECUTOR`（及其他 `ATC_EFFORT_<ROLE>`） | executor 默认 `high` | 单角色覆盖 |
| `ATC_PERMISSION_MODE` | `bypassPermissions` | 角色会话权限模式（`acceptEdits` / `auto` / `default` 等） |

fast 模式没有启动 flag，且仅 Opus 系支持——需要时在 executor 窗口手动输入 `/fast`。

`launch-team.sh` 还支持 `DRY_RUN=1`（只生成启动脚本不开窗）、`POSITION_MAIN=0`（不移动主控窗口）。多项目并行时角色会话名自动带任务 slug 后缀（如 `executor-pomodoro-cli`），主控建议 `claude --name main-<slug>`。

---

## 安全说明

- **为什么默认 bypassPermissions**：执行 ⇄ 验证的多轮循环要全自动跑完，角色会话不能停下来等你在 4 个窗口里逐个点批准。兜底是 **git**（框架强制项目为 git 仓库，P1 未初始化会自动 `git init`）。想更保守：`ATC_PERMISSION_MODE=acceptEdits`。
- **`crossSessionInbound: accept`**：主控会写入**项目级** `.claude/settings.local.json`（不进 git）。含义是"本项目里启动的会话收到本机其他会话的消息时直接送达，不弹批准框"——没有它，普通模式的主控收到 bypass 角色的消息会被扣住等你批准，全自动就断了。消息即便送达也仍被标记"来自其他会话"：不能替你批准权限、不能改配置、消息里的斜杠命令不会执行。项目不再跑团队时可移除该键（P5 会问你）。
- **角色来源校验**：角色只执行来自主控的指令（主控名匹配 或 首次 READY 握手锚定的地址），其他来源的消息不执行、上报主控。
- **权限边界**：主控绝不指使角色去做主控自己被拒绝的操作（跨会话洗权限）。

---

## 排障速查

| 现象 | 原因 / 处理 |
|---|---|
| READY 收不齐 | 对应窗口多半卡在「文件夹信任 / Bypass 警告」确认框，去点一下；或 `/list-agents` 看会话是否在 |
| 主控提示消息被 hold / 待批准 | 主控启动时还没加载 `crossSessionInbound: accept`——带同样的 `--name` 重启主控后重新调用 skill |
| 角色回 `BLOCKED: 待确认来源` | 桌面版主控的显示名可能与 `--name` 不同；主控回一句"该地址就是主控"即锚定 |
| 窗口没排好 | 布局失败不影响运行，手动摆即可；开窗几秒内别点其他 Terminal 窗口 |
| 首次运行没反应 | 看是否弹了 macOS「自动化」授权；被拒后到 系统设置 → 隐私与安全性 → 自动化 开启 |
| 角色长时间无回报 | 主控的看门狗会提醒；`/list-agents` 确认在线，看该窗口是否卡确认框；确认空闲后再让主控重发 |
| 新窗口提示找不到 `claude` | 新终端的登录 shell PATH 没有 claude；修好 `~/.zshrc` 后在该窗口按提示重跑 |

更多见 [docs/troubleshooting.md](docs/troubleshooting.md)。

---

## 与其他方案的关系

| | 本框架 | claude-agent-team（subagent） | Claude Code Agent Teams（实验性） | AWS CAO |
|---|---|---|---|---|
| 角色形态 | 独立会话、独立窗口 | 同会话 subagent | lead spawn 的 teammate（tmux 分屏） | 异构 CLI 的 tmux 会话 |
| 观察/介入 | 每个窗口随时可点进去 | 只见结果 | 可点 pane | tmux attach |
| 模型 | Claude 系（每角色可不同） | Claude 系 | Claude 系 | Claude/Codex/Kimi 等 |
| 依赖 | 原生跨会话消息 | 原生 subagent | 需开实验开关 | 第三方工具链 |

选择依据见 [docs/design-decisions.md](docs/design-decisions.md)。

## Roadmap
- 英文 README 与英文角色包（`ATC_LANG=en`）
- 插件市场分发（`/plugin marketplace add`，恢复 hook 随插件自动注册）
- Linux / WSL2 开窗后端（tmux 或 terminal emulator）
- executor 内调用 `codex exec` 等外部 CLI（异构模型）

## License
MIT
