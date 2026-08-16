#!/usr/bin/env bash
# Updates Java (Temurin), Kotlin, and Gradle via SDKMAN.
# `sdk upgrade` sometimes offers to uninstall what it supersedes, but not
# reliably — old patch releases accumulate side by side (observed: java
# 25.0.3-tem still present next to 25.0.4-tem). The prune step below is the
# deterministic removal pass: within each candidate, keep only the newest
# version per major series (the series key includes the vendor suffix, so
# 25.0.x-tem only competes with other -tem builds). Scoping to the series
# rather than "newest overall" means a deliberately pinned older major
# (e.g. a java 21 kept alongside 25) is never touched, and the version
# `current` points at is skipped unconditionally as a final guard.
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
	log "SDKMAN not found — bootstrapping (see TOOLCHAIN.md)"
	curl -s "https://get.sdkman.io" | bash
fi
source "$SDKMAN_DIR/bin/sdkman-init.sh"

# `sdk upgrade` below only upgrades candidates already installed — on a fresh
# SDKMAN bootstrap there are none, so the initial install (latest LTS Temurin
# + Kotlin + Gradle, per TOOLCHAIN.md) has to happen explicitly first.
if [[ ! -d "$SDKMAN_DIR/candidates/java" ]]; then
	log "Java / Kotlin / Gradle not found — installing (see TOOLCHAIN.md)"
	sdk install java
	sdk install kotlin
	sdk install gradle
fi

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

# Series key: major version + vendor suffix when present (25.0.4-tem → 25-tem,
# gradle 9.6.1 → 9). Installed versions are real directories; `current` is a
# symlink, which `-type d` (no -L) already excludes.
series_key() {
	local v="$1" suffix="${1##*-}"
	[[ "$suffix" == "$v" ]] && suffix=""
	echo "${v%%.*}${suffix:+-$suffix}"
}

log "Pruning superseded patch releases (keeping the newest per major series)"
for dir in "$SDKMAN_DIR"/candidates/*/; do
	candidate=$(basename "$dir")
	current=$(basename "$(readlink "$dir/current" 2>/dev/null || true)")
	versions=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
	[[ -z "$versions" ]] && continue
	declare -A newest=()
	while IFS= read -r v; do
		newest[$(series_key "$v")]="$v" # sort -V order → last one wins
	done <<<"$versions"
	while IFS= read -r v; do
		keep="${newest[$(series_key "$v")]}"
		[[ "$v" == "$keep" || "$v" == "$current" ]] && continue
		echo "  $candidate/$v (kept $keep)"
		run_sdk uninstall "$candidate" "$v"
	done <<<"$versions"
	unset newest
done

java -version
kotlin -version
gradle --version
