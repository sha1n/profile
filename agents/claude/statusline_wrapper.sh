#!/usr/bin/env zsh

payload="$(cat; print -n x)"
payload="${payload%x}"

orca_hook="$HOME/.orca/agent-hooks/claude-statusline.sh"
# Claude Code runs a single statusLine command, so this wrapper takes that slot.
# Orca's script only forwards rate-limit data to the Orca app and prints nothing.
if [[ -x "$orca_hook" ]]; then
  printf '%s' "$payload" | /bin/sh "$orca_hook" >/dev/null 2>&1 &!
fi

printf '%s' "$payload" | "${0:A:h}/statusline.sh"
