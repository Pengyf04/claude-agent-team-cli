#!/bin/bash
# ensure-inbound.sh <项目目录>
# 安全地把 {"crossSessionInbound":"accept"} 合并进 <项目>/.claude/settings.local.json（不覆盖其他键，幂等），
# 并把运行时产物加入 .git/info/exclude。输出 NEW（本次新写入）或 EXISTS（已存在），供主控判断是否需重启。
# 主控可在启动前由用户手动运行；SKILL P1 也会调用。
set -euo pipefail
PROJ="$(cd "${1:?用法: ensure-inbound.sh <项目目录>}" && pwd)"
F="$PROJ/.claude/settings.local.json"
mkdir -p "$PROJ/.claude"
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
