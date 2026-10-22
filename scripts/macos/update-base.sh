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

# Rosetta runs the x86_64 half of the Hyper repos' macOS legs on this arm64
# box: the osx-x64 cdylib's own `cargo test`, and any x86_64 binary a suite
# launches. Its installer needs sudo, so like Xcode's selection it is a
# one-time manual step this fails loudly on rather than running.
log "Rosetta 2"
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
	cat >&2 <<'MSG'
Rosetta 2 is not installed (x86_64 binaries fail with "Bad CPU type"). One-time, by hand (needs sudo):
  sudo softwareupdate --install-rosetta --agree-to-license
MSG
	exit 1
fi
echo "x86_64 binaries run"

log "Base dependencies (Homebrew)"
brew_build_deps

"$(brew --prefix)/bin/bash" --version | head -1
