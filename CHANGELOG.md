# Changelog

本项目遵循语义化版本。

## [Unreleased]
### 新增
- **支持 Claude Code 桌面版客户端作主控**（已完整端到端实测）。三个前置条件由框架自动检查、不再靠人记：① inbound 只能用**用户级** `~/.claude/settings.json` 的 `crossSessionInbound: accept`（桌面版不能 `--settings`）；② 注册名用**斜杠命令** `/rename` 固定——客户端另有同名弹窗入口只改对话标题、不改注册名，是陷阱；③ CLI 需已登录（凭据与客户端各自独立）
- `doctor.sh` 新增三类硬检查：CLI 登录状态、主控 inbound 通路（区分终端/桌面）、主控注册名（保留字 `main` 判为阻断、派生名给出固定建议）。自身会话检测改为**上溯进程树**，不再硬依赖父进程号（隔一层 shell 就会落空）
- `session-recover.sh` 把主控名从"提醒用户自查"升级为**主动比对并报警**，附带可直接执行的 `/rename` 命令
- SKILL 重入检查新增两步：先核对注册名（不一致则停下要求先改回，不带错名字往下走）；恢复后**主动向正在等待的角色补要一次回报**（角色协议规定"回报只发一次"，不补要就会一直空等）

### 修复
- **`shutdown-team.sh` 谎报关窗成功**：取窗口 tty 失败时静默跳过杀进程，关窗失败也被吞掉，却照样打印"已关闭"。现在 tty 取不到时按会话名兜底结束进程、关窗后**回查窗口是否真的关了**、有残留则如实告警并保留 `windows.txt` 便于重试、以非零码退出
- **项目级 `crossSessionInbound: accept` 是结构性空操作，已彻底移除相关逻辑**。该键的项目级来源（`localSettings`/`projectSettings`）只在取值比当前更严格时才被采纳，而 `accept` 是最宽松的一档（accept<hold<refuse），比较基准在无人设置时也是 `accept`，因此永远不满足「更严格」——写进 `.claude/settings.local.json` 从第一天起就没生效过。框架历次跑通靠的全是「双方权限模式同类」（主控恰好也在 bypass），不是这个配置。已通过读取实现 + 双组对照实验实证（除 `--settings` 外一切相同：无参数组被扣 `mode-mismatch`，带参数组直达）
- 主控改用 `--settings '{"crossSessionInbound":"accept"}'` 启动（属 `flagSettings`，取到即用、只作用于本会话）。**主控不再需要跑 `bypassPermissions`**——此前为了让框架能用而要求主控跳过全部权限检查，是把问题转嫁成用户的安全等级降低
- 角色 runner 一直就是用 `--settings` 传的，**角色侧从未受影响**

### 变更
- `ensure-inbound.sh` → **改名 `prepare-project.sh`**，只保留「把运行时产物写入 `.git/info/exclude`」这一个仍然有效的职责；删除 inbound 写入逻辑与昨日新增的 `--remove`（移除一个从未生效的键没有意义）
- SKILL 删除 P1「消息通路配置」与 P5「问是否移除该键」两个步骤；P0 自检改为检查是否带了 `--settings`
- `doctor.sh` 不再检查项目级该键是否存在（检查一个无效配置会给出虚假安全感），改为直接提示主控该带的启动参数
- README / architecture / troubleshooting / manual-e2e-checklist / examples 同步更正
- `design-decisions` 第 6 条用实证结论重写（含实现细节与对照实验数据）

### 测试
- 新增：`prepare-project.sh` 幂等性、不碰用户 settings、非 git 目录静默跳过、**脚本自身不得再含 inbound 写入逻辑**
- 新增文档 lint：文档不得再引导用户执行已废弃的 `ensure-inbound.sh`（只查调用写法，保留 CHANGELOG 等处的叙述性提及）

