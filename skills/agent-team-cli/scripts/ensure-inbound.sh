#!/bin/bash
# ensure-inbound.sh <项目目录> [--remove]
# 安全地把 {"crossSessionInbound":"accept"} 合并进 <项目>/.claude/settings.local.json（不覆盖其他键，幂等），
# 并把运行时产物加入 .git/info/exclude。输出 NEW（本次新写入）或 EXISTS（已存在），供主控判断是否需重启。
# --remove：收尾时**只移除该键**，保留文件里的其他内容——它是有安全含义的持久配置
#   （本项目所有会话无门禁收消息），任务结束后不该默认留着；但直接删整个文件会连带
#   抹掉用户自己的项目配置。输出 REMOVED / ABSENT / NOFILE。
# 主控可在启动前由用户手动运行；SKILL P1 与 P5 也会调用。
set -euo pipefail
PROJ="$(cd "${1:?用法: ensure-inbound.sh <项目目录> [--remove]}" && pwd)"
MODE="${2:-}"
F="$PROJ/.claude/settings.local.json"
mkdir -p "$PROJ/.claude"

if [ "${MODE}" = "--remove" ]; then
  [ -s "${F}" ] || { echo "NOFILE"; exit 0; }
  command -v python3 >/dev/null 2>&1 || { echo "ERROR: 未找到 python3，请手动从 ${F} 移除 crossSessionInbound 键" >&2; exit 1; }
  F="$F" python3 - <<'PY'
import json, os, sys
p = os.environ["F"]
try:
    d = json.load(open(p, encoding="utf-8"))
except json.JSONDecodeError as e:
    print(f"ERROR: {p} 不是合法 JSON（{e}），未修改", file=sys.stderr); sys.exit(1)
if not isinstance(d, dict) or "crossSessionInbound" not in d:
    print("ABSENT"); sys.exit(0)
del d["crossSessionInbound"]
if d:
    json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
else:
    os.remove(p)   # 本就只有这一个键 → 整个文件删掉，不留空壳
print("REMOVED")
PY
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  RESULT="$(F="$F" python3 - <<'PY'
import json, os, sys
p = os.environ["F"]
d = {}
if os.path.exists(p) and os.path.getsize(p) > 0:
    try:
        d = json.load(open(p, encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"ERROR: {p} 不是合法 JSON（{e}），未修改", file=sys.stderr); sys.exit(1)
    if not isinstance(d, dict): d = {}
if d.get("crossSessionInbound") == "accept":
    print("EXISTS")
else:
    d["crossSessionInbound"] = "accept"
    json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
    print("NEW")
PY
)"
else
  # 无 python3 的兜底：仅在文件不存在时创建；已存在则提示手动合并
  if [ ! -s "$F" ]; then printf '{\n  "crossSessionInbound": "accept"\n}\n' > "$F"; RESULT="NEW"
  elif grep -q '"crossSessionInbound"[[:space:]]*:[[:space:]]*"accept"' "$F"; then RESULT="EXISTS"
  else echo "ERROR: 未找到 python3 且 $F 已有内容，请手动加入 \"crossSessionInbound\": \"accept\"" >&2; exit 1; fi
fi
if [ -d "$PROJ/.git" ]; then
  mkdir -p "$PROJ/.git/info"
  for pat in ".claude/agent-team-cli/" ".claude/settings.local.json"; do
    grep -qxF "$pat" "$PROJ/.git/info/exclude" 2>/dev/null || echo "$pat" >> "$PROJ/.git/info/exclude"
  done
fi
echo "$RESULT"
