# Grok wiring in this repo

Hook JSON does **not** live here. Grok harness hooks are in
`~/Developer/cerberus-hub/tools/grok/hooks/` and `setup.sh` makes
`~/.grok/hooks` a symlink to that directory.

This folder only keeps the pane-run runtime (`bin/pane-route.cjs`),
which the hub hook calls at `$HOME/.grok/bin/pane-route.cjs`.
