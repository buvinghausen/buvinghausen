#!/usr/bin/env bash
# Updates Go, gopls, and Delve. Removes the superseded /usr/local/go install
# before laying down a new version — Go does not coexist side by side.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
require_cmd go "go not found on PATH — run the Go install steps in TOOLCHAIN.md first"

GO_LATEST=$(curl -s https://go.dev/VERSION?m=text | head -1)
GO_CURRENT=$(go version | awk '{print $3}')

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

go version
gopls version
dlv version
