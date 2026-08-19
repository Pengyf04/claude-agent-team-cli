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
- 团队令牌来源校验（launch 生成、主控每条消息携带、角色只认令牌）；角色回报只按主控名发一次；`restart-role.sh` 单角色重启；角色临时文件 mktemp 纪律；桌面版主控说明
- SKILL 重入检查（主控重启后续跑不重复提问）、git init 前征得用户同意并拒绝危险目录、窗口 ID 按 tty 精确识别、主控不在 Terminal.app 时不移动已有窗口
- 文档：README（macOS only 置顶）、architecture、design-decisions、troubleshooting、manual-e2e-checklist、HANDOFF；examples/pomodoro-cli 真实运行记录
- 所有 `osascript` 调用经 `osa` 超时包装器（`ATC_OSA_TIMEOUT`，默认 8 秒）：headless 环境（CI runner / SSH / 锁屏 / 自动化授权未决）下 osascript 会无限阻塞而非报错，原有失败兜底永远走不到，会导致 `launch-team.sh` 与 `doctor.sh` 无提示卡死
- 测试：新增 osascript 阻塞回归（伪造阻塞型 osascript 验证不挂死）、Markdown 内部链接完整性、`ATC_*` 配置项与 README/doctor.sh 的同步校验；shellcheck 扩展到覆盖 `tests/run.sh` 自身；泄漏扫描改为只查已入库文件；测试末尾声明未覆盖范围，避免绿灯被误读为全覆盖
- 修复 UTF-8 locale 下脚本报 `unbound variable` 而无法运行：中文提示中 `$VAR` 紧挨中文字符时，bash 会把中文的高位字节并入变量名（C locale 不触发，故本地长期未暴露）。全部 30 处改为 `${VAR}`，并加入 lint 检查与 `LC_ALL=en_US.UTF-8` 下的 CI 验证
- 团队令牌生成改用 `od -N 32` 有界读取：原 `tr -dc ... </dev/urandom | head -c 8` 依赖 SIGPIPE 杀死 `tr`，而 SIGPIPE 被忽略时（`SIG_IGN` 会被子进程继承）`tr` 会无限空转，命令替换永远不返回
- `tests/run.sh` 自带看门狗（`TEST_TIMEOUT`，默认 600 秒）：超时打印最后进入的检查点后中止，让作业正常失败而非被强制取消（被取消时缓冲日志会丢失，挂死点无从定位）
- 修复后台进程继承 stdout 导致 CI 步骤永不结束：`kill -9` 杀不掉子 shell 底下的 `sleep`，孤儿会继续持有 runner 的输出管道
- CI：macOS 矩阵（macos-14 / macos-latest）、最小权限 `contents: read`、并发取消陈旧运行、`timeout-minutes` 上限、action 钉 commit SHA、`test` 汇总门禁作业（分支保护只需盯一个稳定检查名）
- 新增 `release.yml`（打 tag 触发，测试通过才建 Release）、`dependabot.yml`、PR 模板（内嵌自检清单）、issue 模板
