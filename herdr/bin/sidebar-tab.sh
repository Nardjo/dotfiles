#!/bin/sh
# Open the VS Code sidebar in a tab of its own, named rather than numbered.
#
# `plugin pane open --placement tab` makes the tab but gives no way to label it,
# so we create the tab first and run the binary in its root pane. Same result,
# a name you can read in the tab bar.
#
# The plugin checkout path carries a hash, so the binary is resolved through
# the plugin registry instead of being written down.

set -eu

HERDR="${HERDR_BIN_PATH:-herdr}"
LABEL="${1:-explorer}"

root="$("$HERDR" plugin list --json 2>/dev/null | python3 -c '
import json, sys
plugins = json.load(sys.stdin)["result"]["plugins"]
match = [p for p in plugins if p["plugin_id"] == "herdr-sidebar"]
print(match[0]["plugin_root"] if match else "")
')"
[ -n "$root" ] || { echo "herdr-sidebar is not installed" >&2; exit 1; }

bin="$root/target/release/herdr-sidebar"
[ -x "$bin" ] || { echo "sidebar binary not built: $bin" >&2; exit 1; }

out="$("$HERDR" tab create --label "$LABEL" --cwd "$PWD" 2>/dev/null)"
pane="$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])
except Exception:
    print("")
')"
[ -n "$pane" ] || { echo "could not create the tab" >&2; exit 1; }

"$HERDR" pane rename "$pane" Explorer >/dev/null 2>&1 || true
exec "$HERDR" pane run "$pane" "exec '$bin'"
