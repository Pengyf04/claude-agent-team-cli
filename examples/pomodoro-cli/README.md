# 示例：番茄钟 CLI（一次真实的端到端运行记录）

这是框架首次端到端实测留下的真实产物（已脱敏），展示 `/agent-team-cli` 一次完整运行会生成什么、各角色如何交接。

**任务**：用 Python 标准库实现命令行番茄钟 + pytest 测试（7 条可判定验收标准，见 [task.md](task.md)）。

## 这次运行的过程

| 阶段 | 发生了什么 | 产物 |
|---|---|---|
| 规划环 第 1 轮 | planner 产出方案 → plan-reviewer 对抗评审，挑出 3 处必改（验收判定词不一致、正则未转义、伪代码歧义）+ 2 条建议 → `NEEDS_REVISION` | [review-log.md](review-log.md) 第 1 轮 |
| 规划环 第 2 轮 | planner 逐条回应并修订（5 点全采纳，见 plan.md「修订记录」）→ plan-reviewer 复审 `APPROVED` | [plan.md](plan.md) |
| 🔴 卡点 A | 主控向用户播报 plan 摘要，用户确认 | — |
| 执行验证环 第 1 轮 | executor 交付 `pomodoro.py` + 14 个 pytest 用例 → verifier 实跑 7 条标准 + 5 组边界用例，全部通过 `PASS`（并独立核实了 executor 报告的两个环境注意点） | [deliverable/](deliverable/)、[verify-report.md](verify-report.md) |
| 终验 | planner 不采信 verifier 结论、独立复测关键路径 → `FINAL_ACCEPT` | — |
| 🔴 卡点 B | 主控汇总交付物、验证结论、风险，用户终审 | — |

统计：规划环 2/5 轮、执行验证环 1/8 轮、终验回退 0/2；全程约 1 小时（含人工确认等待）。

## 值得看的细节

- **对抗评审是真的在挑刺**：第 1 轮 reviewer 挑出的 3 处问题都会导致验收时假 FAIL 或执行歧义，不是走形式。
- **验证者独立核实执行者的说法**：executor 提到"后台 `&` 启动时 SIGINT 会被 shell 忽略，需用 `trap - INT` 子 shell 方式验证"，verifier 没有照单全收，而是实测确认属实后才采信。
- **风险上报链条**：executor 报告"用 `pip --user` 装了 pytest"这类环境副作用 → 主控在卡点 B 单列「⚠️ 风险与注意事项」呈报用户。

## 复现

```bash
mkdir demo && cd demo && git init
bash ~/.claude/skills/agent-team-cli/scripts/ensure-inbound.sh .
claude --name atc-main
# 会话内（把 task.md 的验收标准直接贴进去，或给出它在你机器上的绝对路径）：
/agent-team-cli 用 Python 标准库实现命令行番茄钟 pomodoro.py + pytest 测试。验收标准：<粘贴 task.md 中的 7 条>
```

> 注：verify-report.md / plan.md 里提到的 `rtk` / `rtk proxy` 是原作者本机的一个命令代理工具，与本框架无关；陌生环境不会遇到，可忽略。
