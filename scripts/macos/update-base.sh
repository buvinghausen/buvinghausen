#!/usr/bin/env bash
# Installs TOOLCHAIN-macos.md's Base Dependencies block — the Homebrew formulae
# every other module's from-source build assumes are already present (pyenv's
# and ruby-build's headers, autotools, and Homebrew bash for the scripts
# themselves). The list lives in lib-macos.sh's brew_build_deps so the
# language modules can call the same one when they bootstrap; brew install /
# upgrade are both no-ops once current. The Darwin twin of scripts/update-base.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

# The index refresh only (the `dnf makecache` analogue). Deliberately not a
# blanket `brew upgrade`: that is the same bigger, less predictable action
# the Fedora module leaves out of its pass (`dnf update -y`).
log "Homebrew index"
brew update

log "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
	echo "No developer directory selected — run \`xcode-select --install\` (or install Xcode) first; every compile below needs it" >&2
	exit 1
fi
xcode-select -p

log "Base dependencies (Homebrew)"
brew_build_deps

"$(brew --prefix)/bin/bash" --version | head -1
