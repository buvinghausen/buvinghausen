#!/usr/bin/env bash
# Updates Go, gopls, Delve, revive, benchstat, and TinyGo. Removes the superseded
# /usr/local/go install (and the superseded ~/.local/tinygo tree) before laying
# down a new version — neither coexists side by side.
#
# Bootstraps Go itself when missing (fresh machine / fresh distro) — Go ships
# as a raw tarball with no installer, so PATH/GOPATH are appended to
# ~/.bashrc once here, mirroring TOOLCHAIN.md's manual install block.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

TINYGO_HOME="$HOME/.local/tinygo"
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin:$TINYGO_HOME/bin"

if ! command -v go >/dev/null 2>&1; then
	log "Go not found — bootstrapping (see TOOLCHAIN.md)"
	append_bashrc_once "# Go" <<'EOF'

# Go
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF
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
	wget -q -P "$TMP" "https://go.dev/dl/${GO_LATEST}.linux-${ARCH}.tar.gz"
	sudo rm -rf /usr/local/go
	sudo tar -C /usr/local -xzf "$TMP/${GO_LATEST}.linux-${ARCH}.tar.gz"
fi

log "gopls / dlv"
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest

log "revive (linter)"
go install github.com/mgechev/revive@latest

# Formatting (gofmt) and profiling (`go tool pprof`) ship inside the Go
# distribution itself; benchstat is the one piece of the perf loop that
# doesn't — it turns two sets of `go test -bench -count=N` output into a
# delta with a significance test instead of two columns to eyeball.
log "benchstat (go test -bench comparison)"
go install golang.org/x/perf/cmd/benchstat@latest

# TinyGo — the Go-to-WebAssembly compiler Hyper's Go binding ships through
# (README: "Go through TinyGo"). Not a `go install`: it ships as a release
# tarball whose unpacked tree (bin/ with tinygo + its own wasm-opt, lib/, src/,
# targets/) has to stay together, so it lives whole under ~/.local/tinygo with
# bin/ appended to PATH — not a lone binary dropped into ~/.local/bin, which is
# how the 2026-09-01 hand install ended up invisible to every shell. Version-
# diffed on the installed binary; the superseded tree is removed before the new
# one lands, the same treatment /usr/local/go gets above.
log "TinyGo"
append_bashrc_once "# TinyGo" <<'EOF'

# TinyGo
export PATH=$PATH:$HOME/.local/tinygo/bin
EOF
TINYGO_LATEST=$(github_latest_release tinygo-org/tinygo)
TINYGO_CURRENT=$("$TINYGO_HOME/bin/tinygo" version 2>/dev/null | awk '{print $3}' || echo "none")

if [[ "$TINYGO_CURRENT" == "$TINYGO_LATEST" ]]; then
	log "TinyGo already at $TINYGO_CURRENT — skipping reinstall"
else
	log "TinyGo $TINYGO_CURRENT -> $TINYGO_LATEST"
	ARCH=$(arch_amd64_arm64)
	TINYGO_TMP=$(mktemp -d)
	wget -q -P "$TINYGO_TMP" "https://github.com/tinygo-org/tinygo/releases/download/v${TINYGO_LATEST}/tinygo${TINYGO_LATEST}.linux-${ARCH}.tar.gz"
	tar -xzf "$TINYGO_TMP/tinygo${TINYGO_LATEST}.linux-${ARCH}.tar.gz" -C "$TINYGO_TMP"
	rm -rf "$TINYGO_HOME"
	mv "$TINYGO_TMP/tinygo" "$TINYGO_HOME"
	rm -rf "$TINYGO_TMP"
fi

go version
gopls version
dlv version
# benchstat has no version flag — read the module version out of the binary.
go version -m "$(command -v benchstat)" | awk '$1 == "mod" {print "benchstat", $3}'
tinygo version
