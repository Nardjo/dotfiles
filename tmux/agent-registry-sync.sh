#!/usr/bin/env bash
# Keeps the agent sidebar's pane list in sync with reality: the plugin only
# tags a pane on SessionStart, so sessions started before the hooks — or whose
# tag got cleared mid-run — vanish from the sidebar even while grok/claude run.
# Every few seconds this tags any pane running grok or claude and untags panes
# that aren't. Live state still comes from hooks; this only fixes presence.
set -uo pipefail

LOCK="/tmp/agent-registry-sync.pid"
if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
echo $$ >"$LOCK"
trap 'rm -f "$LOCK"' EXIT

pane_agent_name() {
  local pid kids k comm
  pid="$(tmux display-message -p -t "$1" '#{pane_pid}' 2>/dev/null)"
  [[ -z "$pid" ]] && return 1
  kids="$(pgrep -P "$pid" 2>/dev/null || true)"
  for k in $pid $kids; do
    comm="$(ps -p "$k" -o comm= 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$comm" in
      *grok*) echo grok; return 0 ;;
      *claude*) echo claude; return 0 ;;
    esac
  done
  return 1
}

# Wait, never exit, when no session answers. tmux loads its config - and starts
# this - before tmux-resurrect has restored anything, so a `while has-session`
# loop ends on the very first tick after a reboot and nothing ever restarts it.
while true; do
  if ! tmux has-session 2>/dev/null; then
    sleep 3
    continue
  fi

  for p in $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null); do
    tag="$(tmux show-options -pqv -t "$p" @pane_agent 2>/dev/null)"
    name="$(pane_agent_name "$p" || true)"
    if [[ -n "$name" ]]; then
      [[ "$tag" != "$name" ]] && {
        tmux set-option -p -t "$p" @pane_agent "$name" 2>/dev/null
        tmux set-option -p -t "$p" @pane_started_at "$(date +%s)" 2>/dev/null
      }
    else
      [[ -n "$tag" ]] && tmux set-option -pu -t "$p" @pane_agent 2>/dev/null
    fi
  done
  sleep 3
done
