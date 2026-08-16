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
#
# Bootstraps fnm itself when missing (fresh machine / fresh distro) — fnm's
# own installer appends `eval "$(fnm env)"` to ~/.bashrc, so no manual PATH
# block is needed here the way Go/dotnet/Rust need one.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

if ! command -v fnm >/dev/null 2>&1; then
	log "fnm not found — bootstrapping (see TOOLCHAIN.md)"
	curl -fsSL https://fnm.vercel.app/install | bash
	export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/fnm:$PATH"
fi
require_cmd fnm "fnm install failed — check the installer output above"
eval "$(fnm env)"

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
