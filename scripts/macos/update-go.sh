#!/usr/bin/env bash
# Updates Go, gopls, Delve, revive, benchstat, and TinyGo. Removes the superseded
# ~/.local/go install (and the superseded ~/.local/tinygo tree) before laying
# down a new version — neither coexists side by side. Darwin twin of
# scripts/update-go.sh: the differences are the `darwin-arm64` asset names,
# ~/.zshrc as the rc file, and Go's tree living user-owned under ~/.local/go
# instead of /usr/local/go (no sudo anywhere in this pass; Go finds its own
# GOROOT from the binary's location, so the path is free).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

GO_HOME="$HOME/.local/go"
TINYGO_HOME="$HOME/.local/tinygo"
export PATH="$PATH:$GO_HOME/bin:$HOME/go/bin:$TINYGO_HOME/bin"

if ! command -v go >/dev/null 2>&1; then
	log "Go not found — bootstrapping (see TOOLCHAIN-macos.md)"
	append_zshrc_once "# Go" <<'EOF2'

# Go
export PATH=$PATH:$HOME/.local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF2
fi

GO_LATEST=$(curl -s https://go.dev/VERSION?m=text | head -1)
GO_CURRENT=$(command -v go >/dev/null 2>&1 && go version | awk '{print $3}' || echo "none")

if [[ "$GO_CURRENT" == "$GO_LATEST" ]]; then
	log "Go already at $GO_CURRENT — skipping reinstall"
else
	log "Go $GO_CURRENT -> $GO_LATEST"
	ARCH=$(arch_amd64_arm64)
	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT
	curl -fsSL -o "$TMP/${GO_LATEST}.darwin-${ARCH}.tar.gz" "https://go.dev/dl/${GO_LATEST}.darwin-${ARCH}.tar.gz"
	rm -rf "$GO_HOME"
	tar -C "$(dirname "$GO_HOME")" -xzf "$TMP/${GO_LATEST}.darwin-${ARCH}.tar.gz"
fi

log "gopls / dlv"
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest

log "revive (linter)"
go install github.com/mgechev/revive@latest

log "benchstat (go test -bench comparison)"
go install golang.org/x/perf/cmd/benchstat@latest

# TinyGo — release tarball whose unpacked tree has to stay together, so it
# lives whole under ~/.local/tinygo (see scripts/update-go.sh for the why).
# The darwin tarball's bin/ carries only `tinygo` — no wasm-opt, unlike the
# Linux one — and `tinygo build -target wasm` hard-fails without it ("could
# not find wasm-opt"; hit on the first run). TinyGo's own Homebrew formula
# declares binaryen as its dependency, so that is where wasm-opt comes from.
log "binaryen (wasm-opt for TinyGo's wasm target — Homebrew)"
brew_ensure binaryen

log "TinyGo"
append_zshrc_once "# TinyGo" <<'EOF2'

# TinyGo
export PATH=$PATH:$HOME/.local/tinygo/bin
EOF2
TINYGO_LATEST=$(github_latest_release tinygo-org/tinygo)
TINYGO_CURRENT=$("$TINYGO_HOME/bin/tinygo" version 2>/dev/null | awk '{print $3}' || echo "none")

if [[ "$TINYGO_CURRENT" == "$TINYGO_LATEST" ]]; then
	log "TinyGo already at $TINYGO_CURRENT — skipping reinstall"
else
	log "TinyGo $TINYGO_CURRENT -> $TINYGO_LATEST"
	ARCH=$(arch_amd64_arm64)
	TINYGO_TMP=$(mktemp -d)
	curl -fsSL -o "$TINYGO_TMP/tinygo${TINYGO_LATEST}.darwin-${ARCH}.tar.gz" "https://github.com/tinygo-org/tinygo/releases/download/v${TINYGO_LATEST}/tinygo${TINYGO_LATEST}.darwin-${ARCH}.tar.gz"
	tar -xzf "$TINYGO_TMP/tinygo${TINYGO_LATEST}.darwin-${ARCH}.tar.gz" -C "$TINYGO_TMP"
	rm -rf "$TINYGO_HOME"
	mv "$TINYGO_TMP/tinygo" "$TINYGO_HOME"
	rm -rf "$TINYGO_TMP"
fi

go version
gopls version
dlv version
go version -m "$(command -v benchstat)" | awk '$1 == "mod" {print "benchstat", $3}'
tinygo version
