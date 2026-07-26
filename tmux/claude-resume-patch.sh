#!/usr/bin/env python3
"""Point each saved Claude pane at the conversation it is actually on.

tmux-resurrect replays a pane's command line verbatim, but that line is frozen
at launch while the conversation id keeps changing (/clear, a new conversation,
resuming another one). So a pane launched as `claude --resume A` that has since
moved to conversation B comes back on A - the "it reopened the previous session"
symptom. Claude Code does not expose the live id in its argv, which is why this
patches the save file instead (anthropics/claude-code#34829).

Runs from @resurrect-hook-post-save-all, after resurrect has written the file.

Source of truth: ~/.claude/sessions/<pid>.json carries the current sessionId.
Panes are matched to it by TTY rather than by parent pid - pid parentage misses
panes whose claude re-execed itself, TTY matched every pane under test.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

RESURRECT_DIR = os.path.expanduser("~/.local/share/tmux/resurrect")
SESSIONS_DIR = os.path.expanduser("~/.claude/sessions")
PROJECTS_DIR = os.path.expanduser("~/.claude/projects")

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
# the pane title carries the id truncated to ~16 chars
UUID_PREFIX = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{2,}"


def run(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return out.stdout
    except Exception:
        return ""


def tty_to_session_id():
    """Current conversation per TTY, from the per-pid files Claude Code writes."""
    pid_tty = {}
    for line in run(["ps", "-Ao", "pid=,tty="]).splitlines():
        parts = line.split()
        if len(parts) == 2:
            pid_tty[parts[0]] = parts[1]

    found = {}
    for path in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(path) as fh:
                rec = json.load(fh)
        except Exception:
            continue
        sid = rec.get("sessionId")
        tty = pid_tty.get(str(rec.get("pid")))
        if not sid or not tty:
            continue
        # ps reports "ttys001", tmux reports "/dev/ttys001"
        tty = "/dev/" + tty if not tty.startswith("/dev/") else tty
        # several claude pids can share a tty (the launcher and its re-exec);
        # the freshest record wins
        prev = found.get(tty)
        if prev is None or rec.get("updatedAt", 0) >= prev[1]:
            found[tty] = (sid, rec.get("updatedAt", 0))
    return {tty: sid for tty, (sid, _) in found.items()}


def pane_key_to_tty():
    """session:window_index.pane_index -> tty, the key resurrect lines carry."""
    fmt = "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_tty}"
    out = {}
    for line in run(["tmux", "list-panes", "-a", "-F", fmt]).splitlines():
        parts = line.split("\t")
        if len(parts) == 4:
            sess, win, pane, tty = parts
            out[(sess, win, pane)] = tty
    return out


def encode_path(path):
    """Claude Code's project-directory encoding: every non-alphanumeric char
    becomes a dash. Same rule as ~/.claude/bin/claude-last-session, which was
    verified against real project dirs (_learning -> -learning, .claude ->
    --claude), so underscores and dots are both covered."""
    return re.sub(r"[^a-zA-Z0-9]", "-", path)


def inner_session_id(transcript):
    """A resumed session writes a continuation file whose filename uuid differs
    from the sessionId inside it (anthropics/claude-code#30606); --resume needs
    the inner one."""
    try:
        with open(transcript, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if rec.get("sessionId"):
                    return rec["sessionId"]
    except OSError:
        pass
    return None


def resolve_prefix(cwd, prefix):
    """Expand a truncated id from the pane title into the full one."""
    hits = glob.glob(os.path.join(PROJECTS_DIR, encode_path(cwd), prefix + "*.jsonl"))
    if len(hits) != 1:
        return None
    inner = inner_session_id(hits[0])
    if inner and re.fullmatch(UUID, inner):
        return inner
    name = os.path.basename(hits[0])[: -len(".jsonl")]
    return name if re.fullmatch(UUID, name) else None


def patch_line(line, tty_ids, pane_ttys):
    fields = line.rstrip("\n").split("\t")
    if len(fields) < 11 or fields[0] != "pane":
        return line

    command = fields[10]
    if "claude" not in command:
        return line

    session, window, pane_index = fields[1], fields[2], fields[5]
    title, cwd = fields[6], fields[7].lstrip(":")

    session_id = tty_ids.get(pane_ttys.get((session, window, pane_index)))

    if not session_id:
        match = re.search(UUID_PREFIX, title)
        if match:
            session_id = resolve_prefix(cwd, match.group(0))

    if not session_id:
        return line

    if re.search(r"--resume\s+" + UUID, command):
        command = re.sub(r"(--resume\s+)" + UUID, r"\g<1>" + session_id, command)
    else:
        # pane started fresh: no id in its argv at all, the case that currently
        # restores an empty session
        command = command + " --resume " + session_id

    fields[10] = command
    return "\t".join(fields) + "\n"


def main():
    link = os.path.join(RESURRECT_DIR, "last")
    if not os.path.exists(link):
        return 0
    target = os.path.join(RESURRECT_DIR, os.readlink(link))
    if not os.path.isfile(target):
        return 0

    tty_ids = tty_to_session_id()
    pane_ttys = pane_key_to_tty()
    if not tty_ids and not pane_ttys:
        return 0

    with open(target) as fh:
        lines = fh.readlines()

    patched = [patch_line(line, tty_ids, pane_ttys) for line in lines]
    if patched == lines:
        return 0

    shutil.copy2(target, target + ".bak")
    # temp file then rename: a failure never leaves a truncated save behind
    fd, tmp = tempfile.mkstemp(dir=RESURRECT_DIR)
    with os.fdopen(fd, "w") as fh:
        fh.writelines(patched)
    shutil.copymode(target, tmp)
    os.replace(tmp, target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
