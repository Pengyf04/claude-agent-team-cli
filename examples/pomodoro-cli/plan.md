# Plan：Python 命令行番茄钟（pomodoro-cli）

> 输入：`runs/pomodoro-cli/task.md`（7 条验收标准）
> 交付目录：`runs/pomodoro-cli/deliverable/`
> 本 plan 面向无上下文的执行者，照此即可实现，不依赖对话记忆。

## 1. 目标拆解

1. **G1 核心计时循环**：实现工作/休息阶段交替的周期循环，时长单位为分钟（float，支持小数），周期数可配置。
2. **G2 实时显示**：每秒原地刷新一行：当前阶段（工作/休息）、当前周期 i/总数、剩余时间 mm:ss。
3. **G3 提示机制**：阶段切换与全部完成时终端响铃（`\a`）+ 中文提示。
4. **G4 优雅退出**：Ctrl+C（KeyboardInterrupt）时打印已完成的完整周期数，退出码 0。
5. **G5 CLI 接口**：argparse，`--work`（默认 25）、`--break`（默认 5）、`--cycles`（默认 4），`--help` 显示用法与默认值。
6. **G6 可测试性**：参数解析、时间格式化等逻辑拆成纯函数；`test_pomodoro.py` 用 pytest 覆盖。
7. **G7 交付合规**：全部文件位于 `runs/pomodoro-cli/deliverable/`，仅用 Python 标准库。

## 2. 方案与步骤

### 2.1 文件清单（全部在 deliverable/ 下）

| 文件 | 作用 |
|---|---|
| `pomodoro.py` | 主程序，单文件，仅标准库（argparse、time、sys） |
| `test_pomodoro.py` | pytest 测试，`import pomodoro` 后测纯函数，不含任何 sleep |

### 2.2 pomodoro.py 内部结构（函数签名即契约）

```python
format_time(seconds: int) -> str
    # 秒 → "mm:ss"，如 0→"00:00"、59→"00:59"、60→"01:00"、3600→"60:00"
    # 分钟位不截断不进位到小时，两位起步、可超两位（如 125 分钟 → "125:00"）

minutes_to_seconds(minutes: float) -> int
    # 分钟 → 秒；max(1, round(minutes * 60))，保证最小 1 秒（0.02 分钟 = 1.2s → 1s）

build_parser() -> argparse.ArgumentParser
    # --work  float 默认 25.0（工作时长/分钟）
    # --break float 默认 5.0 （休息时长/分钟），dest="break_minutes"（break 是关键字）
    # --cycles int  默认 4  （周期数）
    # formatter_class=argparse.ArgumentDefaultsHelpFormatter，description 用中文说明
    # 三个参数均校验必须 > 0（自定义 type 函数，非法值走 argparse 标准报错，exit code 2）

parse_args(argv: list[str] | None = None) -> argparse.Namespace
    # build_parser().parse_args(argv)，便于测试注入 argv

countdown(total_seconds: int, phase_label: str, cycle: int, total_cycles: int) -> None
    # 每秒一轮：print(f"\r[{phase_label}] 周期 {cycle}/{total_cycles} 剩余 {format_time(remaining)}",
    #                end="", flush=True)；然后 time.sleep(1)
    # remaining 从 total_seconds 递减到 1，循环结束后 print() 换行

notify(message: str) -> None
    # print("\a" + message, flush=True)  —— 响铃 + 中文提示，独占一行

run(args) -> int
    # 唯一实现：KeyboardInterrupt 只在 run 内捕获，main 不做任何异常处理
    # completed = 0
    # try:
    #     for i in 1..cycles:
    #         notify(f"第 {i}/{cycles} 个周期：开始工作（{args.work} 分钟）")
    #         countdown(minutes_to_seconds(args.work), "工作", i, cycles)
    #         completed += 1                      # 工作阶段结束即计 1 个完整周期
    #         if i < cycles:                      # 最后一个周期后不再休息
    #             notify(f"工作结束，开始休息（{args.break_minutes} 分钟）")
    #             countdown(minutes_to_seconds(args.break_minutes), "休息", i, cycles)
    #     notify(f"全部完成！共完成 {completed} 个周期。")
    # except KeyboardInterrupt:
    #     print(f"\n已中断，已完成 {completed} 个完整周期。", flush=True)
    # return completed

main(argv=None) -> int
    # args = parse_args(argv); run(args); return 0

if __name__ == "__main__": sys.exit(main())
```

