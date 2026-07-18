#!/usr/bin/env bash
# Updates Node.js (fnm), npm, and TypeScript (Go-native compiler, GA since 7.0).
# Replay-safe: every step here is a no-op or clean overwrite when already current.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

require_cmd fnm "fnm not found — run the Node.js install steps in TOOLCHAIN.md first"
eval "$(fnm env)"
require_cmd npm "npm not found on PATH after fnm env — check fnm install"

log "Node.js (fnm lts-latest)"
fnm install --lts
fnm default lts-latest

log "npm"
npm install -g npm@latest

log "TypeScript"
npm install -g typescript@latest

node --version
npm --version
tsc --version
