# 验证报告：pomodoro-cli

## 第 1 轮验证

- 验证时间：2026-08-15
- 验证环境：macOS (Darwin 23.6.0)，PATH python3 = Homebrew Python 3.14.6（/opt/homebrew/bin/python3），系统 /usr/bin/python3 = 3.9.6（自带 pytest 8.4.2）
- 验证对象：`deliverable/pomodoro.py`、`deliverable/test_pomodoro.py`（对照 plan.md 第 5 节 AC1–AC7）
- 所有命令均在 `runs/pomodoro-cli/deliverable/` 下**实际运行**，非静态审查

| # | 验证项 | 方法 | 期望 | 实际 | 结论 |
|---|--------|------|------|------|------|
| AC1 | 完整跑完 | `python3 pomodoro.py --work 0.05 --break 0.02 --cycles 2`，date 计时 | 退出码 0；耗时 6–14s；含「全部完成」「2 个周期」 | 退出码 0；耗时 8s；两个子串均存在 | ✅ 通过 |
| AC2 | 每秒刷新 | AC1 输出按 `\r` 拆分 + 正则 `\[工作\] 周期 \d/\d 剩余 \d{2,}:\d{2}` | 匹配 ≥5 条；`[工作]`/`[休息]` 均存在；`00:0\d` 递减 | 匹配 6 条；两阶段均存在；倒计时序列 00:03→00:02→00:01（两轮工作）、00:01（休息），单调递减 | ✅ 通过 |
| AC3 | 响铃+中文提示 | AC1 输出按字节统计 `\a`(0x07) + 子串检查 | `\a` ≥4 次；含「开始工作」「开始休息」「全部完成」 | `\a` 恰 4 次（2 工作开始+1 休息开始+1 全部完成）；三类提示均存在 | ✅ 通过 |
| AC4 | Ctrl+C 优雅退出 | `( trap - INT; exec python3 pomodoro.py --work 0.05 --break 0.02 --cycles 9 >out 2>&1 ) &`，5s 后 `kill -INT`，`wait` 取退出码 | 退出码 0；输出含「已完成」「1 个完整周期」 | 退出码 0；末行「已中断，已完成 1 个完整周期。」；中断落在工作2 中段（末条刷新为 `[工作] 周期 2/9 剩余 00:03`），与 plan 时间线一致 | ✅ 通过 |
| AC5 | 帮助信息 | `python3 pomodoro.py --help` | 退出码 0；含 --work/--break/--cycles 与默认值（25.0/5.0/4 均可） | 退出码 0；显示 `(default: 25.0)`、`(default: 5.0)`、`(default: 4)`，中文描述完整 | ✅ 通过 |
| AC6 | pytest 全过 | deliverable/ 下运行 pytest（两个解释器交叉验证） | 0 failed；参数解析类 ≥3 用例、时间格式化类 ≥2 用例 | Homebrew 3.14（经 `rtk proxy python3 -m pytest -q`）：`14 passed in 0.03s`；`/usr/bin/python3 -m pytest -q`：`14 passed in 0.02s`。用例：参数解析 3 个（defaults/custom/invalid）、时间格式化 2 个（format_time 7 组参数化、minutes_to_seconds 4 组参数化） | ✅ 通过 |
| AC7 | 交付位置+仅标准库 | `ls` + `grep -E "^(import|from)" pomodoro.py` | 两文件均在 deliverable/；import 仅标准库 | 两文件均在位；import 仅 argparse/sys/time，全为标准库 | ✅ 通过 |
| B1 | 边界：非法参数 | `--cycles 0`、`--work -1`、`--break 0`、`--work abc`、未知参数 `--bogus` | argparse 标准报错，退出码 2 | 五种情况退出码均为 2，报错信息为中文（如「argument --cycles: 必须大于 0，当前为 0」） | ✅ 通过 |

### 对 executor 两点转告的独立核实

1. **SIGINT/SIG_IGN 说法：属实**。实测普通 `cmd &` 后台启动后 `kill -INT`，进程存活并继续运行（SIGINT 被非交互 shell 置为 SIG_IGN 并被 Python 继承）——确系测试方式问题，非程序缺陷。正式判定采用 `trap - INT` 恢复默认处置的方式，结果如 AC4 行。
2. **pytest 环境说法：属实，另发现一处与交付物无关的环境现象**。裸跑 `python3 -m pytest` 在本验证会话中被 rtk 工具拦截报错（`rtk: Failed to spawn process`），这是验证环境的 rtk wrapper 问题；经 `rtk proxy` 绕过后 Homebrew 3.14 的 pytest 正常（14 passed），`/usr/bin/python3` 自带 pytest 8.4.2 亦正常（14 passed）。**不影响 AC6 判定**。

### 附注：派活消息来源核实（通信纪律记录）

本轮派活消息 from 显示为 `<main-socket>`（from-name「main」），与启动指令告知的主控名「main」字面不符；经 ListAgents 核查，原「main [f05596]」注册项已不可达（曾于就绪回报时成功送达），判断为主控会话注册名变更为会话标题所致，且消息内容（run slug、executor 细节、协议格式）与主控上下文完全吻合，故按主控指令执行。如非主控本人所发请指正。

### Bug / 未达项清单（回退给执行者）

（无——AC1–AC7 及边界用例全部通过）

判定：PASS
