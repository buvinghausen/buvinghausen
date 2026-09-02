#!/usr/bin/env bash
# Installs TOOLCHAIN.md's Base Dependencies block — the dnf packages every
# other module's from-source build assumes are already present (gcc/make for
# cargo builds, the pyenv/ruby-build/php-build/swiftly headers, etc). The
# list itself lives in lib.sh's dnf_build_deps so the language modules can
# call the same one when they bootstrap; `dnf install -y` is idempotent, so
# this is a fast no-op once installed. Fedora-specific, matching this box;
# substitute package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

log "Base dependencies (dnf)"
dnf_build_deps
