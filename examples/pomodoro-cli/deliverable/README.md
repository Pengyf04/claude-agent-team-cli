# 交付说明：pomodoro-cli（模式 A 首次实现）

## 交付物

| 文件 | 说明 |
|---|---|
| `pomodoro.py` | 主程序，单文件，仅标准库（argparse / sys / time） |
| `test_pomodoro.py` | pytest 用例，只测纯函数，无任何 sleep，14 个用例 0.02s 跑完 |

## 做了什么（对应 plan）

- **plan 2.2 函数契约**：`format_time` / `minutes_to_seconds` / `build_parser` / `parse_args` / `countdown` / `notify` / `run` / `main` 全部按签名与伪代码实现。`--break` 用 `dest="break_minutes"`；三个参数用自定义 type（`positive_float` / `positive_int`）校验 >0，非法值走 argparse 标准报错、退出码 2。
- **plan 2.2 run 逻辑**：最后一个周期后不休息（`i < cycles`）；工作阶段跑完即 `completed += 1`；`KeyboardInterrupt` 只在 `run` 内捕获，打印「已中断，已完成 X 个完整周期。」；`main` 只做 `parse_args + run + return 0`，不做异常处理。
- **plan 2.3 实现步骤**：按序创建目录 → 纯函数 → 计时/交互函数 → 测试 → 自测 AC1–AC7。
- **plan 2.4 测试用例**：参数解析类 3 个（`test_defaults` / `test_custom_values` / `test_invalid_rejected`），时间格式化类 2 个（`test_format_time_basic` 7 组参数化、`test_minutes_to_seconds` 4 组参数化），共 14 个 test item，均通过。
- **plan G1–G7 / 5. AC1–AC7**：均已本地自测，结果见下。

## 自测结果

| AC | 命令 | 结果 |
|---|---|---|
| AC1 | `python3 pomodoro.py --work 0.05 --break 0.02 --cycles 2` | 退出码 0，耗时 7s（区间 6–14s），输出含「全部完成」「2 个周期」 |
| AC2 | 同上输出 | 原始字节含 7 个 `\r`；正则 `\[工作\] 周期 \d/\d 剩余 \d{2,}:\d{2}` 匹配 6 条；`[工作]` `[休息]` 均存在，倒计时形如 `00:03→00:01` |
| AC3 | 同上输出 | `\a`（0x07）出现 4 次；含「开始工作」「开始休息」「全部完成」 |
| AC4 | 后台启动 cycles=9，5s 后 SIGINT | 退出码 0，输出末尾「已中断，已完成 1 个完整周期。」（**注意启动方式，见下方风险 1**） |
| AC5 | `python3 pomodoro.py --help` | 退出码 0，显示 `--work (default: 25.0)`、`--break (default: 5.0)`、`--cycles (default: 4)` |
| AC6 | `python3 -m pytest -q` | `14 passed in 0.02s`（**见下方风险 2**） |
| AC7 | `grep -E "^(import\|from)" pomodoro.py` | 仅 `argparse` / `sys` / `time`，全为标准库；两个文件均在 `deliverable/` 下 |

## 已知遗留 / 风险

1. **AC4 的验证方式有坑（非程序缺陷）**：非交互 shell 用 `cmd &` 启动的后台任务，其 SIGINT 被 shell 设为 SIG_IGN 并被 Python 继承，`kill -INT` 不会触发 `KeyboardInterrupt`，程序会一路跑完 9 个周期。真实终端里按 Ctrl+C 不受影响。验证 AC4 请显式恢复默认处置：

   ```bash
   ( trap - INT; exec python3 pomodoro.py --work 0.05 --break 0.02 --cycles 9 > out.txt 2>&1 ) &
   PID=$!; sleep 5; kill -INT $PID; wait $PID; echo "exit=$?"; tail -1 out.txt
   ```

   用此方式实测：`exit=0`，末行「已中断，已完成 1 个完整周期。」。已按 plan 保持代码不覆盖继承来的 SIGINT 处置（符合 POSIX 惯例，不破坏 `nohup` 语义），未做防御性改动。

2. **pytest 环境（plan R1）**：本机 PATH 上的 `python3` 是 Homebrew Python 3.14，原先没有 pytest 且受 PEP 668 保护（`pip install pytest` 直接报错）。已按 plan R1 授权执行 `python3 -m pip install --user --break-system-packages pytest`（Homebrew 官方推荐的 `--user` 覆盖方式，装到 `~/Library/Python/3.14`，不动 Homebrew 自身）。现在 `python3 -m pytest -q` 与 `/usr/bin/python3 -m pytest -q` 均可跑通。若验证环境仍缺 pytest，可用 `/usr/bin/python3 -m pytest -q`（系统 Python 自带 pytest 8.4.2）。

3. **计时精度（plan R3）**：`sleep(1)` 递减不做漂移校正，长时间运行会比名义时长略慢，属 plan 已接受的取舍。
