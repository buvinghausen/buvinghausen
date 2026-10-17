#!/usr/bin/env bash
# Updates Node.js (fnm), npm, and TypeScript (Go-native compiler, GA since 7.0).
# Replay-safe: every step here is a no-op or clean overwrite when already current.
# Same prune policy as scripts/update-node.sh: fnm never removes anything on
# its own, so every installed version except `fnm current` is uninstalled.
#
# Darwin differences: fnm comes from Homebrew (fnm's own curl installer just
# shells out to `brew install fnm` on macOS and then edits ~/.zshrc itself —
# calling brew directly keeps the rc wiring under append_zshrc_once like
# every other module here), and the shell hook is zsh's.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

log "fnm (Homebrew)"
brew_ensure fnm
append_zshrc_once "# fnm" <<'EOF2'

# fnm
eval "$(fnm env --use-on-cd --shell zsh)"
EOF2
eval "$(fnm env --shell bash)"

log "Node.js (fnm lts-latest)"
fnm install --lts
fnm default lts-latest

# npm only lands on PATH once a node version is installed and active above —
# checked here, not before, so this also works on a first-ever bootstrap.
require_cmd npm "npm not found on PATH after fnm install — check fnm install"

NODE_KEEP=$(fnm current)
log "Pruning stale Node.js versions (keeping ${NODE_KEEP})"
NODE_VERSIONS=$(fnm list | awk '{print $2}')
while IFS= read -r v; do
	[[ -z "$v" || "$v" == "system" || "$v" == "$NODE_KEEP" ]] && continue
	echo "  $v (kept $NODE_KEEP)"
	fnm uninstall "$v"
done <<<"$NODE_VERSIONS"

log "npm"
npm install -g npm@latest

log "TypeScript"
npm install -g typescript@latest

fnm --version
node --version
npm --version
tsc --version
