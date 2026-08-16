#!/usr/bin/env bash
# Installs TOOLCHAIN.md's Base Dependencies block — the dnf packages every
# other module assumes are already on PATH (awk, gcc/make for cargo builds,
# the pyenv/SDKMAN headers, etc). `dnf install -y` is idempotent, so this is
# a fast no-op once installed. Fedora-specific, matching this box; substitute
# package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

log "Base dependencies (dnf)"
sudo dnf install -y curl wget git gcc gcc-c++ make openssl-devel zlib-devel \
	bzip2 bzip2-devel readline-devel sqlite sqlite-devel xz xz-devel \
	libffi-devel tk-devel libuuid-devel patch gawk
