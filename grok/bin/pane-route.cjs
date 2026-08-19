#!/usr/bin/env node
// Grok PreToolUse: run shell commands in a visible tmux/herdr pane via pane-run.
// Emits Grok hook JSON (decision + updatedInput). Fail-open on errors.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const HOME = os.homedir();
const RUNNER = path.join(HOME, '.grok', 'bin', 'pane-run');

const SILENT = new Set([
  'ls', 'cat', 'head', 'tail', 'grep', 'rg', 'fd', 'find', 'wc',
  'which', 'echo', 'pwd', 'stat', 'file', 'tree', 'jq', 'cd',
]);
const SILENT_GIT = new Set(['status', 'log', 'diff', 'show', 'branch']);

function quote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function emit(payload) {
  process.stdout.write(JSON.stringify(payload));
}

function isSilent(command) {
  const segments = command.split(/\|\||&&|;|\|/).map((s) => s.trim()).filter(Boolean);
  if (!segments.length) return false;
  return segments.every((segment) => {
    const words = segment.split(/\s+/);
    const [head, second, third] = words;
    if (head === 'rtk') return second === 'git' ? SILENT_GIT.has(third) : SILENT.has(second);
    if (head === 'git') return SILENT_GIT.has(second);
    return SILENT.has(head);
  });
}

function throughRtk(raw) {
  const result = spawnSync('rtk', ['hook', 'claude'], { input: raw, encoding: 'utf8', timeout: 5000 });
  if (result.status !== 0 || !result.stdout) return null;
  try {
    return JSON.parse(result.stdout).hookSpecificOutput || null;
  } catch {
    return null;
  }
}

function main() {
  let raw;
  try {
    raw = fs.readFileSync(0, 'utf8');
  } catch {
    return;
  }
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    return;
  }

  const toolInput = input.tool_input || input.toolInput || {};
  const original = typeof toolInput.command === 'string' ? toolInput.command : '';
  if (!original) return;

  let command = original;
  const rtk = throughRtk(raw);
  if (rtk) {
    if (rtk.permissionDecision && rtk.permissionDecision !== 'allow') {
      emit({
        decision: rtk.permissionDecision === 'deny' ? 'deny' : 'allow',
        reason: rtk.permissionDecisionReason || 'rtk',
      });
      return;
    }
    if (rtk.updatedInput && typeof rtk.updatedInput.command === 'string') {
      command = rtk.updatedInput.command;
    }
  }

  const inPane = Boolean(process.env.TMUX) || process.env.HERDR_ENV === '1';
  const skip =
    !inPane ||
    toolInput.run_in_background === true ||
    /^\s*(tmux\b|herdr\b|\S*pane-run\b)/.test(command) ||
    isSilent(original);

  const cwd = input.cwd || process.cwd();
  const finalCommand = skip ? command : `${RUNNER} ${quote(cwd)} ${quote(command)}`;
  if (finalCommand === original) return;

  emit({
    decision: 'allow',
    reason: 'Runs in a visible pane',
    updatedInput: { ...toolInput, command: finalCommand },
  });
}

main();
