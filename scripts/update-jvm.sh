#!/usr/bin/env bash
# Updates Java (Temurin), Kotlin, and Gradle via SDKMAN.
# `sdk upgrade` prompts per-candidate to uninstall the superseded version —
# that prompt IS the old-parts removal step for this stack, left interactive
# on purpose so you can decline for any candidate you've deliberately pinned.
#
# No `-u`/pipefail here: SDKMAN's own scripts (init and the `sdk` CLI itself)
# reference unset variables (e.g. $ZSH_VERSION, positional $2) with no
# default, and lean on `grep`/pipe idioms that return non-zero on a benign
# "no match" (e.g. "already up to date"). `sdk` is a shell function sourced
# into *this* shell, not a subprocess, so those internals run under whatever
# mode this script sets — fine interactively where nothing is in strict mode,
# fatal here otherwise. `-e` stays on for our own lines; scoped off with
# `set +e` around the two `sdk` calls specifically, with the exit code
# checked by hand so a real failure still stops the script.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export SDKMAN_DIR="$HOME/.sdkman"
if [[ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
	echo "SDKMAN not found — run the Java/Kotlin install steps in TOOLCHAIN.md first" >&2
	exit 1
fi
source "$SDKMAN_DIR/bin/sdkman-init.sh"

run_sdk() {
	set +e
	sdk "$@"
	local status=$?
	set -e
	# SDKMAN's own "nothing to do" paths (e.g. grep finding no candidates)
	# surface as exit 1 with no error text — only treat >1 as a real failure.
	if [[ $status -gt 1 ]]; then
		echo "sdk $* failed (exit $status)" >&2
		exit "$status"
	fi
}

log "SDKMAN self-update"
run_sdk update

log "Java / Kotlin / Gradle upgrade"
run_sdk upgrade

java -version
kotlin -version
gradle --version
