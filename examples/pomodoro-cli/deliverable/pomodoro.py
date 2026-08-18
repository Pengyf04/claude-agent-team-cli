#!/usr/bin/env python3
"""命令行番茄钟：工作 / 休息阶段交替循环，仅使用 Python 标准库。"""

import argparse
import sys
import time


def format_time(seconds: int) -> str:
    """秒 → "mm:ss"。分钟位不进位到小时，两位起步、可超两位（125 分钟 → "125:00"）。"""
    minutes, secs = divmod(int(seconds), 60)
    return f"{minutes:02d}:{secs:02d}"


def minutes_to_seconds(minutes: float) -> int:
    """分钟 → 秒，最小保底 1 秒（0.02 分钟 = 1.2s → 1s）。"""
    return max(1, round(minutes * 60))


def positive_float(value: str) -> float:
    """argparse type：必须为大于 0 的浮点数。"""
    number = float(value)
    if number <= 0:
        raise argparse.ArgumentTypeError(f"必须大于 0，当前为 {value}")
    return number


def positive_int(value: str) -> int:
    """argparse type：必须为大于 0 的整数。"""
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError(f"必须大于 0，当前为 {value}")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pomodoro.py",
        description="命令行番茄钟：按设定的周期数交替进行工作与休息，时长单位为分钟（支持小数）。",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--work", type=positive_float, default=25.0, help="工作时长（分钟）"
    )
    parser.add_argument(
        "--break",
        dest="break_minutes",
        type=positive_float,
        default=5.0,
        help="休息时长（分钟）",
    )
    parser.add_argument(
        "--cycles", type=positive_int, default=4, help="周期数"
    )
    return parser


def parse_args(argv=None) -> argparse.Namespace:
    return build_parser().parse_args(argv)


def countdown(total_seconds: int, phase_label: str, cycle: int, total_cycles: int) -> None:
    """每秒原地刷新一行倒计时，从 total_seconds 递减到 1。"""
    for remaining in range(total_seconds, 0, -1):
        print(
            f"\r[{phase_label}] 周期 {cycle}/{total_cycles} 剩余 {format_time(remaining)}",
            end="",
            flush=True,
        )
        time.sleep(1)
    print()


def notify(message: str) -> None:
    """响铃 + 中文提示，独占一行。"""
    print("\a" + message, flush=True)


def run(args) -> int:
    """执行完整番茄钟流程，返回已完成的完整周期数。"""
    cycles = args.cycles
    completed = 0
    try:
        for i in range(1, cycles + 1):
            notify(f"第 {i}/{cycles} 个周期：开始工作（{args.work} 分钟）")
            countdown(minutes_to_seconds(args.work), "工作", i, cycles)
            completed += 1
            if i < cycles:
                notify(f"工作结束，开始休息（{args.break_minutes} 分钟）")
                countdown(minutes_to_seconds(args.break_minutes), "休息", i, cycles)
        notify(f"全部完成！共完成 {completed} 个周期。")
    except KeyboardInterrupt:
        print(f"\n已中断，已完成 {completed} 个完整周期。", flush=True)
    return completed


def main(argv=None) -> int:
    args = parse_args(argv)
    run(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
