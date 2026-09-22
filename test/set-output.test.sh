#!/bin/bash
# --set-output: build one safe hl.monitor() from live values + overrides.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap '/usr/bin/rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
if [[ "${1:-}" == "-j" ]]; then
  printf '%s' '[{"name":"DP-4","description":"Dell","width":3840,"height":2160,"refreshRate":59.997,"scale":1.25,"x":0,"y":0},{"name":"eDP-1","description":"LG","width":2880,"height":1800,"refreshRate":120.001,"scale":1.25,"x":339,"y":1728}]'
  exit 0
fi
printf '%s\n' "$*" >> "$(dirname "$0")/eval.log"
STUB
chmod +x "$TMP/bin/hyprctl"

PATH="$TMP/bin:$PATH" bash "$ROOT/workscape.sh" --set-output DP-4 2 "" >/dev/null
lua=$(cat "$TMP/bin/eval.log")
[[ $lua == *'mode = "3840x2160@60"'* ]] || { echo "bad mode in: $lua"; exit 1; }
[[ $lua == *'scale = 2'* ]] || { echo "bad scale in: $lua"; exit 1; }
[[ $lua == *'position = "0x0"'* ]] || { echo "bad pos in: $lua"; exit 1; }

: > "$TMP/bin/eval.log"
PATH="$TMP/bin:$PATH" bash "$ROOT/workscape.sh" --set-output eDP-1 "" "2880x1800@60" >/dev/null
lua=$(cat "$TMP/bin/eval.log")
[[ $lua == *'mode = "2880x1800@60"'* ]] || { echo "mode override lost: $lua"; exit 1; }
[[ $lua == *'scale = 1.25'* ]] || { echo "scale not kept: $lua"; exit 1; }
[[ $lua == *'position = "339x1728"'* ]] || { echo "position moved: $lua"; exit 1; }

if PATH="$TMP/bin:$PATH" bash "$ROOT/workscape.sh" --set-output 'DP-4; touch pwned' 2 "" >/dev/null 2>&1; then
  echo "bad connector accepted"
  exit 1
fi
[[ ! -e "$TMP/pwned" ]] || { echo "connector injection escaped"; exit 1; }
if PATH="$TMP/bin:$PATH" bash "$ROOT/workscape.sh" --set-output DP-4 "" "1920x1080; rm x" >/dev/null 2>&1; then
  echo "bad mode accepted"
  exit 1
fi
echo "set-output.test.sh ok"
