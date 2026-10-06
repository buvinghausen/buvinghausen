#!/usr/bin/env bash
# Updates Swift via swiftly: self-updates swiftly, then updates the in-use
# toolchain to latest, then SwiftLint from its release zip. `swiftly update` uninstalls the superseded toolchain
# as part of the same command — no separate prune step needed, unlike the
# Go/JVM/.NET modules above.
#
# Bootstraps swiftly itself when missing (fresh machine / fresh distro) — the
# swift.org tarball installer's own profile wiring targets
# ~/.bash_profile/~/.bash_login (login-shell files WSL2's interactive bash
# terminals don't source), so --no-modify-profile is passed and the env line
# is appended to ~/.bashrc by hand instead, mirroring every other module here.
#
# --platform fedora39, not fedora41 (see TOOLCHAIN.md's Swift section for the
# full explanation): swift.org's support matrix lists Fedora 41 as the
# current minimum, but the swiftly binary currently shipped at
# download.swift.org/swiftly/linux only recognizes fedora39 (plus the ubuntu/
# ubi9/amazonlinux2/debian12 set) as a --platform value — confirmed by
# running it, fedora41 fails hard with "Unrecognized platform". fedora39
# works fine on this Fedora 44 box.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

SWIFTLY_ENV="$HOME/.local/share/swiftly/env.sh"

if [[ -f "$SWIFTLY_ENV" ]]; then
	source "$SWIFTLY_ENV"
fi

if ! command -v swiftly >/dev/null 2>&1; then
	log "swiftly not found — bootstrapping (see TOOLCHAIN.md)"

	log "Build dependencies (shared dnf list, see lib.sh)"
	dnf_build_deps

	ARCH=$(uname -m)
	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT
	(
		cd "$TMP"
		curl -sO "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz"
		tar zxf "swiftly-${ARCH}.tar.gz"
		./swiftly init --assume-yes --quiet-shell-followup --no-modify-profile --platform fedora39
	)
fi

# Outside the bootstrap block on purpose: swiftly can already be installed (by a
# hand run of the installer, or an earlier version of this script) without its
# env line ever reaching ~/.bashrc, leaving swift invisible to new shells.
# append_bashrc_once is keyed on the marker, so this is a no-op once wired.
append_bashrc_once "# Swiftly (Swift toolchain manager)" <<EOF

# Swiftly (Swift toolchain manager)
. "$SWIFTLY_ENV"
EOF

source "$SWIFTLY_ENV"
require_cmd swiftly "swiftly install failed — check the installer output above"

log "swiftly self-update"
swiftly self-update --assume-yes

log "Swift toolchain update (swiftly removes the superseded toolchain automatically)"
swiftly update --assume-yes

# SwiftLint: the Hyper repos' lint-docs-swift CI gate (`swiftlint lint --strict
# Sources`). The release zip carries two binaries; this installs
# `swiftlint-static`, the one CI runs — it needs neither a Swift toolchain nor
# the libxml2 soname the dynamically linked `swiftlint` is built against. The
# formatter is not a separate install: `swift format` ships in the toolchain.
log "SwiftLint"
SWIFTLINT_LATEST=$(github_latest_release realm/SwiftLint)
SWIFTLINT_CURRENT=$(swiftlint version 2>/dev/null || true)
if [[ "$SWIFTLINT_CURRENT" == "$SWIFTLINT_LATEST" ]]; then
	echo "swiftlint already at $SWIFTLINT_CURRENT — skipping"
else
	SWIFTLINT_ZIP="swiftlint_linux_$(arch_amd64_arm64).zip"
	SWIFTLINT_TMP=$(mktemp -d)
	wget -q -P "$SWIFTLINT_TMP" "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_LATEST}/${SWIFTLINT_ZIP}"
	unzip -q "$SWIFTLINT_TMP/$SWIFTLINT_ZIP" swiftlint-static -d "$SWIFTLINT_TMP"
	sudo install "$SWIFTLINT_TMP/swiftlint-static" /usr/local/bin/swiftlint
	rm -rf "$SWIFTLINT_TMP"
fi

swiftly --version
swift --version
swift format --version
swiftlint version
