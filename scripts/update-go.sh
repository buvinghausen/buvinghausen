#!/usr/bin/env bash
# Updates Go, gopls, Delve, revive, and benchstat. Removes the superseded /usr/local/go install
# before laying down a new version — Go does not coexist side by side.
#
# Bootstraps Go itself when missing (fresh machine / fresh distro) — Go ships
# as a raw tarball with no installer, so PATH/GOPATH are appended to
# ~/.bashrc once here, mirroring TOOLCHAIN.md's manual install block.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

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

go version
gopls version
dlv version
# benchstat has no version flag — read the module version out of the binary.
go version -m "$(command -v benchstat)" | awk '$1 == "mod" {print "benchstat", $3}'
