# 架构

## 组件

```
用户 ⇄ main（主控，用户自启的 Claude Code 会话，任意模型）
        │ launch-team.sh：AppleScript 开 4 个 Terminal.app 窗口（主屏均分）
        │ SendMessage 派活 ↓ ／ 结构化标记回报 ↑（Claude Code 跨会话消息，事件驱动唤醒）
        ├── planner        规划者：产出 plan；终验
        ├── plan-reviewer  规划评审者：对抗式挑战 plan
        ├── executor       执行者：按 plan 交付；修 bug
        └── verifier       验证者：设计用例验收；提 bug
文件协议：<项目>/runs/<slug>/{task.md, plan.md, review-log.md, deliverable/, verify-report.md, final-review.md, state.md}
角色之间不直接对话，一切经 main 转交（main 始终掌握全局）
```

| 文件 | 作用 |
|---|---|
| `skills/agent-team-cli/SKILL.md` | 主控编排 playbook：P0 目标对齐 → P1 环境准备 → P2 开窗 → P3 就绪确认（人工）→ P4 状态机 → P5 收尾，以及全程纪律 |
| `roles/*.md` | 角色 system prompt，经 `--append-system-prompt` 注入（因此不会被上下文压缩掉）；含通信协议、工作模式、结构化标记 |
| `scripts/launch-team.sh` | 生成每角色 runner 脚本（`claude --name/--model/--effort/--permission-mode/--settings/--append-system-prompt` + 待命指令）、AppleScript 开窗与布局、窗口 ID 逐个落盘、重复启动保护 |
| `scripts/shutdown-team.sh` | 按记录先结束窗口内进程再关窗，清理 runner |
| `scripts/session-recover.sh` | 用户级 SessionStart hook：项目内存在未完成 `runs/*/state.md` 时把内容与恢复指引注入会话（startup / resume / compact 触发）；其他情况静默 |
| `scripts/ensure-inbound.sh` | 安全 merge `crossSessionInbound: accept` 进项目 `.claude/settings.local.json`（幂等）+ 运行时产物写入 `.git/info/exclude`；用户可在启动主控前手动跑，SKILL P1 也会调用 |
| `scripts/doctor.sh` | 只读自检 |

## 状态机（继承自 claude-agent-team）

```
[1] 规划环（≤5 轮）: planner(模式A) → PLAN_READY → plan-reviewer → APPROVED | NEEDS_REVISION(回 planner)
🔴 卡点 A: plan 定稿给用户确认
[2] 执行验证环（≤8 轮）: executor(模式A) → EXECUTION_DONE → verifier → PASS | FAIL(→ executor 模式B 修复 → verifier …)
[3] 终验（回退 ≤2 次）: planner(模式B) → FINAL_ACCEPT | FINAL_REJECT(写 final-review.md → executor 模式B → 回 [2])
🔴 卡点 B: 交付物 + 验证结论 + 终验结论 + 风险给用户终审
任意角色任意时刻可回 BLOCKED: <需人拍板的点> → main 与用户对齐后统一分发
```

## 通信协议

- **寻址**：按会话名（`claude --name`）；多项目并行时角色名带 slug 后缀。角色回报时以来信的 `from` 地址为准，不依赖主控名。
- **来源校验（双通道）**：角色只执行 (a) `from-name` 等于启动时告知的主控名，或 (b) `from` 地址等于首次 READY 握手成功送达的地址（TOFU 锚定）的消息；其他来源不执行、上报主控。
- **消息 = 信号，文件 = 内容**：回报正文 ≤10 行，最后一行**单行**结构化标记；详情落 `runs/<slug>/`。
- **派活模板**：模式 + 工作区路径 + 要读的文件 + "完成后回报 <主控名>，最后一行标记"。
- **唤醒**：空闲会话收到消息即开新 turn（官方机制）；主控每次派活后起后台 `sleep` 看门狗，到点若无回报则提示用户目视窗口。

## 恢复机制

- 主控每次状态迁移**全量重写** `state.md`（固定 schema：skill 路径、主控名、slug、阶段、轮次、正在等待、下一步、待办决策、已收集风险）。
- SessionStart hook（`session-recover.sh`）在会话启动 / resume / 压缩后检测未完成的 state.md（首行含 `agent-team-cli/SKILL.md`、阶段非 `[P5] 完成`），注入 `<agent-team-cli-recovery>` 块：身份判断指引 + state.md 全文。
- 角色端协议在 system prompt 里，天然扛压缩；派活消息每次重给模式与路径。

## 运行时产物（均在用户项目内，不入本仓库）

- `runs/<slug>/…`
- `.claude/agent-team-cli/{windows.txt, run-*.sh}`（窗口记录与 runner，shutdown 或陈旧检测时清理）
- `.claude/settings.local.json` 中的 `crossSessionInbound: accept`
