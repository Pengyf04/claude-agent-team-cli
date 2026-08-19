# 排障

先跑一遍自检：`bash ~/.claude/skills/agent-team-cli/scripts/doctor.sh <项目目录>`。

## 安装 / 环境

| 现象 | 处理 |
|---|---|
| `install.sh` 提示未找到 python3 | `xcode-select --install`；或按提示手动把那段 hook JSON 加进 `~/.claude/settings.json`；或 `./install.sh --no-hook` |
| `/list-agents` 不被识别 | Claude Code < 2.1.224，升级；或运行在 Bedrock / Vertex / Foundry（不支持）；或设置了 `DISABLE_TELEMETRY` / `DO_NOT_TRACK` / `DISABLE_GROWTHBOOK` / `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 之一（关闭了功能开关评估） |
| 新窗口提示找不到 `claude` | 新 Terminal 的登录 shell PATH 没有 claude（常见于 nvm 等）；在 `~/.zshrc` 导出路径，然后在该窗口按提示重跑 runner |
| 首次运行没开窗 / 报 osascript 错误 | macOS 自动化授权被拒：系统设置 → 隐私与安全性 → 自动化 → 允许控制 Terminal；主控执行 launch 脚本需以非沙箱方式运行 Bash |

## 启动 / 握手

| 现象 | 处理 |
|---|---|
| READY 收不齐 | 去对应窗口看是否卡在「文件夹信任」/「Bypass Permissions 警告」确认框；`/list-agents` 看会话是否在；主控可 SendMessage ping 一次 |
| 主控收到消息被 hold / 弹批准框 | **主控自身权限模式不是 bypassPermissions**（普通/auto 模式收不到 bypass 角色的消息）。带同样 `--name` 加上 `--permission-mode bypassPermissions` 重启主控并重新调用 skill，重入检查会续跑并让角色重发 READY。⚠️ 项目级 `crossSessionInbound: accept` 在 auto 模式下**实测未生效**（见 design-decisions #6），不要指望它兜底 |
| `ListAgents` 里角色出现两份 | 旧团队没关：手动关旧窗口或跑 `shutdown-team.sh`；角色名带 slug 后缀可从根上避免 |
| launch 脚本报"旧团队窗口仍在运行" | 记录的窗口还开着，先关；若窗口已关，脚本会自动清理陈旧记录 |
| 窗口没按田字格排好 | 布局失败不影响运行；开窗几秒内不要点其他 Terminal 窗口；外接屏聚焦时用主屏 |

## 运行中

| 现象 | 处理 |
|---|---|
| 角色回 `BLOCKED: 消息未含团队令牌` | 主控漏带 `令牌: <值>` 行；补发完整指令。令牌在项目 `.claude/agent-team-cli/token` |
| 某角色的回报一直收不到、其他角色正常 | 该角色多半曾向 socket 地址发过消息，此后其消息持续被扣：`restart-role.sh <项目> <角色>`（非沙箱）重启它；已产出的文件照用 |
| 角色窗口弹 "Dangerous rm operation… proceed?" | 选 No；主控让角色改用 `mktemp -d`。bypass 模式也不跳过此类硬检查 |
| 桌面版主控收不到角色消息且没有批准框 | 决定因素是**主控自身权限模式**（不限桌面版，命令行 auto 模式主控实测同样被扣）：把主控会话权限模式设为 bypassPermissions。桌面版另有"不显示批准框"这一点，问题更隐蔽 |
| shutdown/restart 脚本"关不掉"窗口、Terminal 弹终止确认 | 主控在沙箱内运行了脚本（杀不掉进程）：以非沙箱方式重跑；已弹的确认框手动点"终止" |
| 角色长时间无回报 | 主控看门狗到点会提示；`/list-agents` 确认在线 → 目视窗口是否卡确认框/仍在工作 → 确认空闲后让主控重发（换措辞，系统会丢弃短时间内完全相同的重复消息） |
| 角色回报没有结构化标记 | 主控让它重发一条只含标记的确认 |
| 角色说命令被拦截/改写 | 多半是用户全局配置（hooks、命令代理类工具）所致，属环境现象；记入风险，按环境绕行 |
| 主控好像"忘了"进行到哪 | 看 `runs/<slug>/state.md`；SessionStart hook 会在压缩后自动注入；也可手动让主控重读 SKILL 与 state.md |
| 循环打转 | 有硬上限（规划环 5、执行验证环 8、终验回退 2），超限主控会停下升级给你 |

## 收尾

| 现象 | 处理 |
|---|---|
| 想关 4 个窗口 | `bash ~/.claude/skills/agent-team-cli/scripts/shutdown-team.sh <项目>`；或手动关（下次启动脚本会自动清理陈旧记录） |
| 项目不再跑团队 | 移除 `crossSessionInbound` 键：`scripts/ensure-inbound.sh <项目> --remove`（只摘该键、保留文件其余内容；P5 也会问你） |
| 任务中途放弃后，每次开会话都被注入"存在进行中的 Agent Team 任务" | `shutdown-team.sh <项目> --abandon <slug>`（把 state.md 阶段标为已放弃完成），或删 `runs/<slug>/` |
| 升级 | `git pull && ./install.sh`；`--link` 模式无需重装 |
