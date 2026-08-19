# Grok-adapted Mirko setup

Same stack as https://github.com/mirkobozzetto/dotfiles, recabled for Grok Build CLI.

## Differences from upstream

- tmux/herdr prefix is **Ctrl+B**, not Ctrl+Space (Grok voice uses Ctrl+Space)
- Ghostty `Cmd` shortcuts send `\x02` (Ctrl+B)
- Font: MesloLGL 16
- `Shift+Enter` = newline in the Grok composer; `Cmd+A` unbind so Grok select-all works
- tmux tags `grok` panes; Grok hooks write `@pane_status` for auto-jump
- `herdr integration install grok` for session restore
- Grok hook JSON lives in cerberus-hub `tools/grok/hooks/` (`~/.grok/hooks` is a symlink). pane-run binary stays in this repo.

## Try it

Open a **new** Ghostty window (`Cmd+N`). It starts mux → tmux session `main`.

| Action | Key |
|---|---|
| Split right / left / down | `Cmd+D` / `Cmd+Shift+H` / `Cmd+Shift+D` |
| New tab | `Cmd+T` |
| Session picker | `Cmd+P` |
| Agent sidebar | `Cmd+Shift+B` |
| Jump to agent that needs you | `Cmd+Shift+G` |
| Switch tmux ↔ herdr | `~/.config/mux switch` |
| Prefix by hand | `Ctrl+B` |

This current Grok session stays on the old window until you open a new one.

## Rollback

```sh
bash ~/.dotfiles-backup-20260818-trial/RESTORE.sh
```