## [0.1.0] - 2026-08-19
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
- `restart-role.sh` 的全部 `osascript` 调用补上超时包装（含把开窗的 heredoc 改写为临时文件调用）：它是「角色坏掉时的救援工具」，实测原先在阻塞型 osascript 下会永久挂死；超时后报错退出且不会把空窗口 id 写进 `windows.txt`
- `ensure-inbound.sh` 新增 `--remove`：收尾时**只摘掉 `crossSessionInbound` 一个键**并保留文件其余内容，仅当再无其他键时才删除整个文件（此前 P5 收尾会删掉整个 `settings.local.json`，可能连带抹掉用户自己的项目配置）；SKILL P5 改为调用该脚本，禁止手工编辑该 JSON
- 角色协议新增「交付前清理临时产物」：`deliverable/` 只应包含交付物本身，`__pycache__` / `.pytest_cache` 等缓存回报前删除（删除用精确路径，禁止对 `runs/` 用通配符 `rm`）
- README 快速开始改为教已验证配置 `claude --name atc-main --permission-mode bypassPermissions`，并说明两个参数各自解决哪个会导致团队卡死的问题；SKILL P0 增加主控权限模式自检
- `shutdown-team.sh` 关团队时一并作废团队令牌：令牌需能区分团队世代，否则侥幸存活的旧角色窗口仍能接受新团队指令——正好是它要防的场景
- 关团队后若仍有进行中的 `state.md`，`shutdown-team.sh` 明确提示孤儿状态并给出可直接执行的 `--abandon` 命令（不自动放弃：中途重启角色时自动放弃会误伤）
- `session-recover.sh` 增加团队活体校验：注入时报告窗口记录与在册角色会话；若任务标记进行中却无任何角色在册，明确警告不得直接续跑，并提醒核对 `state.md` 里记录的主控名是否已作废。校验只读文件与会话注册表，绝不调 `osascript`（该 hook 在任意项目启动时都会跑）
- `shutdown-team.sh` 的 `osascript` 调用补上超时包装器（此前只有 launch-team.sh 与 doctor.sh 有）
- **修复主控名为 `main` 时团队必然卡死在握手**：`main` 是 SendMessage 的保留收件人，角色按名字回报会被拦截且无任何绕过（ListAgents 给的 ref、系统建议的 ref、sessionId 均不可达）。`launch-team.sh` 现在在开窗前就拒绝该名字（大小写不敏感）并给出改名指引；默认主控名改为 `atc-main`；README / SKILL / 示例 / 回归清单同步；新增用例与文档 lint（防止脚本已拒绝而文档仍在教用户踩坑）
- 更正文档中一处已被实测推翻的设计论证：`design-decisions` 第 6 条原称「写了项目级 `crossSessionInbound: accept` 即可让普通模式主控收到 bypass 角色的消息」，2026-08-19 E2E 实测该配置在位却未生效，消息仍被扣住。现如实记录实测结果、两个竞争假设、当前唯一验证过的配置（主控也跑 bypass）及其代价（主控安全等级被迫降低，这是待办而非已解决的设计）；`troubleshooting` / `architecture` / README 桌面版章节 / 人工回归清单同步更正
- 修正 SKILL 中「权限类别扣留是桌面版专属」的错误表述：实际取决于主控自身权限模式，命令行 auto 模式主控同样被扣
- 角色协议里作为“主控”简称的 `main` 改写为「主控」，避免角色误按字面名字发送
- 修复 UTF-8 locale 下脚本报 `unbound variable` 而无法运行：中文提示中 `$VAR` 紧挨中文字符时，bash 会把中文的高位字节并入变量名（C locale 不触发，故本地长期未暴露）。全部 30 处改为 `${VAR}`，并加入 lint 检查与 `LC_ALL=en_US.UTF-8` 下的 CI 验证
- 团队令牌生成改用 `od -N 32` 有界读取：原 `tr -dc ... </dev/urandom | head -c 8` 依赖 SIGPIPE 杀死 `tr`，而 SIGPIPE 被忽略时（`SIG_IGN` 会被子进程继承）`tr` 会无限空转，命令替换永远不返回
- `tests/run.sh` 自带看门狗（`TEST_TIMEOUT`，默认 600 秒）：超时打印最后进入的检查点后中止，让作业正常失败而非被强制取消（被取消时缓冲日志会丢失，挂死点无从定位）
- 修复后台进程继承 stdout 导致 CI 步骤永不结束：`kill -9` 杀不掉子 shell 底下的 `sleep`，孤儿会继续持有 runner 的输出管道
- CI：macOS 矩阵（macos-14 / macos-latest）、最小权限 `contents: read`、并发取消陈旧运行、`timeout-minutes` 上限、action 钉 commit SHA、`test` 汇总门禁作业（分支保护只需盯一个稳定检查名）
- 新增 `release.yml`（打 tag 触发，测试通过才建 Release）、`dependabot.yml`、PR 模板（内嵌自检清单）、issue 模板
