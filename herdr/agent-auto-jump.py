#!/usr/bin/env python3
"""Focus the herdr agent that wants you: a turn that just ended, or a prompt.

herdr reports agent lifecycle state through its integrations (herdr integration
status). This polls that state and calls `herdr agent focus` on the edge
working -> idle (finished) or -> blocked (needs an answer).

Focus is never stolen away from a pane that is itself waiting on you.
"""

import json
import os
import subprocess
import sys
import time

TICK = 1.0
COOLDOWN = 3.0  # seconds after a jump before another one is allowed
LOG = os.path.expanduser("~/.config/herdr/agent-auto-jump.log")

# herdr reports "idle" for agents it detects on screen, "done" for a lifecycle
# state pushed by an integration. Both mean the turn is over.
FINISHED = {"idle", "done"}

# Statuses of the pane you are on that forbid stealing your focus.
# herdr exposes no "last time you typed" signal, so this is the only guard.
# "blocked" alone: an agent is asking you something, you are probably answering.
# Add "working" to also stay put whenever the pane you watch is running.
HOLD_WHEN_FOCUSED_IS = {"blocked"}


def log(msg: str) -> None:
    with open(LOG, "a") as fh:
        fh.write(f"{time.strftime('%H:%M:%S')} {msg}\n")


def herdr(*args: str) -> dict:
    # A dead server answers on stderr with an empty stdout. Raising here keeps
    # the caller from reading that as "no agents", which would wipe the known
    # states and drop a working -> idle edge that spans the outage.
    run = subprocess.run(["herdr", *args], capture_output=True, text=True, timeout=10)
    out = run.stdout.strip()
    if not out.startswith("{"):
        raise RuntimeError(run.stderr.strip()[:120] or f"rc={run.returncode}")
    return json.loads(out)


def agents() -> list:
    return herdr("agent", "list").get("result", {}).get("agents", [])


def main() -> int:
    prev: dict[str, str] = {}
    handled: set[str] = set()
    last_jump = 0.0

    while True:
        try:
            current = agents()
        except Exception as exc:  # herdr server restarting
            log(f"poll failed: {exc}")
            time.sleep(TICK)
            continue

        focused = next((a for a in current if a.get("focused")), None)
        busy_here = bool(focused) and focused["agent_status"] in HOLD_WHEN_FOCUSED_IS

        for a in current:
            pane, state = a["pane_id"], a["agent_status"]
            was = prev.get(pane)

            reason = ""
            if state == "blocked":
                reason = "needs you"
            elif was == "working" and state in FINISHED:
                reason = "finished"

            if not reason:
                prev[pane] = state
                handled.discard(pane)  # episode over, a future jump is allowed
                continue

            if pane in handled or a.get("focused"):
                prev[pane] = state
                handled.add(pane)
                continue

            if busy_here or time.time() - last_jump < COOLDOWN:
                # deliberately do NOT record the state: working -> idle is a
                # single edge and forgetting it would drop the owed jump.
                continue

            herdr("agent", "focus", pane)
            log(f"JUMPED to {pane} ({a['cwd']}) because it {reason}")
            prev[pane] = state
            handled.add(pane)
            last_jump = time.time()
            break

        # panes that disappeared
        alive = {a["pane_id"] for a in current}
        for gone in set(prev) - alive:
            prev.pop(gone, None)
            handled.discard(gone)

        time.sleep(TICK)


if __name__ == "__main__":
    sys.exit(main())
