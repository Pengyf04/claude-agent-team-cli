## 改动内容


## 自检清单

- [ ] `bash tests/run.sh` 本地全绿
- [ ] `shellcheck -S warning install.sh uninstall.sh tests/run.sh skills/agent-team-cli/scripts/*.sh` 无告警
- [ ] 若改了 `SKILL.md` / `roles/` / `launch-team.sh` 的实质逻辑 → 已按 `docs/manual-e2e-checklist.md` 人工回归
- [ ] 若新增用户可配置项 → 已同步 README 参数表与 `doctor.sh` 输出（`tests/run.sh` 会自动校验）
- [ ] 已更新 `CHANGELOG.md`
- [ ] 未削弱以下任何一条不可退让的约束：
  - [ ] 人工卡点绝不自动通过
  - [ ] 角色只与主控通信
  - [ ] 消息来源校验（团队令牌）
  - [ ] 循环硬上限
  - [ ] 消息只传信号、内容走文件

## 人工回归结果（若适用）

