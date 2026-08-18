# 设计决策（为什么是这样）

本文提炼自框架搭建前的两轮调研（多 CLI 协作方案调研、AWS CAO 部署专项调研）与一次完整端到端实测，只保留结论与依据；时效以 2026-08 为准，生态迭代很快。

## 1. 为什么用"独立会话 + 跨会话消息"，而不是同会话 subagent

subagent 共享主会话上下文、只能向主会话回报、过程不可见。本框架的诉求是：角色**各自独立上下文**、**各自窗口可观察可介入**、角色之间能多轮循环。Claude Code v2.1.224+ 的跨会话消息（`ListAgents` / `SendMessage`）正好提供了独立会话间的消息与**空闲自动唤醒**，且是官方机制、零安装。

## 2. 为什么不用 Claude Code 实验性 Agent Teams

Agent Teams（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`）自动化程度更高（共享任务列表、空闲通知、计划审批），但：teammate 运行在 tmux/iTerm2 分屏而非真正独立窗口；模型/fast 在 spawn 时固定、不能事后在窗口内调整；处于实验阶段、行为随小版本变化；`/resume` 不恢复 in-process teammate。用户明确要"真实独立窗口 + 每窗口可手动确认配置"，独立会话形态更贴合，也更稳定。Agent Teams 值得作为后续可选形态。

## 3. 为什么不用 AWS CLI Agent Orchestrator（CAO）

CAO 是最接近的现成方案（supervisor/worker、tmux 会话、支持 Claude Code / Codex / Kimi 等异构 CLI），但其驱动方式是"抓取 tmux 屏幕文字 + 注入按键"，导致：provider CLI 升级会静默弄坏它（历史 issue 反复出现）、长任务 handoff 结果可能在 MCP 超时后丢失（当时仍 open）、所有 provider 一律 `--yolo`。而原生跨会话消息走结构化邮箱/socket，没有这些脆弱点。代价是本框架**仅限 Claude 系模型**——异构模型（如 executor 内调 `codex exec`）列入 roadmap。当"每个子 Agent 必须是各家 CLI 的原生界面"是硬需求时，CAO 仍是合理选择。

## 4. 为什么角色之间不直接通信

技术上 SendMessage 允许角色互发。但主控中心化转交能保证：主控始终掌握全局状态与轮次计数、所有需人拍板的事项有唯一出口、循环上限可强制。这也与 claude-agent-team 的既有纪律一致，迁移成本最低。

## 5. 为什么默认 `bypassPermissions` + 强制 git

执行 ⇄ 验证多轮循环要全自动，角色不能停下等用户在 4 个窗口逐个批准。兜底选 git（框架强制项目为 git 仓库）而非沙箱，是因为简单、通用、可回滚。可用 `ATC_PERMISSION_MODE` 收紧。

## 6. 为什么 `crossSessionInbound: accept` 写在项目级 `settings.local.json`

Claude Code 默认规则：普通模式会话收到 bypass 会话的消息会**扣住等用户批准**（安全闸）；主控普通模式 + 角色 bypass 恰好双向被扣，全自动断掉，因此必须显式 `accept`。写项目级（只影响本项目）且用 `settings.local.json`（不进 git，不把"无门禁收消息"发布给团队其他人）。

## 7. 为什么消息只传信号、内容走文件

跨会话消息只有纯文本、有长度与频率限制、且不保证被完整引用；文件是唯一可靠的跨角色真源，也让上下文压缩后能重建状态。这条纪律直接继承自 claude-agent-team。

## 8. 为什么需要 SessionStart 恢复 hook

主控的"压缩后先重读 SKILL 与 state.md"这条规则本身活在会被压缩的上下文里。用户级 SessionStart hook（startup / resume / compact 触发）把 state.md 与恢复指引由系统硬注入，恢复从"靠自觉"变为"确定性"。hook 有保护：项目里没有未完成的 state.md 就静默。

## 9. 为什么角色来源校验是"双通道"

实测发现桌面版 Claude Code 主控的显示名可能与 `--name` 注册名不同，纯"名字匹配"会误伤（角色拒绝合法派活）。改为"名字匹配 或 首次 READY 握手锚定的地址（TOFU）"，兼顾防伪装与顺畅。

## 10. 为什么先做手动分发而非插件

手动路线（`git clone` + `install.sh`）路径稳定、无需解决插件内脚本路径定位问题，两条命令与插件相当；仓库结构保持插件兼容，插件轨可后加。hook 合并用 python3：能 `git clone` 的 Mac 必有 Command Line Tools，也就必有 python3。

## 11. 已知取舍
- macOS only（AppleScript + Terminal.app）；Linux/WSL2 需要开窗后端。
- 主控没有真正的"超时"（空闲会话不会自己醒），用后台 `sleep` 看门狗唤醒代替。
- Fast 模式无启动 flag 且仅 Opus 支持，需手动 `/fast`。
- 中文角色 prompt ⇒ 角色用中文工作。
