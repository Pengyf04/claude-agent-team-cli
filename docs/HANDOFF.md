# 维护交接（给下一个维护会话）

> 本仓库由一次长会话从零建成并发布 v0.1.0。以下是继续维护所需的最少上下文。

## 项目是什么
Claude Code 的多会话 Agent Team 编排 skill：主控开 4 个 Terminal 窗口启动 planner / plan-reviewer / executor / verifier 独立会话，用原生跨会话消息驱动状态机。详见 [README](../README.md)、[architecture](architecture.md)、[design-decisions](design-decisions.md)。

## 唯一真源与本机安装关系
- 仓库 `skills/agent-team-cli/` 是唯一真源。
- 维护者本机 `~/.claude/skills/agent-team-cli` 是指向仓库该目录的**符号链接**（`./install.sh --link`），仓库改动即时生效；**不要**在本机再装插件版（同名冲突 + hook 双触发）。
- 维护者本机 `~/.claude/settings.json` 已注册 SessionStart hook → `~/.claude/skills/agent-team-cli/scripts/session-recover.sh`（经符号链接生效）。

## 改动流程（见 CLAUDE.md）
1. 改 SKILL / roles / scripts → `tests/run.sh` 必须全绿
2. 涉及 SKILL / roles / launch 的实质改动 → 按 `docs/manual-e2e-checklist.md` 人工回归一次
3. 更新 `CHANGELOG.md`；语义化版本；发版打 tag + GitHub Release

## 验证状态（截至 v0.1.0）
- 端到端实测通过（番茄钟任务，见 examples/）：开窗、READY 握手、规划环 2 轮、执行验证环 1 轮、终验、两个卡点、看门狗唤醒、闲置 2 天唤醒。
- 实测后新增/改动并已回归的：模型/权限参数化（DRY_RUN）、去 python3 的 hook 脚本（三场景）、install/uninstall（隔离 HOME 幂等/精确移除）、doctor、TOFU 双通道来源校验（改措辞）、slug 后缀命名（DRY_RUN）、陈旧记录自动清理（真实窗口场景）。
- 发布前做过一次"陌生人首次安装"视角的对抗性审查并修复。

## 已知限制 / Roadmap
macOS only；仅 Claude 系模型；Fast 需手动；中文 prompt。Roadmap：英文包、插件分发、Linux/WSL2 后端、executor 调 codex exec。

## 曾踩过的坑（别再踩）
- AppleScript 里 `STOP` 等是保留字，布局脚本变量不能这么命名。
- 桌面版主控的显示名 ≠ `--name`，角色来源校验必须有 TOFU 通道。
- 短时间内重发一模一样的消息会被系统去重丢弃，重发要换措辞。
- SendMessage 目标不在"本会话"时要用 `名字 [ref]` 形式。
- 主控空闲不会自己醒：任何"超时"都必须靠后台 `sleep` 看门狗。
- 不要在 `/goal` 等自动续跑模式下运行 skill——人工卡点会被反复催促（SKILL 已加固：绝不替用户放行）。

## 待办：首次发布 v0.1.0（本地已提交，尚未推到 GitHub）
由新维护会话执行，执行前与用户确认：
```bash
cd ~/Claude_Code/claude-agent-team-cli
bash tests/run.sh                                     # 必须全绿
gh repo create Pengyf04/claude-agent-team-cli --public --source=. --remote=origin --description "多窗口多会话的 Claude Code Agent Team 编排框架" --push
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md
```
发布后：在一个干净目录按 README 从零 `git clone` + `./install.sh` 验证一次；README 顶部可加 CI 徽章。
