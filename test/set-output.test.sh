#!/bin/bash
# --set-output: build one safe hl.monitor() from live values + overrides.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'echo kept $TMP' EXIT
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

# --set-profile-output: pin + live set + guard re-arm, serialized under the
# apply lock so a scan can never enforce a pre-edit snapshot.
CFG='{"version":2,"settings":{"activeProfileId":"desk"},"monitors":[{"id":"laptop","label":"Laptop","serial":"","description":"LG","name":"eDP-1"},{"id":"dell","label":"Dell","serial":"","description":"Dell","name":"DP-4"}],"profiles":[{"id":"desk","name":"Desk","monitors":["laptop","dell"]}]}'
STATE="$TMP/state"
mkdir -p "$STATE/omarchy/workscape"
printf '%s' "$CFG" > "$STATE/omarchy/workscape/config.json"
: > "$TMP/bin/eval.log"
XDG_STATE_HOME="$STATE" PATH="$TMP/bin:$PATH" WORKSCAPE_CONFIG="$STATE/omarchy/workscape/config.json" \
  bash -x "$ROOT/workscape.sh" --set-profile-output desk laptop 1.75 "" 2>"$TMP/trace.log" >/dev/null
pin=$(jq -r '.profiles[0].monitorScales.laptop // empty' "$STATE/omarchy/workscape/config.json")
[[ $pin == 1.75 ]] || { echo "pin not saved: $pin"; exit 1; }
lua=$(cat "$TMP/bin/eval.log")
[[ $lua == *'scale = 1.75'* ]] || { echo "live set missing scale: $lua"; exit 1; }
[[ -s "$STATE/omarchy/workscape/last_auto_fp" ]] || { echo "guard fingerprint not armed"; exit 1; }
guard_prof=$(cat "$STATE/omarchy/workscape/last_auto_profile")
[[ $guard_prof == "desk" ]] || { echo "guard profile wrong: $guard_prof"; exit 1; }

XDG_STATE_HOME="$STATE" PATH="$TMP/bin:$PATH" WORKSCAPE_CONFIG="$STATE/omarchy/workscape/config.json" \
  bash "$ROOT/workscape.sh" --set-profile-output desk laptop auto "" >/dev/null
pin=$(jq -r '.profiles[0].monitorScales.laptop // empty' "$STATE/omarchy/workscape/config.json")
[[ -z $pin ]] || { echo "auto did not unpin: $pin"; exit 1; }
echo "set-profile-output ok"
