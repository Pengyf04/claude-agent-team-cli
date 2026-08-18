# Changelog

本项目遵循语义化版本。

## [0.1.0] - 2026-08-18
### 首个公开版本
- `/agent-team-cli` skill：主控开 4 个 Terminal 窗口启动 planner / plan-reviewer / executor / verifier 独立会话，用 Claude Code 跨会话消息驱动「规划环 → 卡点A → 执行验证环 → 终验 → 卡点B」状态机；循环硬上限 5 / 8 / 2；两个人工卡点绝不自动通过
- 角色协议：只与主控通信、双通道来源校验（主控名匹配 或 首次握手锚定地址）、消息只传信号内容走文件、单行结构化标记
- `launch-team.sh`：预设 name/model/effort/权限、主屏均分布局、窗口 ID 逐个落盘、重复启动保护（陈旧记录自动清理）、slug 后缀命名、`ATC_MODEL_* / ATC_EFFORT_* / ATC_PERMISSION_MODE` 参数化、runner 内 claude 检测
- `shutdown-team.sh`：先结束进程再关窗并清理
- `session-recover.sh`：SessionStart（startup/resume/compact）恢复 hook，注入未完成任务的 state.md 与恢复指引
- `ensure-inbound.sh`（项目级 accept 配置安全合并）；`doctor.sh` 自检；`install.sh`（备份至 skills/ 之外、幂等、`--link`、`--no-hook`）/ `uninstall.sh`；`shutdown-team.sh --abandon <slug>`
- SKILL 重入检查（主控重启后续跑不重复提问）、git init 前征得用户同意并拒绝危险目录、窗口 ID 按 tty 精确识别、主控不在 Terminal.app 时不移动已有窗口
- 文档：README（macOS only 置顶）、architecture、design-decisions、troubleshooting、manual-e2e-checklist、HANDOFF；examples/pomodoro-cli 真实运行记录
