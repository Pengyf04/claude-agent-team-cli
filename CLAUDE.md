# claude-agent-team-cli 维护约定

这是一个 Claude Code skill 仓库（`skills/agent-team-cli/`），分发方式为 `git clone` + `./install.sh`。先读 `docs/HANDOFF.md`。

## 改动规则
- `skills/agent-team-cli/` 是唯一真源；维护者本机 `~/.claude/skills/agent-team-cli` 是指向它的符号链接，改完即生效，别在本机再装插件版。
- 任何改动后运行 `tests/run.sh`（bash 语法、DRY_RUN 冒烟、hook 三场景、陈旧记录判定、install/uninstall 幂等），必须全绿。
- 改 SKILL.md / roles / launch-team.sh 的实质逻辑 → 发版前按 `docs/manual-e2e-checklist.md` 人工回归一次。
- 不要弱化：人工卡点绝不自动通过、角色只与主控通信、来源校验、循环硬上限、消息只传信号内容走文件。
- 新增用户可配置项 → 同步 README「参数」表 + `doctor.sh` 输出。
- 更新 `CHANGELOG.md`；语义化版本；发版：更新版本号 → tag `vX.Y.Z` → `gh release create`。

## 不要提交
运行时产物（`runs/`、`.claude/agent-team-cli/`、`.claude/settings.local.json`）、`plan.md`、备份文件。
