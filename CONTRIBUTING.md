# 贡献指南

- 提 issue 请附：macOS 版本、`claude --version`、`bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh` 输出、复现步骤。
- 改动 `skills/agent-team-cli/` 下任何文件前，先读 `docs/architecture.md` 与 `docs/design-decisions.md`。
- 提 PR 前：`tests/run.sh` 全绿；涉及 SKILL / roles / launch 的实质改动请按 `docs/manual-e2e-checklist.md` 人工回归并在 PR 中注明结果；更新 `CHANGELOG.md`。
## 本地验证（提 PR 前必做）

```bash
bash tests/run.sh
shellcheck -S warning install.sh uninstall.sh tests/run.sh skills/agent-team-cli/scripts/*.sh
```

CI 在 macOS 矩阵（macos-14 / macos-latest）上跑同样两条命令。分支保护要求名为 `test` 的
汇总检查通过才能合并——它汇总所有矩阵作业的结果。

自动化测试**不覆盖**真实开窗、READY 握手、角色状态机流转（需要 GUI 与真实 Claude 会话），
这部分走 `docs/manual-e2e-checklist.md` 人工回归。测试末尾会打印这条提示，别把绿灯读成全覆盖。

无图形界面的环境下 `osascript` 会无限阻塞而非报错，脚本内所有 osascript 调用都带超时
（`ATC_OSA_TIMEOUT`，默认 8 秒）。`tests/run.sh` 有专门的回归用例伪造阻塞型 `osascript` 来守住这条。

- 保持角色协议中的硬约束（只与主控通信、来源校验、人工卡点不自动通过、循环上限）不被弱化；如需改动请在 PR 中说明理由。
