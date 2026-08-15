# Shell functions worth keeping in version control.
# Sourced from ~/.zshalias, which stays out of this repo because it holds
# API keys in clear.

# Clear the screen and really empty the scrollback, whatever runs underneath.
# `clear` alone leaves tmux's own buffer intact, so tmux needs clear-history.
# herdr and a bare terminal honour ED 3 (ESC[3J); ESC[2J alone does not.
cl() {
  clear
  if [ -n "$TMUX" ]; then
    tmux clear-history
  else
    printf '\033[3J'
  fi
}