### 2.3 实现步骤（执行者按序做）

1. 创建 `runs/pomodoro-cli/deliverable/` 目录。
2. 实现 `pomodoro.py`：先写纯函数（format_time / minutes_to_seconds / build_parser / parse_args），再写 countdown / notify / run / main。
3. 实现 `test_pomodoro.py`（用例见 2.4）。
4. 自测：依次跑通「成功标准」第 8 节的 AC1–AC7 全部命令，确认输出与退出码符合预期后才算完成。

### 2.4 测试用例设计（test_pomodoro.py，全部无 sleep、毫秒级跑完）

**参数解析类**
- `test_defaults`：`parse_args([])` → work=25.0、break_minutes=5.0、cycles=4。
- `test_custom_values`：`parse_args(["--work","0.05","--break","0.02","--cycles","2"])` → 对应 0.05 / 0.02 / 2，验证 float 小数支持。
- `test_invalid_rejected`：`parse_args(["--cycles","0"])` 与 `parse_args(["--work","-1"])` 均 `pytest.raises(SystemExit)`。

**时间格式化类**
- `test_format_time_basic`：0→"00:00"、5→"00:05"、59→"00:59"、60→"01:00"、61→"01:01"、3599→"59:59"、3600→"60:00"。
- `test_minutes_to_seconds`：25→1500、0.05→3、0.02→1（最小 1 秒保底）、1.5→90。

## 3. 关键决策与取舍

1. **最后一个周期不休息**（`i < cycles` 才进入休息）。番茄钟惯例是休息服务于下一个工作段，尾部休息无意义；同时让快速验收更快。已在 2.2 写死，验证者按此判定。
2. **「完整周期」= 工作阶段跑完即 +1**，休息视为周期间隔。这使 Ctrl+C 的计数语义唯一：休息中被中断，该周期已算完成。对比方案（工作+休息都完才算）会让"最后周期无休息"与计数规则互相矛盾，故弃用。
3. **计时用固定 `sleep(1)` 递减循环**，不用 `end_time - time.monotonic()` 漂移校正。理由：仅标准库、单进程、分钟级时长，秒级累计误差可忽略；代码简单、可测性好。取舍：长时间运行可能慢数秒，属可接受范围（见风险 R3）。
4. **单行 `\r` 原地刷新而非逐行打印**：满足"每秒刷新"的同时不刷屏；管道/重定向下 `\r` 行仍会被捕获，验证者可用正则匹配（见 AC2）。
5. **`--break` 用 `dest="break_minutes"`**：`args.break` 是 Python 语法错误，必须重命名 dest；CLI 参数名保持 `--break` 不变，对用户无感。
6. **响铃用 `\a` 字符**：验收只要求输出含 `\a`（字节 0x07），不要求实际发声（终端是否发声取决于用户环境，程序不可控）。
7. **不做的**：无颜色输出、无配置文件、无桌面通知、无长休息（每 4 个周期长休息的进阶玩法）、无 README——task.md 未要求，保持最小交付。

## 4. 风险与边界

- **R1 pytest 依赖**：pytest 非标准库。主程序仅标准库（合规），pytest 仅测试期用。若执行/验证环境 `python3 -m pytest` 不可用，执行者先 `python3 -m pip install pytest`（或上报 main 拍板环境问题），不得改用非 pytest 方案。
- **R2 计时验收抖动**：AC1 用时长区间判定（见下），上下限已放宽 ±数秒，避免机器负载造成误判。
- **R3 计时精度**：sleep(1) 方案每阶段实际耗时 ≥ 名义时长，可能多出少量毫秒累计；验收区间已覆盖。
- **R4 非 TTY 环境**：验证多在重定向/管道下进行，`\r` 与 `\a` 均为普通字节会被捕获，flush=True 保证不丢缓冲。
- **边界**：只支持 macOS/Linux 的 python3 命令行运行；不承诺 Windows cmd 的响铃效果；参数非法时由 argparse 以退出码 2 报错属预期行为，不属于"优雅退出"范畴。

