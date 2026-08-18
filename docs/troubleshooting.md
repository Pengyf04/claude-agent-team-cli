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
| 主控收到消息被 hold / 弹批准框 | 主控启动时未加载 `crossSessionInbound: accept`（P1 才写入）——带同样 `--name` 重启主控，重新调用 skill（会跳过已完成步骤） |
| `ListAgents` 里角色出现两份 | 旧团队没关：手动关旧窗口或跑 `shutdown-team.sh`；角色名带 slug 后缀可从根上避免 |
| launch 脚本报"旧团队窗口仍在运行" | 记录的窗口还开着，先关；若窗口已关，脚本会自动清理陈旧记录 |
| 窗口没按田字格排好 | 布局失败不影响运行；开窗几秒内不要点其他 Terminal 窗口；外接屏聚焦时用主屏 |

## 运行中

| 现象 | 处理 |
|---|---|
| 角色回 `BLOCKED: 待确认来源合法性` | 桌面版主控显示名与 `--name` 不同触发了来源校验；主控回一句"该地址就是主控"，角色即按 TOFU 锚定继续 |
| 角色长时间无回报 | 主控看门狗到点会提示；`/list-agents` 确认在线 → 目视窗口是否卡确认框/仍在工作 → 确认空闲后让主控重发（换措辞，系统会丢弃短时间内完全相同的重复消息） |
| 角色回报没有结构化标记 | 主控让它重发一条只含标记的确认 |
| 角色说命令被拦截/改写 | 多半是用户全局配置（hooks、命令代理类工具）所致，属环境现象；记入风险，按环境绕行 |
| 主控好像"忘了"进行到哪 | 看 `runs/<slug>/state.md`；SessionStart hook 会在压缩后自动注入；也可手动让主控重读 SKILL 与 state.md |
| 循环打转 | 有硬上限（规划环 5、执行验证环 8、终验回退 2），超限主控会停下升级给你 |

## 收尾

| 现象 | 处理 |
|---|---|
| 想关 4 个窗口 | `bash ~/.claude/skills/agent-team-cli/scripts/shutdown-team.sh <项目>`；或手动关（下次启动脚本会自动清理陈旧记录） |
| 项目不再跑团队 | 可移除 `.claude/settings.local.json` 里的 `crossSessionInbound` 键（P5 会问） |
