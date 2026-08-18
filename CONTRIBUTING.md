# 贡献指南

- 提 issue 请附：macOS 版本、`claude --version`、`bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh` 输出、复现步骤。
- 改动 `skills/agent-team-cli/` 下任何文件前，先读 `docs/architecture.md` 与 `docs/design-decisions.md`。
- 提 PR 前：`tests/run.sh` 全绿；涉及 SKILL / roles / launch 的实质改动请按 `docs/manual-e2e-checklist.md` 人工回归并在 PR 中注明结果；更新 `CHANGELOG.md`。
- 保持角色协议中的硬约束（只与主控通信、来源校验、人工卡点不自动通过、循环上限）不被弱化；如需改动请在 PR 中说明理由。