## 5. 成功标准（Acceptance Criteria，供 Verifier 逐条判定）

> 所有命令均在 `runs/pomodoro-cli/deliverable/` 目录下执行。对应 task.md 的 7 条验收标准，细化为可执行判定。

- **AC1（↔task#1 完整跑完）**：`time python3 pomodoro.py --work 0.05 --break 0.02 --cycles 2` 正常结束，退出码 0；总耗时在 **6–14 秒** 区间（名义 3+1+3=7 秒）；输出包含"全部完成"与"2 个周期"。
- **AC2（↔task#2 每秒刷新）**：AC1 捕获的输出中，按 `\r` 拆分后能匹配到 ≥5 条符合正则 `\[工作\] 周期 \d/\d 剩余 \d{2,}:\d{2}` 的记录（注意 `[` `]` 必须转义，否则正则里是字符类），且同时存在字面子串 `[工作]` 与 `[休息]` 两种阶段、`00:0\d` 形式的递减倒计时。
- **AC3（↔task#3 响铃+中文提示）**：AC1 输出中 `\a`（0x07）出现 **≥4 次**（2 次工作开始 + 1 次休息开始 + 1 次全部完成）；且存在"开始工作""开始休息""全部完成"三类中文提示。
- **AC4（↔task#4 Ctrl+C 优雅退出）**：后台启动 `python3 pomodoro.py --work 0.05 --break 0.02 --cycles 9`，**5 秒**后向进程发 SIGINT；进程退出码 **0**，输出含子串"已完成"与"1 个完整周期"（时间线：工作1 结束于 ~3s、休息1 结束于 ~4s、工作2 覆盖 ~4–7s，5s 落在工作2 中段，双侧余量 ≥2 秒；中断文案为"已中断，已完成 1 个完整周期。"，与判定词一致）。
- **AC5（↔task#5 帮助信息）**：`python3 pomodoro.py --help` 退出码 0，输出含 `--work`、`--break`、`--cycles` 三个参数及默认值字样；float 默认值经 ArgumentDefaultsHelpFormatter 实际显示为 `25.0`/`5.0`，与 `25`/`5` 均判符合，cycles 默认值显示 `4`。不得用 `default: 25` 这类精确等值匹配判定。
- **AC6（↔task#6 pytest）**：在 deliverable/ 下 `python3 -m pytest -q` 全部通过（0 failed），且 test_pomodoro.py 至少含 2.4 列出的参数解析类 ≥3 个、时间格式化类 ≥2 个用例。
- **AC7（↔task#7 交付位置 + 仅标准库）**：`pomodoro.py` 与 `test_pomodoro.py` 均位于 `runs/pomodoro-cli/deliverable/`；`grep -E "^(import|from)" pomodoro.py` 结果仅含标准库模块（argparse/time/sys 等），无第三方 import。

## 6. 修订记录

### 第 2 轮（回应 review-log.md 第 1 轮评审）

**必改项，全部采纳：**
1. AC4 判定词与中断文案不一致 → **已改**：中断文案统一为「已中断，已完成 X 个完整周期。」（2.2 run 伪代码），AC4 判定词保持「已完成」+「1 个完整周期」，两者含相同连续子串。
2. AC2 正则 `[工作]` 未转义 → **已改**：正则改为 `\[工作\] 周期 \d/\d 剩余 \d{2,}:\d{2}`，并在 AC2 中注明转义原因；阶段存在性判定明确为字面子串匹配。
3. main 伪代码 except 引用作用域外 completed 且两方案并存 → **已改**：删除 main 中的 except 分支，唯一实现定为 run 内部 try/except KeyboardInterrupt 并打印计数，main 仅 `parse_args + run + return 0`。

**建议项，全部采纳：**
4. AC4 SIGINT 时刻 4s 紧贴边界 → **已改**：改为 5 秒（工作2 中段，双侧余量 ≥2 秒），期望值不变。
5. AC5 float 默认值显示为 25.0/5.0 → **已改**：AC5 注明 `25.0`/`5.0` 亦符合，并禁止精确等值匹配。
