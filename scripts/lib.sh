# shellcheck shell=bash
# Shared helpers for scripts/update-*.sh. Sourced, not executed.

log() { printf '\n==> %s\n' "$1"; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || { echo "$2" >&2; exit 1; }
}

# Matches the arch-detection convention used throughout TOOLCHAIN.md
arch_amd64_arm64() { uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'; }
arch_x64_arm64() { uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/'; }

# Latest release of a GitHub repo ("owner/name"), tag printed without its
# leading "v" — the version-diff key for every release-archive install
# (gh, actionlint, pwsh, async-profiler, rbspy, SwiftLint, TinyGo) so that
# pattern lives once. The "v" is optional: SwiftLint tags its releases bare
# ("0.65.1"). Anchored on the key, not on line shape: the API usually
# pretty-prints one field per line but has been seen returning the whole
# object on one line.
#
# Fails LOUDLY. The original `curl -s | grep | sed` pipeline died silently
# under `set -euo pipefail` whenever the API answered without a tag_name
# (2026-10-24: a full pass stopped dead after "==> TinyGo" with nothing on
# the console — grep's no-match exit 1 failed the assignment and errexit
# took the module and the orchestrator down with it). The usual reason is
# GitHub's unauthenticated limit of 60 requests/hour per public IP: every
# pass spends seven of those, and WSL2 shares the Windows host's IP, so a
# few debugging reruns can lock out `wsl --update` on the Windows side too.
# Authenticated requests get 5000/hour, so a token is sent when one is at
# hand: $GH_TOKEN, then $GITHUB_TOKEN, then `gh auth token` (the gh CLI's
# stored login; silently skipped on a fresh box where update-tools.sh has
# not installed gh yet). Any response without a tag_name — rate limit, 404,
# outage, no network — prints the API's own "message" line and returns 1.
github_latest_release() {
	local repo="$1" token body tag
	local -a auth=()
	token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
	if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
		token=$(gh auth token 2>/dev/null || true)
	fi
	[[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
	# No -f: a 403/404 body carries the "message" we want to show. ${auth[@]+...}
	# keeps an empty array safe under `set -u` on macOS's stock bash 3.2.
	body=$(curl -sS -H 'Accept: application/vnd.github+json' ${auth[@]+"${auth[@]}"} \
		"https://api.github.com/repos/$repo/releases/latest") || {
		echo "github_latest_release $repo: request to api.github.com failed" >&2
		return 1
	}
	tag=$(printf '%s\n' "$body" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')
	if [[ -z "$tag" ]]; then
		echo "github_latest_release $repo: no tag_name in the API response" >&2
		printf '%s\n' "$body" | grep -m1 '"message"' >&2 || printf '%s\n' "$body" | head -c 300 >&2
		return 1
	fi
	printf '%s\n' "$tag"
}

# Downloads a release tarball, extracts it into a scratch dir, and
# `sudo install`s one file out of it (overwriting in place — that IS the
# update path). Args: url, path-inside-tarball, destination.
install_from_tarball() {
	local url="$1" inner="$2" dest="$3" tmp
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/$(basename "$url")" "$url"
	tar -xzf "$tmp/$(basename "$url")" -C "$tmp"
	sudo install "$tmp/$inner" "$dest"
	rm -rf "$tmp"
}

# TOOLCHAIN.md's Base Dependencies block: the ONE dnf list every module's
# from-source build draws on — the pyenv/ruby-build/php-build/swiftly
# prerequisite sets used to be four separate lists, each transcribed from
# its own doc section, overlapping the base list and each other. `dnf
# install -y` is idempotent, so update-base.sh runs this on every pass and
# each language module's first-time bootstrap calls it too (a single-module
# run on a fresh box still gets its headers). Fedora-specific, matching this
# box; substitute package manager for other distros per TOOLCHAIN.md.
#
# No `rust` here even though ruby-build's wiki lists it (YJIT needs rustc at
# configure time): rustup's toolchain is the one this box keeps current, so
# update-ruby.sh sources ~/.cargo/env instead — one Rust, not two.
dnf_build_deps() {
	sudo dnf install -y \
		curl git gcc gcc-c++ make patch gawk binutils glibc-devel \
		autoconf automake libtool bison re2c \
		openssl-devel zlib-devel zlib-ng-compat-devel bzip2 bzip2-devel xz xz-devel \
		readline-devel libedit-devel ncurses-devel gdbm-devel sqlite sqlite-devel \
		libffi-devel libuuid-devel tk-devel libyaml-devel perl-FindBin \
		libxml2-devel libxslt-devel libcurl-devel libicu-devel gmp-devel openldap-devel \
		oniguruma-devel libsodium-devel libzip-devel libpng-devel libjpeg-turbo-devel \
		libwebp-devel libtidy-devel clang-devel python3-devel zip unzip
}

# Appends stdin to ~/.bashrc once, keyed on marker (e.g. "# Go") already being
# present. Used by first-time-bootstrap blocks whose installer doesn't wire
# up ~/.bashrc itself (Go's raw tarball, dotnet-install.sh) — safe to call on
# every run since the marker check makes it a no-op after the first time.
append_bashrc_once() {
	grep -qF "$1" "$HOME/.bashrc" 2>/dev/null && return 0
	cat >>"$HOME/.bashrc"
}
