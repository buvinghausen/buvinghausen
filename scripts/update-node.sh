#!/usr/bin/env bash
# Updates Node.js (fnm), npm, and TypeScript (Go-native compiler, GA since 7.0).
# Replay-safe: every step here is a no-op or clean overwrite when already current.
#
# fnm never removes anything on its own — the previous lts-latest patch (e.g.
# v24.18.0) sits installed side by side with the new one (v24.19.0)
# indefinitely. The prune step below removes every installed version except
# whatever `fnm current` resolves to post-install, mirroring the keep-only-
# current-max policy used in update-python.sh/update-dotnet.sh. `system`
# is never a real fnm-managed version — always skipped.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

require_cmd fnm "fnm not found — run the Node.js install steps in TOOLCHAIN.md first"
eval "$(fnm env)"
require_cmd npm "npm not found on PATH after fnm env — check fnm install"

log "Node.js (fnm lts-latest)"
fnm install --lts
fnm default lts-latest

NODE_KEEP=$(fnm current)
log "Pruning stale Node.js versions (keeping ${NODE_KEEP})"
NODE_VERSIONS=$(fnm list | awk '{print $2}')
while IFS= read -r v; do
	[[ "$v" == "system" || "$v" == "$NODE_KEEP" ]] && continue
	echo "  $v (kept $NODE_KEEP)"
	fnm uninstall "$v"
done <<<"$NODE_VERSIONS"

log "npm"
npm install -g npm@latest

log "TypeScript"
npm install -g typescript@latest

node --version
npm --version
tsc --version
