"""pomodoro.py 的 pytest 用例：只覆盖纯函数，无任何 sleep，毫秒级跑完。"""

import pytest

import pomodoro


# ---------- 参数解析类 ----------

def test_defaults():
    args = pomodoro.parse_args([])
    assert args.work == 25.0
    assert args.break_minutes == 5.0
    assert args.cycles == 4


def test_custom_values():
    args = pomodoro.parse_args(["--work", "0.05", "--break", "0.02", "--cycles", "2"])
    assert args.work == 0.05
    assert args.break_minutes == 0.02
    assert args.cycles == 2


def test_invalid_rejected():
    with pytest.raises(SystemExit):
        pomodoro.parse_args(["--cycles", "0"])
    with pytest.raises(SystemExit):
        pomodoro.parse_args(["--work", "-1"])


# ---------- 时间格式化类 ----------

@pytest.mark.parametrize(
    "seconds,expected",
    [
        (0, "00:00"),
        (5, "00:05"),
        (59, "00:59"),
        (60, "01:00"),
        (61, "01:01"),
        (3599, "59:59"),
        (3600, "60:00"),
    ],
)
def test_format_time_basic(seconds, expected):
    assert pomodoro.format_time(seconds) == expected


@pytest.mark.parametrize(
    "minutes,expected",
    [
        (25, 1500),
        (0.05, 3),
        (0.02, 1),
        (1.5, 90),
    ],
)
def test_minutes_to_seconds(minutes, expected):
    assert pomodoro.minutes_to_seconds(minutes) == expected
