#!/bin/bash
# I-042: Fresh must isolate (lock + detach) before closing windows.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/workscape.sh"
STATEIO="$ROOT/scripts/stateio"

python3 - "$SH" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("cmd_fresh_apply()")
end = text.index("\ncmd_launch_all")
body = text[start:end]
assert "ensure_isolated" in body, "fresh must isolate from the panel Process"
assert "close_preset_workspaces" in body
assert body.index("ensure_isolated") < body.index("close_preset_workspaces"), body
assert "acquire_apply_lock" not in body
assert "reexec_apply_detached" not in body
print("fresh locks before close ok")
PY

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export WORKSCAPE_STATE_DIR=$TMP
python3 "$STATEIO" isolate-apply --timeout 5 -- sleep 2 >/dev/null 2>&1 &
holder=$!
sleep 0.25
out=$(python3 "$STATEIO" isolate-apply --timeout 1 -- true)
wait "$holder" || true
[[ $out == *"apply already in progress"* ]]
echo "held apply.lock refuses second acquire ok"

python3 - "$SH" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("apply_bindings()")
end = text.index("\nprofile_assignments")
body = text[start:end]
assert "bind_workspace_to_monitor" in body
assert "already has windows" not in body, body
assert "WORKSCAPE_MIGRATE_OCCUPIED" in text
assert "profile changed" in text
print("apply matching rebinds occupied pins ok")
PY

python3 - "$SH" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("launch_profile_assignments()")
end = text.index("\ncmd_apply(", start)
body = text[start:end]
assert "boot_log=" in body, "launch_profile_assignments must assign boot_log under set -u"
assert body.index("boot_log=") < body.index('>> "$boot_log"')
print("boot_log assigned before use ok")
PY
