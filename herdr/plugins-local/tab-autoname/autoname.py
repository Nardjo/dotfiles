#!/usr/bin/env python3
"""Give a new tab a name worth reading.

Inside a linked git worktree the directory basename repeats across every
checkout of the same repo, so the branch is the only thing that tells them
apart. Everywhere else the directory is what you actually think in.

Runs on tab.created, and on demand through the rename-current action. A tab
whose label is not the number Herdr assigned is left alone: a name someone
typed, or one Smart Rename derived from the work, always wins.
"""

import json
import os
import subprocess
import sys
import time

HERDR = os.environ.get("HERDR_BIN_PATH", "herdr")
# the root pane is created just after the tab, so the first lookup can miss
PANE_LOOKUP_ATTEMPTS = 5
PANE_LOOKUP_DELAY_S = 0.2


def herdr(*args):
    try:
        done = subprocess.run(
            [HERDR, *args], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode != 0:
        return None
    try:
        return json.loads(done.stdout)
    except json.JSONDecodeError:
        return None


def git(cwd, *args):
    try:
        done = subprocess.run(
            ["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def label_for(cwd):
    # a linked worktree keeps its gitdir under <repo>/.git/worktrees/<name>
    gitdir = git(cwd, "rev-parse", "--git-dir") or ""
    if "/worktrees/" in gitdir:
        branch = git(cwd, "rev-parse", "--abbrev-ref", "HEAD")
        if branch and branch != "HEAD":
            return branch
    return os.path.basename(cwd.rstrip("/")) or cwd


def pane_cwd(workspace_id, tab_id):
    for attempt in range(PANE_LOOKUP_ATTEMPTS):
        if attempt:
            time.sleep(PANE_LOOKUP_DELAY_S)
        args = ["pane", "list"]
        if workspace_id:
            args += ["--workspace", workspace_id]
        listing = herdr(*args)
        if not listing:
            continue
        for pane in listing.get("result", {}).get("panes", []):
            if pane.get("tab_id") == tab_id:
                return pane.get("cwd") or pane.get("foreground_cwd")
    return None


def target_from_event():
    raw = os.environ.get("HERDR_PLUGIN_EVENT_JSON")
    if not raw:
        return None, None, None
    try:
        tab = (json.loads(raw).get("data") or {}).get("tab") or {}
    except json.JSONDecodeError:
        return None, None, None
    return tab.get("tab_id"), tab.get("workspace_id"), tab.get("label")


def target_from_env():
    tab_id = os.environ.get("HERDR_TAB_ID")
    workspace_id = os.environ.get("HERDR_WORKSPACE_ID")
    info = herdr("tab", "get", tab_id) if tab_id else None
    label = (info or {}).get("result", {}).get("tab", {}).get("label")
    return tab_id, workspace_id, label


def rename(tab_id, workspace_id, label, force):
    if not force and label and not str(label).strip().isdigit():
        return
    cwd = pane_cwd(workspace_id, tab_id)
    if not cwd:
        return
    new_label = label_for(cwd)
    if new_label and new_label != label:
        herdr("tab", "rename", tab_id, new_label)


def rename_every_numbered_tab():
    listing = herdr("tab", "list") or {}
    for tab in listing.get("result", {}).get("tabs", []):
        rename(tab.get("tab_id"), tab.get("workspace_id"), tab.get("label"), False)


def main():
    # --all catches up after a restore, where tabs come back as numbers
    if "--all" in sys.argv:
        rename_every_numbered_tab()
        return

    on_demand = "--current" in sys.argv
    tab_id, workspace_id, label = (
        target_from_env() if on_demand else target_from_event()
    )
    if tab_id:
        rename(tab_id, workspace_id, label, on_demand)


if __name__ == "__main__":
    main()
