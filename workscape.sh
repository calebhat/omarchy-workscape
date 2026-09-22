#!/bin/bash
set -uo pipefail

PLUGIN_ID="io.github.calebhat.workscape"
# Config lives OUTSIDE the plugin dir: the shell watches the plugin folder and
# reloads the whole plugin on any file change there, which would close the
# panel and restart the service on every settings save.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workscape"
CONFIG_FILE="$STATE_DIR/config.json"
MAX_CONFIG_BYTES=524288
PREV_WORKBOOK_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workbook"
PREV_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/auto-workspace"
LEGACY_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/tenzin.auto-workspace/config.json"
STATE_FILE="$STATE_DIR/state.json"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Omarchy reloads the plugin on any file write under this folder (including
# Python's __pycache__). Never write bytecode here or Capture closes the panel.
export PYTHONDONTWRITEBYTECODE=1
MATCH="$PLUGIN_DIR/scripts/match"
GEOM="$PLUGIN_DIR/scripts/geom"
GESTURES="$PLUGIN_DIR/scripts/gestures"
HOTKEYS="$PLUGIN_DIR/scripts/hotkeys"
STATEIO="$PLUGIN_DIR/scripts/stateio"
WORKSCAPE_APPLY_ARGV=("$@")

default_config() {
  cat <<'JSON'
{
  "version": 2,
  "settings": {
    "enabled": true,
    "applyOnBoot": false,
    "launchDelayMs": 800,
    "staggerMs": 80,
    "silent": true,
    "onlyOnBoot": true,
    "lastFormWorkspace": 1,
    "activeProfileId": "default"
  },
  "monitors": [],
  "extraApps": [],
  "profiles": [
    {
      "id": "default",
      "name": "Default",
      "matchMode": "exact",
      "monitors": [],
      "workspaceMonitors": {},
      "assignments": []
    }
  ]
}
JSON
}

ensure_config() {
  python3 "$STATEIO" ensure-config >/dev/null
}

read_config() {
  python3 "$STATEIO" ensure-config
}

jq_config() {
  read_config | jq "$@"
}

state_get() {
  python3 "$STATEIO" read-state "$1" 2>/dev/null || true
}

state_put() {
  printf '%s' "$2" | python3 "$STATEIO" write-state "$1"
}

cmd_ensure_config() {
  python3 "$STATEIO" ensure-config || exit 1
}

cmd_write_config() {
  python3 "$STATEIO" write-config
}

cmd_hypr_layout() {
  local layout col
  layout=$(timeout 2 hyprctl getoption general:layout -j </dev/null 2>/dev/null | jq -r '.str // empty' 2>/dev/null || true)
  col=$(timeout 2 hyprctl getoption scrolling:column_width -j </dev/null 2>/dev/null | jq -r '.float // 0.49' 2>/dev/null || true)
  printf '%s|%s\n' "${layout:-dwindle}" "${col:-0.49}"
}

live_monitors_json() {
  timeout 3 hyprctl -j monitors all </dev/null 2>/dev/null \
    || timeout 3 hyprctl -j monitors </dev/null 2>/dev/null \
    || echo "[]"
}

hypr_clients_json() {
  timeout 2 hyprctl clients -j </dev/null 2>/dev/null || echo "[]"
}

ensure_isolated() {
  if [[ ${WORKSCAPE_APPLY_ISOLATED:-} == "1" ]]; then
    return 0
  fi
  exec python3 "$STATEIO" isolate-apply --timeout 180 -- /bin/bash "$PLUGIN_DIR/workscape.sh" "${WORKSCAPE_APPLY_ARGV[@]}"
}

apply_profile_outputs() {
  local profile_id=$1
  if ! live_monitors_json | timeout --kill-after=2 12 python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --apply-outputs; then
    echo "monitor layout timed out or failed — continuing with launch"
  fi
}

cmd_live_status() {
  ensure_config
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --status
}

cmd_sync_active_profile() {
  ensure_config || exit 1
  local id cur
  id=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --print-id 2>/dev/null || true)
  id=${id//$'\n'/}
  if [[ ! $id =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo '{"synced":false}'
    return 0
  fi
  if ! jq_config -e --arg id "$id" '.profiles[] | select(.id==$id)' >/dev/null 2>&1; then
    echo '{"synced":false}'
    return 0
  fi
  cur=$(jq_config -r '.settings.activeProfileId // empty')
  if [[ $id == "$cur" ]]; then
    printf '{"synced":false,"id":"%s"}\n' "$id"
    return 0
  fi
  if read_config | jq --arg id "$id" '.settings.activeProfileId = $id' | python3 "$STATEIO" write-config >/dev/null; then
    printf '{"synced":true,"id":"%s","from":"%s"}\n' "$id" "$cur"
  else
    echo '{"synced":false,"error":"write"}'
    return 1
  fi
}

cmd_match_id() {
  ensure_config
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --print-id
}

# Direct control-surface hook: set one output's scale and/or mode in place.
# Empty args keep the current value; position never moves.
cmd_set_output() {
  local conn=$1 scale=${2:-} mode=${3:-}
  [[ $conn =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "bad connector: $conn" >&2; return 1; }
  [[ $conn != *HEADLESS* ]] || { echo "no headless outputs" >&2; return 1; }
  local mon
  mon=$(live_monitors_json | jq -c --arg n "$conn" '[.[] | select(.name==$n)][0] // empty')
  [[ -n $mon ]] || { echo "monitor not found: $conn" >&2; return 1; }
  local w h r sc x y
  w=$(printf '%s' "$mon" | jq -r '.width // 0')
  h=$(printf '%s' "$mon" | jq -r '.height // 0')
  r=$(printf '%s' "$mon" | jq -r '.refreshRate // 60')
  sc=$(printf '%s' "$mon" | jq -r '.scale // 1')
  x=$(printf '%s' "$mon" | jq -r '.x // 0')
  y=$(printf '%s' "$mon" | jq -r '.y // 0')
  if [[ -n $mode ]]; then
    if [[ $mode =~ ^([0-9]{3,5})x([0-9]{3,5})@([0-9]{1,3}(\.[0-9]{1,3})?)$ ]]; then
      w=${BASH_REMATCH[1]}
      h=${BASH_REMATCH[2]}
      r=${BASH_REMATCH[3]}
    else
      echo "bad mode: $mode" >&2
      return 1
    fi
  fi
  if [[ -n $scale ]]; then
    [[ $scale =~ ^[0-9]\.?[0-9]{0,2}$ ]] || { echo "bad scale: $scale" >&2; return 1; }
    sc=$scale
  fi
  (( w > 0 && h > 0 )) || { echo "monitor has no mode: $conn" >&2; return 1; }
  local hz
  hz=$(printf '%.2f' "$r" | sed -e 's/0*$//' -e 's/\.$//')
  timeout 3 hyprctl eval "$(printf 'hl.monitor({ output = "%s", mode = "%sx%s@%s", position = "%sx%s", scale = %s })' "$conn" "$w" "$h" "$hz" "$x" "$y" "$sc")" </dev/null >/dev/null 2>&1 || true
  echo "set $conn ${w}x${h}@${hz} scale=${sc} pos=${x}x${y}"
}

cmd_apply_on_monitor_change() {
  # Event + periodic scan body: settle, match, and apply at most what changed.
  ensure_config || exit 1
  wait_for_hyprland || exit 1
  local settle fp matched new_matched rounds=0
  settle=$(python3 "$PLUGIN_DIR/scripts/monitorsettle" --wait --timeout 12 2>/dev/null || true)
  fp=$(printf '%s' "$settle" | jq -r '.fingerprint // empty' 2>/dev/null || true)
  if [[ -z $fp ]]; then
    echo "no monitor fingerprint — skipping"
    exit 0
  fi
  matched=$(cmd_match_id 2>/dev/null | tr -d '\n')
  if [[ -z $matched ]]; then
    echo "no profile matches the current displays — nothing to do"
    exit 0
  fi
  local last_fp last_profile
  last_fp=$(state_get last_auto_fp | tr -d '\n')
  last_profile=$(state_get last_auto_profile | tr -d '\n')
  if [[ $fp == "$last_fp" && $matched == "$last_profile" ]]; then
    echo "display set unchanged (profile $matched) — skipping"
    exit 0
  fi
  while :; do
    rounds=$((rounds + 1))
    echo "auto-apply: displays settled → profile $matched (round $rounds)"
    cmd_sync_active_profile >/dev/null || true
    # Subshell: cmd_apply execs into the isolated apply; the scan must survive
    # to re-check the display set and record the guard state afterwards.
    ( WORKSCAPE_APPLY_ARGV=(--apply-profile "$matched")
      cmd_apply hotkey "$matched" true ) || true
    # Another display can land mid-apply; re-settle briefly and re-check.
    settle=$(python3 "$PLUGIN_DIR/scripts/monitorsettle" --wait --timeout 4 2>/dev/null || true)
    fp=$(printf '%s' "$settle" | jq -r '.fingerprint // empty' 2>/dev/null || true)
    [[ -n $fp ]] || break
    new_matched=$(cmd_match_id 2>/dev/null | tr -d '\n')
    if [[ -z $new_matched || $new_matched == "$matched" ]]; then
      matched=${new_matched:-$matched}
      break
    fi
    matched=$new_matched
    if (( rounds >= 3 )); then
      echo "auto-apply: match still moving ($matched) — stopping after $rounds rounds"
      break
    fi
  done
  state_put last_auto_fp "$fp"
  state_put last_auto_profile "$matched"
}

notify() {
  local title=$1 body=$2
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "WorkScape" -- "$title" "$body" >/dev/null 2>&1 || true
  fi
}

profile_must_match() {
  # Refuse desk-dock (etc.) on laptop-only hardware. Silent spawn then lands
  # windows on the focused workspace instead of the missing monitors.
  local id=$1
  local out rc=0
  out=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$id" --require-match 2>/dev/null) || rc=$?
  if (( rc == 0 )); then
    return 0
  fi
  local msg
  msg=$(printf '%s' "$out" | jq -r '.detail // .reason // "does not match connected displays"' 2>/dev/null || echo "does not match connected displays")
  echo "refusing profile $id — $msg" >&2
  notify "WorkScape" "$msg"
  return 1
}

move_workspace_to_monitor() {
  local ws=$1 name=$2
  [[ $ws =~ ^[0-9]+$ ]] || return 0
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || return 0
  [[ $name != *HEADLESS* ]] || return 0
  hyprctl eval "$(printf 'hl.dispatch(hl.dsp.workspace.move({workspace="%s", monitor="%s"}))' "$ws" "$name")" >/dev/null 2>&1 || true
}

bind_workspace_to_monitor() {
  local ws=$1 name=$2
  [[ $ws =~ ^[0-9]+$ ]] || return 0
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || return 0
  [[ $name != *HEADLESS* ]] || return 0
  local layout
  layout=$(jq_config -r --arg ws "$ws" '
    .settings.activeProfileId as $id
    | (.profiles[] | select(.id==$id) | .workspacePrefs[$ws].layout) // "dwindle"
  ' 2>/dev/null || echo dwindle)
  local locks
  locks=$(jq_config -r --arg ws "$ws" '
    .settings.activeProfileId as $id
    | [.profiles[] | select(.id==$id) | .assignments[]? | select((.workspace|tostring)==$ws and .lockPlace==true)] | length
  ' 2>/dev/null || echo 0)
  if [[ $locks =~ ^[0-9]+$ ]] && (( locks >= 2 )); then
    layout=dwindle
  fi
  case "$layout" in
    dwindle|scrolling|master) ;;
    *) layout=dwindle ;;
  esac
  hyprctl eval "$(printf 'hl.workspace_rule({ workspace = "%s", monitor = "%s", persistent = true, layout = "%s" })' "$ws" "$name" "$layout")" >/dev/null 2>&1 || true
  move_workspace_to_monitor "$ws" "$name"
  echo "bound workspace $ws → $name"
}

snapshot_workspaces() {
  hyprctl -j workspaces 2>/dev/null | jq -c '[.[] | select(.id != null) | {id: (.id|tostring), monitor: (.monitor // "")}]' 2>/dev/null || echo "[]"
}

# After monitor enable/disable/move, put unpinned workspaces back where they were.
restore_unpinned_workspaces() {
  local snap=$1
  local pinned_json=${2:-{}}
  [[ -n $snap && $snap != "[]" && $snap != "null" ]] || return 0
  local enabled
  enabled=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.disabled != true) | .name' 2>/dev/null)
  # Drop leftover persistent pins from a previous profile (Hyprland keeps them).
  local n
  for n in $(seq 1 10); do
    if printf '%s' "$pinned_json" | jq -e --arg ws "$n" 'has($ws)' >/dev/null 2>&1; then
      continue
    fi
    hyprctl eval "$(printf 'hl.workspace_rule({ workspace = "%s", persistent = false })' "$n")" >/dev/null 2>&1 || true
  done
  printf '%s' "$snap" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
    [[ -n $item ]] || continue
    local ws mon
    ws=$(printf '%s' "$item" | jq -r '.id // empty')
    mon=$(printf '%s' "$item" | jq -r '.monitor // empty')
    [[ -n $ws && -n $mon ]] || continue
    if printf '%s' "$pinned_json" | jq -e --arg ws "$ws" 'has($ws)' >/dev/null 2>&1; then
      continue
    fi
    if [[ " ${WORKSCAPE_OCCUPIED_WS:-} " == *" $ws "* ]]; then
      echo "leave workspace $ws — already has windows"
      continue
    fi
    printf '%s\n' "$enabled" | grep -qx -- "$mon" || continue
    echo "keep workspace $ws on $mon"
    move_workspace_to_monitor "$ws" "$mon"
  done
}

# geom JSON {x,y,w,h} is 0–1 of the workspace's *layout* area (backend pixels / scale).
apply_window_geom() {
  local addr=$1 geom_json=$2 ws=$3
  [[ -n $addr && -n $geom_json && $geom_json != "null" ]] || return 0
  python3 "$GEOM" --apply-one --addr "$addr" --geom "$geom_json" --workspace "$ws" || true
}

apply_profile_geoms() {
  local profile_id=$1
  python3 "$GEOM" --apply-config --config "$CONFIG_FILE" --profile-id "$profile_id" || true
}

apply_bindings() {
  local bindings_json=$1
  [[ -n $bindings_json && $bindings_json != "{}" && $bindings_json != "null" ]] || return 0
  python3 -c '
import json, sys
b = json.loads(sys.argv[1])
for ws, name in b.items():
    if ws and name:
        print(f"{ws}\t{name}")
' "$bindings_json" | while IFS=$'\t' read -r ws name; do
    bind_workspace_to_monitor "$ws" "$name"
  done
}

profile_assignments() {
  local profile_id=$1
  if jq_config -e '.profiles' >/dev/null 2>&1; then
    jq_config -c --arg id "$profile_id" '
      (.profiles // [] | map(select(.id == $id)) | .[0].assignments // [])
      | sort_by(
          (.geom.z // 0) as $z
          | (.exec // .command // "") as $e
          | if ($e | test("outlook-mail|https://|omarchy-launch-webapp")) then ($z - 100)
            elif ($e | test("brave$|/brave$")) then ($z + 100)
            else $z end
        )[]?
    ' 2>/dev/null
  else
    jq_config -c '.assignments[]?' 2>/dev/null
  fi
}

cmd_list_apps() {
  # List .desktop apps: Name | Exec | Icon | IconPath | File | Score
  # Score = rough frecency from shell histories + recently-used.xbel, so the
  # panel can show commonly used apps first. IconPath lets the UI render
  # real icons instead of glyphs.
  local seen=""
  local -A seen_desk
  local -A seen_name
  # Extra / TUI apps that are not .desktop files (Herdr, custom extras).
  ensure_config
  local extra_line extra_name extra_exec extra_icon
  while IFS= read -r extra_line; do
    [[ -n $extra_line ]] || continue
    extra_name=$(printf '%s' "$extra_line" | jq -r '.name')
    extra_exec=$(printf '%s' "$extra_line" | jq -r '.exec // .command')
    extra_icon=$(printf '%s' "$extra_line" | jq -r '.icon // empty')
    [[ -n $extra_name && -n $extra_exec ]] || continue
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$extra_name" "$extra_exec" "${extra_icon:-utilities-terminal}" "" "extra" "9999"
    seen+="|$extra_exec|"
    seen_name["${extra_name,,}"]=1
  done < <(jq_config -c '.extraApps[]?' 2>/dev/null)

  # Skip walking the icon themes here — the panel resolves Icon= via Quickshell.
  local hist_txt="" h
  for h in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.local/share/fish/fish_history"; do
    [[ -f $h ]] || continue
    hist_txt+="$(tail -c 262144 "$h" 2>/dev/null)"
    hist_txt+="\n"
  done
  local -A tok_count
  local token count
  while read -r token count; do
    [[ -n $token ]] && tok_count["$token"]="$count"
  done < <(awk '{ for (i=1; i<=NF && i<=2; i++) { if ($i ~ /^[a-zA-Z0-9_.+-]+$/ && $i !~ /^[0-9:-]+$/) print tolower($i) } }' < <(printf "%b" "$hist_txt") | sort | uniq -c | awk '{ print $2, $1 }')
  local -A xbel_count
  while read -r count path; do
    [[ -n $path ]] && xbel_count["$path"]="$count"
  done < <(grep -oE 'file://[^"]+\.desktop' "$HOME/.local/share/recently-used.xbel" 2>/dev/null | sed 's#file://##' | sort | uniq -c | awk '{ print $2, $1 }')
  for dir in "$HOME/.local/share/applications" "/usr/share/applications" "/var/lib/flatpak/exports/share/applications" "$HOME/.local/share/flatpak/exports/share/applications"; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' file; do
      local name="" exec_line="" icon="" hidden="" nodisplay=""
      name=$(grep -m1 "^Name=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      exec_line=$(grep -m1 "^Exec=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      icon=$(grep -m1 "^Icon=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      hidden=$(grep -m1 "^Hidden=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      nodisplay=$(grep -m1 "^NoDisplay=" "$file" 2>/dev/null | cut -d= -f2- | head -n1)
      [[ $hidden == "true" || $nodisplay == "true" ]] && continue
      [[ -z $name || -z $exec_line ]] && continue
      local icon_path=""
      if [[ -n $icon && $icon == /* && -f $icon ]]; then
        icon_path="$icon"
      fi
      exec_line=$(echo "$exec_line" | sed -E 's/ \%[UuFfDdNnickvm]//g' | xargs)
      [[ -z $exec_line ]] && continue
      local desk_base="${file##*/}"
      desk_base="${desk_base,,}"
      local name_key="${name,,}"
      if [[ -n ${seen_desk[$desk_base]:-} ]]; then continue; fi
      if [[ -n ${seen_name[$name_key]:-} ]]; then continue; fi
      if [[ $seen == *"|$exec_line|"* ]]; then continue; fi
      seen_desk["$desk_base"]=1
      seen_name["$name_key"]=1
      seen+="|$exec_line|"
      local base="${exec_line%% *}"
      local appname="${base##*/}"
      local score=0
      local base_l="${base,,}" appname_l="${appname,,}" nfirst_l="${name%% *}" domain_l=""
      nfirst_l="${nfirst_l,,}"
      [[ -n ${tok_count[$base_l]:-} ]] && score=$((score + tok_count["$base_l"]))
      [[ -n ${tok_count[$appname_l]:-} ]] && score=$((score + tok_count["$appname_l"]))
      [[ -n ${tok_count[$nfirst_l]:-} ]] && score=$((score + tok_count["$nfirst_l"]))
      if [[ $exec_line == omarchy-launch-webapp* ]]; then
        local url="${exec_line#*\'}"; url="${url%%\'*}"
        if [[ $url == http* ]]; then
          domain_l=$(echo "$url" | sed -E 's#^[a-z]+://([^/:]+).*#\1#' | sed -E 's/^www\.//')
          domain_l="${domain_l%%.*}"
          domain_l="${domain_l,,}"
          [[ -n ${tok_count[$domain_l]:-} ]] && score=$((score + tok_count["$domain_l"]))
        fi
      fi
      [[ -n ${xbel_count[$file]:-} ]] && score=$((score + xbel_count["$file"]))
      if [[ $exec_line == *omarchy-launch-webapp* ]]; then
        local weburl=""
        weburl=$(printf '%s' "$exec_line" | grep -oE 'https://[^[:space:]\"'\'']+' | grep -v deeplink | tail -1)
        [[ -z $weburl ]] && weburl=$(printf '%s' "$exec_line" | grep -oE 'https://[^[:space:]\"'\'']+' | tail -1)
        [[ -n $weburl ]] && exec_line="omarchy-launch-webapp '$weburl'"
      fi
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$name" "$exec_line" "$icon" "$icon_path" "$file" "$score"
    done < <(find "$dir" -maxdepth 1 -name "*.desktop" -print0 2>/dev/null)
  done
}

cmd_status() {
  ensure_config
  local count enabled_count profile_count
  count=$(jq_config '[.profiles[]?.assignments[]?] | length' 2>/dev/null || echo 0)
  enabled_count=$(jq_config '[.profiles[]?.assignments[]? | select(.enabled==true)] | length' 2>/dev/null || echo 0)
  profile_count=$(jq_config '.profiles | length' 2>/dev/null || echo 0)
  local enabled apply_on_boot
  enabled=$(jq_config -r '.settings.enabled // true' 2>/dev/null)
  apply_on_boot=$(jq_config -r '.settings.applyOnBoot // false' 2>/dev/null)
  cat <<EOF
{
  "configFile": "$CONFIG_FILE",
  "total": $count,
  "enabled": $enabled_count,
  "profiles": $profile_count,
  "pluginEnabled": $enabled,
  "applyOnBoot": $apply_on_boot,
  "exists": true
}
EOF
}

wait_for_hyprland() {
  local timeout=20 tries=0
  while ! hyprctl -j version >/dev/null 2>&1; do
    tries=$((tries + 1))
    if ((tries >= timeout)); then
      echo "hyprctl not ready after ${timeout}s, aborting launch" >&2
      return 1
    fi
    sleep 1
  done
  return 0
}

wait_for_lan() {
  local n
  for n in 1 2 3 4 5 6 7 8 9 10; do
    if ip -4 route show default 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cmd_launch() {
  local workspace="$1"
  local exec_cmd="$2"
  local silent="${3:-true}"
  local geom_json="${4:-}"
  local cwd="${5:-}"
  local url="${6:-}"
  local app_name="${7:-}"
  local target_mon="${8:-}"
  if [[ -z $workspace || -z $exec_cmd ]]; then
    echo "usage: $0 --launch <workspace> <exec> [silent] [geom-json]" >&2
    exit 1
  fi
  if ! [[ $workspace =~ ^([1-9]|1[0-9]|20)$ ]]; then
    echo "invalid workspace: $workspace" >&2
    exit 1
  fi
  # hl.exec_cmd does not honor Hyprland's "[workspace N silent]" exec prefix —
  # that string is run as a command. Focus the target workspace, then exec.
  local final_cmd="$exec_cmd"
  local name_lc="${app_name,,}"
  # Capture used to store the terminal/qs parent instead of the real launcher.
  if [[ $exec_cmd == "qs" || $exec_cmd == */qs ]]; then
    if [[ $name_lc == *shophawk* ]]; then
      exec_cmd="${HOME}/.local/bin/shophawk-panel"
      final_cmd="$exec_cmd"
    fi
  elif [[ $exec_cmd == "foot" || $exec_cmd == foot\ * ]]; then
    if [[ $name_lc == *herdr* || $name_lc == *omarchyhome* ]]; then
      exec_cmd="${HOME}/.local/bin/herdr-shophawk"
      final_cmd="$exec_cmd"
    fi
  fi
  # outlook-mail focuses an existing Brave tab titled Outlook (often the
  # WS1 browser after session restore) and never creates a WS4 window.
  if [[ $exec_cmd == *outlook-mail* ]]; then
    final_cmd="${HOME}/.local/bin/brave --new-window https://outlook.office.com/mail/"
  elif [[ ${exec_cmd##*/} == "brave" && $exec_cmd != *--new-window* && $exec_cmd != *http* ]]; then
    final_cmd="$exec_cmd --new-window"
  fi
  if [[ -n $url ]]; then
    if [[ $url == https://* ]] && [[ $url != *"'"* ]] && [[ $url != *'$'* ]] && [[ $url != *'`'* ]] && [[ $url != *$'\n'* ]]; then
      :
    else
      url=""
    fi
  fi
  if [[ -n $cwd ]]; then
    if [[ $cwd == /* && $cwd != *..* && -d $cwd && $cwd =~ ^/[A-Za-z0-9._/+\ -]+$ ]]; then
      :
    else
      cwd=""
    fi
  fi
  if [[ -n $url ]]; then
    if [[ $final_cmd == *omarchy-launch-webapp* ]]; then
      final_cmd="omarchy-launch-webapp '$url'"
    elif [[ $final_cmd == *brave* || $final_cmd == *chromium* ]]; then
      if [[ $final_cmd != *"$url"* ]]; then
        final_cmd="$final_cmd $url"
      fi
    else
      final_cmd="omarchy-launch-webapp '$url'"
    fi
  fi
  if [[ -n $cwd && $final_cmd != *"--app-id="* ]]; then
    local qcwd
    printf -v qcwd '%q' "$cwd"
    if [[ $final_cmd == foot || $final_cmd == foot\ * ]]; then
      final_cmd="foot --working-directory=$qcwd${final_cmd#foot}"
    elif [[ $final_cmd == ghostty || $final_cmd == ghostty\ * ]]; then
      if [[ $final_cmd != *working-directory* ]]; then
        final_cmd="ghostty --working-directory=$qcwd${final_cmd#ghostty}"
      fi
    fi
  fi
  if [[ $exec_cmd == *omarchy-launch-webapp* ]]; then
    local weburl="${url:-}"
    if [[ -z $weburl ]]; then
      weburl=$(printf '%s' "$exec_cmd" | grep -oE 'https://[^[:space:]\"'\'']+' | grep -v deeplink | tail -1)
      [[ -z $weburl ]] && weburl=$(printf '%s' "$exec_cmd" | grep -oE 'https://[^[:space:]\"'\'']+' | tail -1)
    fi
    if [[ -n $weburl ]]; then
      final_cmd="omarchy-launch-webapp '$weburl'"
    fi
  fi
  local base_for_tui
  base_for_tui=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null)
  case "$base_for_tui" in
    nvim|vim|vi|nano|helix|hx|emacs|micro|btop|htop|yazi|ranger|lf|herdr)
      if [[ $exec_cmd != omarchy-launch-tui* && $exec_cmd != omarchy-launch-or-focus-tui* && $exec_cmd != *herdr-shophawk* ]]; then
        local tui_args="${exec_cmd#"$base_for_tui"}"
        tui_args=$(printf '%s' "$tui_args" | sed 's/^ *//')
        if [[ -n $tui_args ]]; then
          final_cmd="omarchy-launch-tui --app-id=org.omarchy.$base_for_tui $base_for_tui $tui_args"
        else
          final_cmd="omarchy-launch-tui --app-id=org.omarchy.$base_for_tui $base_for_tui"
        fi
      fi
      ;;
    *)
      if [[ $final_cmd != uwsm-app* && $final_cmd != omarchy-launch* && $final_cmd != *chromium* && $final_cmd != *google-chrome* && $final_cmd != *brave* && $final_cmd != *firefox* ]]; then
        if [[ $exec_cmd =~ ^[a-zA-Z0-9._-]+$ || $exec_cmd =~ ^[a-zA-Z0-9._-]+[[:space:]] ]]; then
          final_cmd="uwsm-app -- $final_cmd"
        fi
      fi
      ;;
  esac
  local dispatch_cmd="$final_cmd"
  local lua_escaped
  lua_escaped=$(printf '%s' "$dispatch_cmd" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  local is_browser_like="false"
  local is_tui_like="false"
  if [[ $final_cmd == *"chromium"* || $final_cmd == *"chrome"* || $final_cmd == *"brave"* || $final_cmd == *"omarchy-launch-webapp"* ]]; then
    is_browser_like="true"
  fi
  case "$base_for_tui" in
    nvim|vim|vi|nano|helix|hx|emacs|micro|btop|htop|yazi|ranger|lf|herdr) is_tui_like="true" ;;
  esac

  local before prev_ws
  before=$(hypr_clients_json | jq -r '.[].address' 2>/dev/null | sort -u | tr '\n' ' ')
  prev_ws=$(hyprctl -j activeworkspace </dev/null 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
  # Pin the workspace to its monitor without focusing it. Empty workspaces
  # follow the focused monitor (I-012); a workspace_rule + move is enough.
  if [[ -n $target_mon && $target_mon =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ && $target_mon != *HEADLESS* ]]; then
    local pin_layout="${9:-dwindle}"
    case "$pin_layout" in
      dwindle|scrolling|master) ;;
      *) pin_layout=dwindle ;;
    esac
    timeout 2 hyprctl eval "$(printf 'hl.workspace_rule({ workspace = "%s", monitor = "%s", persistent = false, layout = "%s" })' "$workspace" "$target_mon" "$pin_layout")" </dev/null >/dev/null 2>&1 || true
    timeout 2 hyprctl eval "$(printf 'hl.dispatch(hl.dsp.workspace.move({ workspace = "%s", monitor = "%s" }))' "$workspace" "$target_mon")" </dev/null >/dev/null 2>&1 || true
  fi

  local launched=0
  local silent_on=0
  [[ $silent == "true" || $silent == "1" ]] && silent_on=1
  # After a dock layout change, hl.exec_cmd can block on DRM/page-flip.
  # Cap each attempt so Fresh Workscape still launches the rest of the profile.
  if ((silent_on)); then
    local rules
    printf -v rules '{ workspace = "%s silent", no_initial_focus = true, tile = true }' "$workspace"
    if timeout 3 hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"$lua_escaped\", $rules))" </dev/null >/dev/null 2>&1; then
      launched=1
    fi
  fi
  if ((launched == 0)); then
    if timeout 3 hyprctl eval "hl.dispatch(hl.dsp.exec_cmd(\"$lua_escaped\"))" </dev/null >/dev/null 2>&1 \
      || timeout 3 hyprctl eval "hl.exec_cmd(\"$lua_escaped\")" </dev/null >/dev/null 2>&1 \
      || timeout 3 hyprctl dispatch exec "$dispatch_cmd" </dev/null >/dev/null 2>&1; then
      launched=1
    fi
  fi
  if ((launched == 0)); then
    echo "failed to execute launch command on workspace $workspace: $final_cmd" >&2
    return 1
  fi
  # If a fallback exec stole focus, put the user back.
  if [[ -n $prev_ws ]]; then
    local now_ws
    now_ws=$(hyprctl -j activeworkspace </dev/null 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -n $now_ws && $now_ws != "$prev_ws" ]]; then
      timeout 2 hyprctl eval "$(printf 'hl.dispatch(hl.dsp.focus({ workspace = "%s" }))' "$prev_ws")" </dev/null >/dev/null 2>&1 || true
    fi
  fi

  local target_ws="$workspace"
  local ok=false
  local tries=12
  local delay=0.08
  if [[ ${exec_cmd,,} == *grok-bot* || ${final_cmd,,} == *brave* || ${exec_cmd,,} == *outlook* ]]; then
    tries=20
    delay=0.1
  fi
  if [[ -z $app_name ]]; then
    app_name=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null || echo "")
  fi
  local placed_addrs=()
  local clients_json
  for _try in $(seq 1 $tries); do
    local new_addrs moved=0
    clients_json=$(hypr_clients_json)
    new_addrs=$(printf '%s' "$clients_json" | jq -r --arg before "$before" '
      ($before | split(" ") | map(select(length>0))) as $old |
      [.[].address] | map(select(. as $a | ($old | index($a) | not))) | .[]
    ' 2>/dev/null)
    if [[ -n $new_addrs ]]; then
      while IFS= read -r addr; do
        [[ -z $addr ]] && continue
        local cls on_ws
        cls=$(printf '%s' "$clients_json" | jq -r --arg a "$addr" '.[] | select(.address==$a) | .class // empty' 2>/dev/null)
        if [[ $is_browser_like == "true" ]]; then
          if ! [[ ${cls,,} =~ chrome|chromium|brave|vivaldi|edge ]]; then
            continue
          fi
        elif [[ $is_tui_like == "true" ]]; then
          if ! [[ $cls =~ foot|org\.omarchy|herdr ]] && ! [[ ${cls,,} =~ foot|nvim|herdr ]]; then
            continue
          fi
        fi
        on_ws=$(printf '%s' "$clients_json" | jq -r --arg a "$addr" --arg ws "$target_ws" '
          def ws_ok($ws):
            if ($ws|test("^[0-9]+$")) then
              (.workspace.id == ($ws|tonumber) or .workspace.name == $ws)
            else
              .workspace.name == $ws
            end;
          .[] | select(.address == $a) | if ws_ok($ws) then "true" else "false" end
        ' 2>/dev/null)
        if [[ $on_ws != "true" ]]; then
          move_window_to_ws "$addr" "$target_ws"
        fi
        if [[ -n $target_mon ]]; then
          move_workspace_to_monitor "$target_ws" "$target_mon"
        fi
        moved=$((moved + 1))
        placed_addrs+=("$addr")
      done <<< "$new_addrs"
      if ((moved > 0)); then
        ok=true
        break
      fi
    fi
    # Unique apps (Grok Bot) often map after we would have left this workspace.
    local existing
    existing=$(find_existing_addr "$exec_cmd" "$app_name" "$clients_json" "$target_ws" "")
    if [[ -z $existing && $(browser_reuse_only_on_target "$exec_cmd") != "true" ]]; then
      existing=$(find_existing_addr "$exec_cmd" "$app_name" "$clients_json" "" "")
    fi
    if [[ -n $existing ]]; then
      move_window_to_ws "$existing" "$target_ws"
      ok=true
      break
    fi
    sleep "$delay"
  done
  # Geometry is applied in a second pass after every assignment has launched.

  if [[ $ok != "true" ]]; then
    echo "warn: no new window detected for workspace $workspace: $final_cmd (may have reused existing window)" >&2
  fi
  if [[ ${WORKSCAPE_RESTORE_FOCUS:-1} != "0" && -n $prev_ws && $prev_ws != "$workspace" ]]; then
    hyprctl eval "$(printf 'hl.dispatch(hl.dsp.focus({ workspace = "%s" }))' "$prev_ws")" </dev/null >/dev/null 2>&1 || true
  fi
  return 0
}

default_only_on_boot_for_type() {
  local type="${1:-app}"
  if [[ $type == "app" ]]; then
    echo "false"
  else
    echo "true"
  fi
}

find_existing_addr() {
  local exec_cmd=$1 name=$2 clients_json=$3
  local target_ws=${4:-}
  local used=${5:-}
  local needle=""
  needle=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null)
  needle=$(basename "$needle" 2>/dev/null || echo "$needle")
  needle="${needle,,}"
  case "$needle" in
    sh|bash|uwsm-app|omarchy-launch-webapp|omarchy-launch-tui|omarchy-launch-or-focus-tui) needle="" ;;
  esac
  local app_id="" host=""
  if [[ $exec_cmd =~ --app-id=([^[:space:]]+) ]]; then
    app_id="${BASH_REMATCH[1],,}"
  fi
  if [[ $exec_cmd =~ https://([^/\"\']+) ]]; then
    host="${BASH_REMATCH[1],,}"
    host="${host#www.}"
  fi
  printf '%s' "$clients_json" | jq -r --arg n "$needle" --arg appid "$app_id" --arg name "${name,,}" --arg exec "${exec_cmd,,}" --arg host "$host" --arg ws "$target_ws" --arg used "$used" '
    def cls: ((.class // "") | ascii_downcase);
    def hay: (cls + " " + ((.initialClass // "") | ascii_downcase) + " " + ((.title // "") | ascii_downcase));
    def leave_alone: (cls == "foot" or cls == "com.mitchellh.ghostty") and (hay | test("hyprland workscape"));
    def is_site_app: cls | test("^(brave|chrome|chromium|google-chrome)-[a-z0-9].*\\.");
    def browser_main: cls == "brave-browser" or cls == "brave" or cls == "chromium" or cls == "google-chrome" or cls == "chromium-browser";
    def on_target:
      ($ws == "") or ((.workspace.id|tostring) == $ws) or (.workspace.name == $ws);
    def hit:
      if $host != "" then
        (hay | contains($host)) and on_target
      elif ($name | test("herdr|omarchyhome") or ($exec | contains("herdr"))) then
        (cls | test("herdr")) and on_target
      elif ($name | test("shophawk")) and ($name | test("herdr") | not) then
        (hay | contains("shophawk")) and (hay | contains("herdr") | not) and on_target
      elif ($n == "qs" or $n == "quickshell" or ($exec | contains("shophawk-panel"))) then
        cls == "org.quickshell" and (hay | contains("shophawk")) and (hay | contains("herdr") | not) and on_target
      elif ($n == "outlook-mail" or $name == "outlook") then
        (cls | test("outlook")) and on_target
      elif ($n == "foot" or $n == "ghostty") then
        (cls == $n or cls == "foot") and on_target
      elif ($n == "brave" or $n == "brave-browser" or $n == "chromium" or $n == "chrome" or $n == "google-chrome") then
        browser_main and (is_site_app | not) and on_target
      elif ($exec | contains("herdr")) then
        hay | contains("herdr")
      elif ($exec | contains("shophawk-panel")) then
        hay | contains("shophawk") and (hay | contains("herdr") | not)
      elif $appid != "" then
        hay | contains($appid)
      elif $n != "" and $n != "." then
        (cls == $n) or (hay | contains($n))
      elif $name != "" then
        hay | contains($name)
      else
        false
      end;
    def used_set: ($used | split(" ") | map(select(length>0)));
    [.[] | select((.address as $a | (used_set | index($a) | not)) and hit and (leave_alone | not))]
    | sort_by(if ($ws != "" and ((.workspace.id|tostring) == $ws or .workspace.name == $ws)) then 0 else 1 end)
    | .[0].address // empty
  ' 2>/dev/null
}

# Browsers and site webapps can have extras on unassigned workspaces.
# Reuse must not steal those. Unique apps (Grok Bot, Herdr, …) may.
browser_reuse_only_on_target() {
  local exec_cmd=$1
  local needle=""
  needle=$(printf '%s' "$exec_cmd" | awk '{print $1}' | xargs basename 2>/dev/null)
  needle=$(basename "$needle" 2>/dev/null || echo "$needle")
  needle="${needle,,}"
  if [[ $exec_cmd =~ https:// ]]; then
    echo "true"
    return
  fi
  case "$needle" in
    brave|brave-browser|chromium|chrome|google-chrome|firefox|outlook-mail|foot) echo "true" ;;
    *) echo "false" ;;
  esac
}

place_existing_on_ws() {
  local exec_cmd=$1 name=$2 clients_json=$3 ws=$4 used=$5
  local existing protected
  existing=$(find_existing_addr "$exec_cmd" "$name" "$clients_json" "$ws" "$used")
  if [[ -z $existing ]]; then
    protected=$(browser_reuse_only_on_target "$exec_cmd")
    if [[ $protected == "true" ]]; then
      return 1
    fi
    existing=$(find_existing_addr "$exec_cmd" "$name" "$clients_json" "" "$used")
  fi
  if [[ -z $existing ]]; then
    return 1
  fi
  move_window_to_ws "$existing" "$ws"
  printf '%s\n' "$existing"
  return 0
}

move_window_to_ws() {
  local addr=$1 ws=$2
  [[ $ws =~ ^([1-9]|10)$ ]] || return 0
  [[ $addr =~ ^0x[0-9a-fA-F]+$ ]] || return 0
  hyprctl eval "$(printf 'hl.dispatch(hl.dsp.window.move({workspace="%s", window="address:%s", follow=false}))' "$ws" "$addr")" >/dev/null 2>&1 || true
}

ensure_profile_windows() {
  local profile_id=$1
  local attempt item ws exec_cmd name existing clients_json missing used
  for attempt in 1 2 3 4; do
    missing=0
    used=""
    clients_json=$(hypr_clients_json)
    while IFS= read -r item; do
      [[ -n $item ]] || continue
      ws=$(echo "$item" | jq -r '.workspace')
      exec_cmd=$(echo "$item" | jq -r '.exec // .command // empty')
      name=$(echo "$item" | jq -r '.name // empty')
      if [[ $(echo "$item" | jq -r '.enabled // true') != "true" ]]; then
        continue
      fi
      [[ -n $ws && -n $exec_cmd ]] || continue
      existing=$(place_existing_on_ws "$exec_cmd" "$name" "$clients_json" "$ws" "$used")
      if [[ -z $existing ]]; then
        missing=1
        echo "wait $name for ws $ws (attempt $attempt)" >&2
        continue
      fi
      used+="$existing "
    done < <(profile_assignments "$profile_id")
    if ((missing == 0)); then
      return 0
    fi
    sleep 0.15
  done
  return 0
}

launch_profile_assignments() {
  local profile_id=$1
  local force=${2:-false}

  local only_on_boot_global boot_id last_boot stagger silent
  only_on_boot_global=$(jq_config -r '.settings.onlyOnBoot // true')
  boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")
  last_boot=$(state_get last_boot_id | tr -d '\n')
  stagger=$(jq_config -r '.settings.staggerMs // 80')
  if ! [[ $stagger =~ ^[0-9]+$ ]]; then stagger=80; fi
  if ((stagger > 2000)); then stagger=2000; fi
  silent=$(jq_config -r '.settings.silent // true')
  local boot_log="${STATE_DIR}/launch.log"
  local clients_json used_addrs=""
  clients_json=$(hypr_clients_json)
  local occupied_ws="${WORKSCAPE_OCCUPIED_WS:-}"
  if [[ -z $occupied_ws ]]; then
    occupied_ws=$(printf '%s' "$clients_json" | jq -r '[.[] | (.workspace.id|tostring)] | unique | join(" ")' 2>/dev/null || echo "")
    export WORKSCAPE_OCCUPIED_WS="$occupied_ws"
  fi
  local pinned_ws
  pinned_ws=$(jq_config -c --arg id "$profile_id" '([.profiles[] | select(.id==$id) | .workspaceMonitors][0] // {})' 2>/dev/null || echo "{}")
  local apply_prev_ws
  apply_prev_ws=$(hyprctl -j activeworkspace </dev/null 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
  export WORKSCAPE_RESTORE_FOCUS=0
  local launch_mons="{}"
  launch_mons=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --bindings 2>/dev/null || echo "{}")

  # set -u: leftover boot_log appends from an earlier I/O harden that
  # dropped the assignment. Apply matching dies on the first launch without this.
  local boot_log="$STATE_DIR/launch-$boot_id.log"
  : > "$boot_log" 2>/dev/null || true
  echo "$(date -u) boot_id=$boot_id profile=$profile_id force=$force" >> "$boot_log" 2>/dev/null || true

  local idx=0 item
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    local ws exec_cmd name type
    ws=$(echo "$item" | jq -r '.workspace')
    exec_cmd=$(echo "$item" | jq -r '.exec // .command // empty')
    name=$(echo "$item" | jq -r '.name // empty')
    type=$(echo "$item" | jq -r '.type // "app"')
    local enabled
    enabled=$(echo "$item" | jq -r '.enabled // true')
    if [[ $enabled != "true" ]]; then
      continue
    fi
    if [[ -z $ws || -z $exec_cmd ]]; then
      echo "skip invalid item: $item" >&2
      continue
    fi
    local pin
    pin=$(printf '%s' "$pinned_ws" | jq -r --arg ws "$ws" '.[$ws] // empty')
    if [[ -n $pin ]]; then
      local pin_off
      pin_off=$(jq_config -r --arg id "$profile_id" --arg pin "$pin" '
        [.profiles[] | select(.id==$id) | .disabledMonitors[]?] | index($pin) | if . == null then "no" else "yes" end
      ' 2>/dev/null)
      if [[ $pin_off == "yes" ]]; then
        echo "skip $name on ws $ws — target display is off"
        continue
      fi
    fi

    local item_only
    item_only=$(echo "$item" | jq -r 'if has("onlyOnBoot") then .onlyOnBoot else empty end')
    if [[ -z $item_only || $item_only == "null" ]]; then
      item_only=$(default_only_on_boot_for_type "$type")
      [[ -z $item_only ]] && item_only="$only_on_boot_global"
    fi
    if [[ $item_only == "1" ]]; then item_only="true"; fi
    if [[ $item_only == "0" ]]; then item_only="false"; fi
    if [[ $item_only == "true" && $force != "true" && -n $last_boot && $last_boot == "$boot_id" ]]; then
      echo "skip $name on ws $ws — already launched this boot (once per boot)"
      continue
    fi

    if [[ " $occupied_ws " == *" $ws "* ]]; then
      echo "skip $name on ws $ws — workspace already has windows"
      echo "$(date -u) SKIP occupied ws=$ws name=$name" >> "$boot_log" 2>/dev/null || true
      continue
    fi

    local existing
    existing=$(place_existing_on_ws "$exec_cmd" "$name" "$clients_json" "$ws" "$used_addrs")
    if [[ -n $existing ]]; then
      echo "reuse $name ($existing) on ws $ws"
      echo "$(date -u) REUSE ws=$ws name=$name addr=$existing" >> "$boot_log" 2>/dev/null || true
      used_addrs+="$existing "
      clients_json=$(hypr_clients_json)
      continue
    fi

    echo "launching [$ws] $name: $exec_cmd (silent=$silent)"
    echo "$(date -u) START ws=$ws name=$name exec=$exec_cmd" >> "$boot_log" 2>/dev/null || true
    if ((idx > 0)) && [[ $stagger -gt 0 ]]; then
      sleep "$(awk "BEGIN {print $stagger/1000}")"
    fi
    local ws_mon=""
    ws_mon=$(printf '%s' "$launch_mons" | jq -r --arg ws "$ws" '.[$ws] // empty' 2>/dev/null || true)
    local geom_json
    geom_json=$(echo "$item" | jq -c '.geom // empty')
    local cwd url
    cwd=$(echo "$item" | jq -r '.cwd // empty')
    url=$(echo "$item" | jq -r '.url // empty')
    # hyprctl reads stdin — must not steal the assignment stream
    local ws_layout
    ws_layout=$(jq_config -r --arg id "$profile_id" --arg ws "$ws" '
      (.profiles[] | select(.id==$id) | .workspacePrefs[$ws].layout) // "dwindle"
    ' 2>/dev/null || echo dwindle)
    local lock_n
    lock_n=$(jq_config -r --arg id "$profile_id" --arg ws "$ws" '
      [.profiles[] | select(.id==$id) | .assignments[]? | select((.workspace|tostring)==$ws and .lockPlace==true)] | length
    ' 2>/dev/null || echo 0)
    if [[ $lock_n =~ ^[0-9]+$ ]] && (( lock_n >= 2 )); then
      ws_layout=dwindle
    fi
    if cmd_launch "$ws" "$exec_cmd" "$silent" "$geom_json" "$cwd" "$url" "$name" "$ws_mon" "$ws_layout" </dev/null; then
      echo "$(date -u) OK ws=$ws name=$name" >> "$boot_log" 2>/dev/null || true
    else
      echo "$(date -u) FAIL ws=$ws name=$name" >> "$boot_log" 2>/dev/null || true
      echo "failed to launch $name" >&2
    fi
    clients_json=$(hypr_clients_json)
    existing=$(place_existing_on_ws "$exec_cmd" "$name" "$clients_json" "$ws" "$used_addrs")
    if [[ -n $existing ]]; then
      used_addrs+="$existing "
      echo "$(date -u) PLACE ws=$ws name=$name addr=$existing" >> "$boot_log" 2>/dev/null || true
      if [[ -n $ws_mon ]]; then
        move_workspace_to_monitor "$ws" "$ws_mon"
      fi
    fi
    idx=$((idx + 1))
  done < <(profile_assignments "$profile_id")

  echo "ensuring assigned windows are on their workspaces"
  ensure_profile_windows "$profile_id"
  apply_bindings "$launch_mons"

  echo "sweeping extras off blocked workspaces"
  python3 "$PLUGIN_DIR/scripts/watch" --sweep || true

  echo "applying window geometry for $profile_id"
  sleep 0.2
  apply_profile_geoms "$profile_id"

  if [[ $apply_prev_ws =~ ^[1-9][0-9]?$ ]] && (( apply_prev_ws <= 20 )); then
    hyprctl eval "$(printf 'hl.dispatch(hl.dsp.focus({ workspace = "%s" }))' "$apply_prev_ws")" </dev/null >/dev/null 2>&1 || true
  fi
  unset WORKSCAPE_RESTORE_FOCUS

  state_put last_boot_id "$boot_id"
  echo "done"
}

install_hypr_lua() {
  # Copy Super+arrow / Super+J overlay. Does not edit hyprland.lua.
  local src="$PLUGIN_DIR/hypr/workscape-binds.lua"
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/workscape-binds.lua"
  [[ -f $src ]] || return 0
  python3 "$STATEIO" copy-file "$src" "$dest" || true
  python3 "$GESTURES" --record-owned workscape-binds.lua --hypr-dir "$(dirname "$dest")" >/dev/null || true
}

cmd_apply() {
  local mode=$1
  local requested_id=${2:-}
  local force=${3:-false}
  ensure_isolated
  ensure_config || exit 1
  wait_for_hyprland || exit 1
  install_hypr_lua || true
  python3 "$GESTURES" --config "$CONFIG_FILE" --profile-id "${requested_id:-}" --apply >/dev/null || true
  python3 "$HOTKEYS" --config "$CONFIG_FILE" --plugin-dir "$PLUGIN_DIR" --apply >/dev/null || true

  local enabled
  enabled=$(jq_config -r '.settings.enabled // true')
  if [[ $enabled != "true" && $force != "true" && $mode == "boot" ]]; then
    echo "plugin disabled, skipping (use --force to override)" >&2
    exit 0
  fi

  if [[ $mode == "boot" ]]; then
    local apply_on_boot
    apply_on_boot=$(jq_config -r '.settings.applyOnBoot // false')
    if [[ $apply_on_boot != "true" && $force != "true" ]]; then
      echo "apply on boot disabled — use hotkey or Apply now"
      exit 0
    fi
    # Same kernel boot_id means this is a shell restart (plugin install),
    # not a new login. Re-applying would resize existing windows.
    local boot_id last_boot
    boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")
    last_boot=$(state_get last_boot_id | tr -d '\n')
    if [[ $force != "true" && -n $boot_id && -n $last_boot && $last_boot == "$boot_id" ]]; then
      echo "already applied this login — skip shell restart"
      exit 0
    fi
    local needs_identity
    needs_identity=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --needs-identity 2>/dev/null || echo yes)
    if [[ $needs_identity == "yes" ]]; then
      echo "no fallback for this layout — waiting for LAN / Wi-Fi identity…"
      wait_for_lan || true
      python3 "$PLUGIN_DIR/scripts/network" --wait-identity 45 >/dev/null || true
    fi
  fi

  local status_json profile_id profile_name bindings attempt
  status_json=$(cmd_live_status)
  if [[ -n $requested_id ]]; then
    profile_must_match "$requested_id" || exit 1
    profile_id=$requested_id
    profile_name=$(jq_config -r --arg id "$profile_id" '([.profiles[]? | select(.id==$id) | .name][0] // $id)')
    bindings=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --bindings)
  else
    profile_id=$(printf '%s' "$status_json" | jq -r '.matchedProfileId // empty')
    profile_name=$(printf '%s' "$status_json" | jq -r '.matchedProfileName // empty')
    bindings=$(printf '%s' "$status_json" | jq -c '.bindings // {}')
    if [[ $mode == "boot" ]]; then
      for attempt in 1 2 3 4 5 6 7 8; do
        if [[ -n $profile_id && $profile_id != "null" ]]; then
          break
        fi
        echo "no match yet (try $attempt), waiting for network…"
        sleep 3
        status_json=$(cmd_live_status)
        profile_id=$(printf '%s' "$status_json" | jq -r '.matchedProfileId // empty')
        profile_name=$(printf '%s' "$status_json" | jq -r '.matchedProfileName // empty')
        bindings=$(printf '%s' "$status_json" | jq -c '.bindings // {}')
      done
    fi
  fi

  if [[ -z $profile_id || $profile_id == "null" ]]; then
    echo "no matching profile for the current monitor layout"
    notify "WorkScape" "No profile matches the current monitors"
    exit 0
  fi

  echo "applying profile $profile_name ($profile_id)"
  local clients_now occupied_ws last_applied
  clients_now=$(hypr_clients_json)
  occupied_ws=$(printf '%s' "$clients_now" | jq -r '[.[] | (.workspace.id|tostring)] | unique | join(" ")' 2>/dev/null || echo "")
  export WORKSCAPE_OCCUPIED_WS="$occupied_ws"
  unset WORKSCAPE_MIGRATE_OCCUPIED
  last_applied=$(state_get last_applied_profile | tr -d '\n')
  if [[ -n $profile_id && $last_applied != "$profile_id" ]]; then
    export WORKSCAPE_MIGRATE_OCCUPIED=1
    echo "profile changed (${last_applied:-none} → $profile_id) — moving occupied workspaces onto this layout"
  fi
  local ws_snap
  ws_snap=$(snapshot_workspaces)
  apply_profile_outputs "$profile_id"
  sleep 0.35
  status_json=$(cmd_live_status)
  if [[ -n $requested_id ]]; then
    bindings=$(live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --bindings)
  else
    bindings=$(printf '%s' "$status_json" | jq -c '.bindings // {}')
  fi
  restore_unpinned_workspaces "$ws_snap" "$bindings"
  apply_bindings "$bindings"
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --apply-ws-prefs >/dev/null || true
  python3 "$GESTURES" --config "$CONFIG_FILE" --profile-id "$profile_id" --apply --extras >/dev/null || true
  restore_unpinned_workspaces "$ws_snap" "$bindings"
  # Hotkey still bypasses "once per boot", but never relaunches a window
  # that is already on the workspace (duplicate Apply was stacking apps).
  local launch_force=$force
  if [[ $mode == "hotkey" ]]; then
    launch_force=true
  fi
  launch_profile_assignments "$profile_id" "$launch_force"
  state_put last_applied_profile "$profile_id"
  notify "WorkScape" "Applied $profile_name"
}

close_preset_workspaces() {
  local profile_id=$1
  local ws addr
  while IFS= read -r ws; do
    [[ $ws =~ ^([1-9]|1[0-9]|20)$ ]] || continue
    while IFS= read -r addr; do
      [[ $addr =~ ^0x[0-9a-fA-F]+$ ]] || continue
      hyprctl eval "$(printf 'hl.dispatch(hl.dsp.window.close({ window = "address:%s" }))' "$addr")" >/dev/null 2>&1 || true
      echo "close $addr on ws $ws"
    done < <(hypr_clients_json | jq -r --arg ws "$ws" '.[] | select((.workspace.id|tostring) == $ws) | .address // empty' 2>/dev/null)
  done < <(jq_config -r --arg id "$profile_id" '
    [.profiles[]? | select(.id==$id) | .assignments[]? | .workspace | tostring]
    | unique | .[]
  ' 2>/dev/null)
}

cmd_reset_empty() {
  local profile_id=${1:-}
  ensure_config || exit 1
  wait_for_hyprland || exit 1
  if [[ -z $profile_id ]]; then
    profile_id=$(cmd_live_status | jq -r '.matchedProfileId // empty')
  fi
  if [[ -z $profile_id || $profile_id == "null" ]]; then
    echo "no profile"
    exit 1
  fi
  profile_must_match "$profile_id" || exit 1
  local occupied
  occupied=$(hypr_clients_json | jq -r '[.[] | (.workspace.id|tostring)] | unique | join(" ")' 2>/dev/null || true)
  export WORKSCAPE_OCCUPIED_WS="$occupied"
  live_monitors_json | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --reset-empty
}

cmd_fresh_apply() {
  local profile_id=${1:-}
  ensure_isolated
  ensure_config || exit 1
  wait_for_hyprland || exit 1
  if [[ -z $profile_id ]]; then
    profile_id=$(cmd_live_status | jq -r '.matchedProfileId // empty')
  fi
  if [[ -z $profile_id || $profile_id == "null" ]]; then
    echo "no profile to refresh"
    exit 1
  fi
  profile_must_match "$profile_id" || exit 1
  echo "closing windows on $profile_id preset workspaces…"
  close_preset_workspaces "$profile_id"
  local assigned leftover n
  assigned=$(jq_config -r --arg id "$profile_id" '[.profiles[] | select(.id==$id) | .assignments[].workspace | tostring] | unique | join(" ")')
  for n in 1 2 3 4 5 6 7 8 9 10; do
    leftover=$(hypr_clients_json | jq -r --arg ws "$assigned" '
      ($ws | split(" ")) as $a
      | [.[] | select((.workspace.id|tostring) as $id | $a | index($id))] | length
    ' 2>/dev/null || echo 1)
    if [[ $leftover == "0" ]]; then
      break
    fi
    sleep 0.12
  done
  unset WORKSCAPE_OCCUPIED_WS
  cmd_apply hotkey "$profile_id" true
}

cmd_apply_hotkeys() {
  ensure_config || exit 1
  python3 "$HOTKEYS" --config "$CONFIG_FILE" --plugin-dir "$PLUGIN_DIR" --apply
}

cmd_apply_workspace_here() {
  local src=${1:-}
  ensure_isolated
  ensure_config || exit 1
  wait_for_hyprland || exit 1
  if ! [[ $src =~ ^([1-9]|10)$ ]]; then
    echo "invalid source workspace: $src" >&2
    exit 1
  fi
  local dest
  dest=$(timeout 2 hyprctl -j activeworkspace </dev/null 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
  dest=${dest//$'\n'/}
  if ! [[ $dest =~ ^([1-9]|1[0-9]|20)$ ]]; then
    echo "no focused workspace"
    notify "WorkScape" "No focused workspace"
    exit 1
  fi
  local status_json profile_id
  status_json=$(cmd_live_status)
  profile_id=$(printf '%s' "$status_json" | jq -r '.matchedProfileId // empty')
  if [[ -z $profile_id || $profile_id == "null" ]]; then
    echo "no matching profile for the current monitor layout"
    notify "WorkScape" "No profile matches the current monitors"
    exit 0
  fi
  profile_must_match "$profile_id" || exit 1
  local count
  count=$(jq_config -r --arg id "$profile_id" --arg ws "$src" '
    [.profiles[] | select(.id==$id) | .assignments[]? | select((.workspace|tostring)==$ws and .enabled != false)] | length
  ' 2>/dev/null || echo 0)
  if ! [[ $count =~ ^[0-9]+$ ]] || (( count < 1 )); then
    echo "no apps on workspace $src"
    notify "WorkScape" "WS $src has no saved apps in the matching profile"
    exit 0
  fi
  local clients_json occupied_ws
  clients_json=$(hypr_clients_json)
  occupied_ws=$(printf '%s' "$clients_json" | jq -r '[.[] | (.workspace.id|tostring)] | unique | join(" ")' 2>/dev/null || echo "")
  if [[ " $occupied_ws " == *" $dest "* ]]; then
    echo "skip open-here — workspace $dest already has windows"
    notify "WorkScape" "WS $dest already has windows — switch to an empty workspace first"
    exit 0
  fi
  export WORKSCAPE_OCCUPIED_WS="$occupied_ws"
  echo "opening WS $src layout on focused WS $dest"
  echo "[]" | python3 "$MATCH" --config "$CONFIG_FILE" --profile-id "$profile_id" --apply-one-pref --src "$src" --dest "$dest" >/dev/null || true
  local stagger silent
  stagger=$(jq_config -r '.settings.staggerMs // 80')
  if ! [[ $stagger =~ ^[0-9]+$ ]]; then stagger=80; fi
  if ((stagger > 2000)); then stagger=2000; fi
  silent=$(jq_config -r '.settings.silent // true')
  local ws_layout
  ws_layout=$(jq_config -r --arg id "$profile_id" --arg ws "$src" '
    (.profiles[] | select(.id==$id) | .workspacePrefs[$ws].layout) // "dwindle"
  ' 2>/dev/null || echo dwindle)
  local lock_n
  lock_n=$(jq_config -r --arg id "$profile_id" --arg ws "$src" '
    [.profiles[] | select(.id==$id) | .assignments[]? | select((.workspace|tostring)==$ws and .lockPlace==true)] | length
  ' 2>/dev/null || echo 0)
  if [[ $lock_n =~ ^[0-9]+$ ]] && (( lock_n >= 2 )); then
    ws_layout=dwindle
  fi
  local idx=0 item used_addrs=""
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    local item_ws exec_cmd name enabled geom_json cwd url
    item_ws=$(echo "$item" | jq -r '.workspace')
    [[ $item_ws == "$src" ]] || continue
    enabled=$(echo "$item" | jq -r '.enabled // true')
    [[ $enabled == "true" ]] || continue
    exec_cmd=$(echo "$item" | jq -r '.exec // .command // empty')
    name=$(echo "$item" | jq -r '.name // empty')
    [[ -n $exec_cmd ]] || continue
    geom_json=$(echo "$item" | jq -c '.geom // empty')
    cwd=$(echo "$item" | jq -r '.cwd // empty')
    url=$(echo "$item" | jq -r '.url // empty')
    if ((idx > 0)) && [[ $stagger -gt 0 ]]; then
      sleep "$(awk "BEGIN {print $stagger/1000}")"
    fi
    echo "launching [$dest] $name (from WS $src)"
    cmd_launch "$dest" "$exec_cmd" "$silent" "$geom_json" "$cwd" "$url" "$name" "" "$ws_layout" </dev/null || true
    clients_json=$(hypr_clients_json)
    idx=$((idx + 1))
  done < <(profile_assignments "$profile_id")
  python3 "$GEOM" --apply-config --config "$CONFIG_FILE" --profile-id "$profile_id" --remap "${src}:${dest}" || true
  hyprctl eval "$(printf 'hl.dispatch(hl.dsp.focus({ workspace = "%s" }))' "$dest")" </dev/null >/dev/null 2>&1 || true
  notify "WorkScape" "Opened WS $src layout on WS $dest"
  echo "done"
}

cmd_launch_all() {
  local force="${1:-false}"
  cmd_apply boot "" "$force"
}

case "${1:-}" in
  --ensure-config) cmd_ensure_config ;;
  --write-config) cmd_write_config "$@" ;;
  --hypr-layout) cmd_hypr_layout ;;
  --list-apps) cmd_list_apps ;;
  --status) cmd_status ;;
  --live-status) cmd_live_status ;;
  --sync-active-profile) cmd_sync_active_profile ;;
  --set-output) shift; cmd_set_output "$@" ;;
  --apply-on-monitor-change) cmd_apply_on_monitor_change ;;
  --list-docks) python3 "$PLUGIN_DIR/scripts/dockid" --list ;;
  --capture-dock) python3 "$PLUGIN_DIR/scripts/dockid" --capture ;;
  --match-id) cmd_match_id ;;
  --launch) shift; cmd_launch "$@" ;;
  --launch-all) shift; cmd_launch_all "${1:-false}" ;;
  --force-launch-all) cmd_launch_all "true" ;;
  --apply-matching) cmd_apply hotkey "" true ;;
  --apply-profile) cmd_apply hotkey "${2:-}" true ;;
  --fresh-apply-profile) cmd_fresh_apply "${2:-}" ;;
  --apply-workspace-here) cmd_apply_workspace_here "${2:-}" ;;
  --apply-hotkeys) cmd_apply_hotkeys ;;
  --reset-empty-workspaces) cmd_reset_empty "${2:-}" ;;
  --watch-extras) exec python3 "$PLUGIN_DIR/scripts/watch" ;;
  --capture-workspace) python3 "$PLUGIN_DIR/scripts/capture" --workspace "${2:-1}" ;;
  --apply-gestures) python3 "$GESTURES" --config "$CONFIG_FILE" --profile-id "${2:-}" --apply ;;
  --restore-hypr) python3 "$GESTURES" --restore-hypr ;;
  --default-config) default_config ;;
  --help|-h|"") cat <<'HELP'
workscape.sh — helper for io.github.calebhat.workscape

  --ensure-config              ensure config exists and print it
  --write-config               atomically write config.json from stdin (capped)
  --hypr-layout                print general:layout|scrolling:column_width
  --list-apps                  list .desktop + extra apps as TSV
  --status                     json status
  --live-status                current monitors + matching profile
  --sync-active-profile        set settings.activeProfileId to the matching layout
  --match-id                   print matching profile id
  --set-output <conn> [scale] [WxH@Hz]  set one live output now (empty args keep current)
  --apply-on-monitor-change    wait for displays to settle, then apply the matching profile (scan body)
  --list-docks                 JSON of USB devices usable as dock bindings
  --capture-dock               JSON of the best connected dock candidate (or null)
  --launch <ws> <exec> [silent]  launch single app on workspace
  --launch-all                 boot path (no-op unless applyOnBoot)
  --force-launch-all           launch matching profile regardless of boot flag
  --apply-matching             detect layout, bind workspaces, launch apps
  --apply-profile <id>         bind + launch a specific profile (refused if displays/network don't match)
  --fresh-apply-profile [id]   close that profile's app workspaces, then apply empty (refused if it doesn't match now)
  --apply-workspace-here <n>   launch matching profile WS n onto the focused workspace (skips if occupied)
  --apply-hotkeys              write user hotkeys to hypr/workscape-hotkeys.lua and bind them
  --reset-empty-workspaces [id] restore Omarchy dwindle on workspaces with no assigned apps (keeps Fill-next Stage chain)
  --watch-extras               keep locked panes pinned; send extras away when extras=block
  --apply-gestures             write trackpad / swipe prefs and hyprctl eval them
  --restore-hypr               remove generated Hyprland persist files and the hyprland.lua require
  --default-config             print default config
HELP
  ;;
  *) echo "unknown arg: $1" >&2; exit 1 ;;
esac
