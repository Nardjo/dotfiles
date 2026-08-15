#!/bin/bash
#
# Raycast Script Command. Add ~/dotfiles/mux as a script directory in
# Raycast: Settings > Extensions > Script Commands > Add Directory.
#
# @raycast.schemaVersion 1
# @raycast.title Switch multiplexer
# @raycast.mode silent
# @raycast.icon 🔀
# @raycast.packageName Terminal
# @raycast.description Flip Ghostty between tmux and herdr, in the window you are already in.

# `mux` with no argument starts a multiplexer; any other word just reports.
"$HOME/.config/mux" switch
echo "now: $("$HOME/.config/mux" state)"
