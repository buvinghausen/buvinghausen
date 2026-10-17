#!/usr/bin/env bash
# The Fedora docker module is already OS-neutral — it only talks to the docker
# CLI, which Docker Desktop for Mac puts on ~/.docker/bin (wired in ~/.zprofile)
# — so this just runs it. Docker Desktop updates itself; see TOOLCHAIN-macos.md.
set -euo pipefail
export PATH="$PATH:$HOME/.docker/bin"
exec bash "$(dirname "${BASH_SOURCE[0]}")/../update-docker.sh"
