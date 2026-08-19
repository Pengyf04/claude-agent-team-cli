# 发版前人工端到端回归清单

自动化测试（`tests/run.sh`）覆盖不了真实 Claude 会话与开窗；每次改动 SKILL.md / roles / launch 脚本后，发版前至少跑一遍本清单（约 20–40 分钟，用一个 10 分钟内能完成的小任务）。

## 准备
- [ ] `./install.sh --link` 后新开一个主控会话：`cd <空目录> && git init && claude --name atc-main --permission-mode bypassPermissions`（名字不能是 `main`——保留字；主控须为 bypass，否则收不到角色消息）
- [ ] `bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh` 无 ❌

## P0–P3
- [ ] `/agent-team-cli <小任务>` 被识别，主控进入目标对齐并索要验收标准
- [ ] 主控自身权限模式为 `bypassPermissions`（否则角色消息会被扣，团队卡死）
- [ ] P1：项目 `.claude/settings.local.json` 出现 `crossSessionInbound: accept`；`runs/<slug>/{task.md,state.md}` 生成
- [ ] P2：4 个 Terminal 窗口弹出、田字格布局、标题 `agent-team:<role>-<slug>`；`.claude/agent-team-cli/windows.txt` 有 5 行
- [ ] 各窗口模型/effort 与预设（或环境变量覆盖）一致
- [ ] 4 个 READY 到达主控且**未被 hold**；主控等用户回复「确认」（不自动通过）

## P4
- [ ] 规划环：planner `PLAN_READY` → reviewer `APPROVED`/`NEEDS_REVISION`，回报最后一行为单行标记
- [ ] 卡点 A 真的停下等用户
- [ ] 执行验证环：executor `EXECUTION_DONE` → verifier `PASS`/`FAIL`；FAIL 时 executor 模式 B 修复
- [ ] 终验 `FINAL_ACCEPT`；卡点 B 汇总含「⚠️ 风险与注意事项」并停下等用户
- [ ] 全程 `state.md` 随状态迁移更新；每次派活后有看门狗 `sleep` 后台任务

## 异常路径（抽 1–2 条）
- [ ] 故意让某角色卡住（例如不接受确认框）→ 看门狗到点主控提示用户
- [ ] 主控执行 `/compact`（或长任务自然压缩）→ 下一 turn 出现 `<agent-team-cli-recovery>` 注入且主控按 state.md 继续
- [ ] 手动关掉 4 个窗口后再次 `launch-team.sh` → 提示"陈旧记录已清理"并正常启动

## 收尾
- [ ] P5 询问是否关窗；`shutdown-team.sh` 能关窗并清理 runner
- [ ] `./uninstall.sh` 后 `~/.claude/settings.json` 中只少了我们那条 hook，其他内容不变
