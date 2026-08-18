# 任务：Python 命令行番茄钟

实现一个命令行番茄钟工具 pomodoro.py（仅用 Python 标准库），支持工作/休息周期循环。

## 验收标准（逐条可判定）
1. `python3 pomodoro.py --work 0.05 --break 0.02 --cycles 2` 能完整跑完 2 个周期后正常退出（时长单位=分钟，支持小数便于快速测试）
2. 运行中每秒刷新显示：当前阶段（工作/休息）、当前周期数、剩余时间倒计时（mm:ss）
3. 阶段切换与全部完成时：终端响铃（\a）并打印明确的中文提示
4. Ctrl+C 优雅退出：打印已完成的完整周期数，退出码 0
5. `python3 pomodoro.py --help` 显示用法（argparse，含各参数默认值：work=25 分钟、break=5 分钟、cycles=4）
6. 附 pytest 测试 test_pomodoro.py：至少覆盖参数解析与时间格式化两类函数，在 deliverable/ 目录下 `python3 -m pytest -q` 全部通过
7. 全部交付物位于 runs/pomodoro-cli/deliverable/
