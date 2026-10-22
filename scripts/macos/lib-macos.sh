# shellcheck shell=bash
# Shared helpers for scripts/macos/update-*.sh. Sourced, not executed.
#
# Sources the OS-neutral half of scripts/lib.sh (log, require_cmd, the arch
# helpers, github_latest_release, install_from_tarball) and adds the Darwin
# specifics: Homebrew is the package manager (the dnf analogue), ~/.zshrc is
# the rc file (zsh is macOS's login shell; every upstream installer in the
# pass that self-wires a profile targets .zshrc on Darwin), and nothing runs
# as root — ~/.local/{bin,opt,go} stand in for /usr/local and /opt.
#
# The Fedora-only helpers that lib.sh also defines (dnf_build_deps,
# append_bashrc_once) are still visible after the source — nothing here calls
# them. Don't.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Homebrew's own PATH wiring lives in ~/.zprofile (brew shellenv). Scripts are
# launched from a zsh terminal and inherit it, but a module run from a bare
# environment (cron, an IDE's build runner) wouldn't — so make it explicit.
if [[ -x /opt/homebrew/bin/brew ]]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi
require_cmd brew "Homebrew not found — install it first (https://brew.sh), it is the one prerequisite this pass assumes"

# Appends stdin to ~/.zshrc once, keyed on marker (e.g. "# Go") already being
# present — same contract as lib.sh's append_bashrc_once, different file.
append_zshrc_once() {
	grep -qF "$1" "$HOME/.zshrc" 2>/dev/null && return 0
	cat >>"$HOME/.zshrc"
}

# `brew install` is a no-op (warning, exit 0) when the formula is already
# installed, but it never upgrades; `brew upgrade` upgrades and is likewise
# a no-op when current. Running both gives the dnf-install semantics every
# Fedora module leans on: present and at the latest the index knows.
brew_ensure() {
	brew install "$@"
	brew upgrade "$@"
}

# The one Homebrew list every from-source build in the macOS pass draws on —
# the dnf_build_deps analogue. Smaller than Fedora's: php comes from Homebrew
# prebuilt (no php-build headers), Swift from the Command Line Tools (no
# swiftly prerequisites), and the compiler/linker/make are the CLT's.
#
#   bash                          — 5.x for the scripts themselves (/bin/bash is 3.2; update-jvm.sh needs declare -A)
#   pkgconf autoconf automake libtool — autotools for ruby-build's and pyenv's configure runs
#   openssl@3 readline sqlite xz zlib zstd libb2 — pyenv's suggested build environment (wiki), minus tcl-tk@8
#                                   (deprecated in Homebrew; nothing here needs tkinter)
#   openssl@3 readline libyaml gmp autoconf — ruby-build's suggested build environment (wiki)
#   libffi                        — ctypes / Fiddle
#
# No `binutils`: ruby-build's wiki warns a Homebrew binutils on PATH breaks
# the Ruby build (its ar/ranlib shadow the system ones). No `llvm` here: the
# tools module installs it for the release-guard checks, keg-only and off
# PATH, so bindgen still finds the CLT's libclang.
brew_build_deps() {
	brew_ensure bash pkgconf autoconf automake libtool \
		openssl@3 readline sqlite xz zlib zstd libb2 \
		libyaml gmp libffi
}

# update-jvm.sh's prune uses associative arrays — bash 4+. The base module
# installs Homebrew bash; this is the guard for a module run before it.
require_bash4() {
	((BASH_VERSINFO[0] >= 4)) || { echo "bash ${BASH_VERSION} is too old (needs 4+) — run the base module first for Homebrew bash" >&2; exit 1; }
}

# Nothing in this pass runs as root. Where the Fedora modules write to
# /usr/local/{bin,go} and /opt, the macOS ones use the user-owned twins under
# ~/.local — the same arrangement Homebrew itself has under /opt/homebrew.
# ~/.local/bin is already first on PATH in ~/.zshrc (Claude Code's installer
# put it there); LOCAL_OPT is where multi-file release trees (async-profiler,
# pwsh, the Android NDK) unpack, each symlinked or PATH'd from its module.
LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
ensure_local_dirs() {
	mkdir -p "$LOCAL_BIN" "$LOCAL_OPT"
}

# lib.sh's install_from_tarball `sudo install`s into /usr/local/bin; this is
# the same download-extract-install for a user-owned destination.
install_from_tarball_local() {
	local url="$1" inner="$2" dest="$3" tmp
	ensure_local_dirs
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/$(basename "$url")" "$url"
	tar -xzf "$tmp/$(basename "$url")" -C "$tmp"
	install "$tmp/$inner" "$dest"
	rm -rf "$tmp"
}
