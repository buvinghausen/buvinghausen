#!/usr/bin/env bash
# Updates Java (Temurin), GraalVM CE, Kotlin, and Gradle via SDKMAN, plus
# async-profiler from its GitHub release tarball.
#
# GraalVM CE is a second java *version* under the same SDKMAN candidate, kept
# alongside the Temurin default — never made `current`. `sdk upgrade` can't
# manage it: it only compares what's installed against the candidate's single
# remote default (`candidates/default/java` → 25.0.4-tem), so a -graalce build
# is invisible to it — never offered, never upgraded. The GraalVM step below
# resolves the newest -graalce in the default's major series from the same
# `versions/all` endpoint `sdk list` reads and installs it when missing; the
# prune step then retires the one it superseded (series key 25-graalce).
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

# Tie GraalVM CE's major to the Temurin default's major (the LTS SDKMAN picks
# for a bare `sdk install java`) rather than "newest -graalce overall", so a
# non-LTS GraalVM (26.x once it exists next to 26.0.2-tem) is never pulled in
# ahead of the LTS the rest of the JVM stack sits on. SDKMAN_CANDIDATES_API
# and SDKMAN_PLATFORM are both exported by sdkman-init.sh.
default_java=$(curl -fsS "$SDKMAN_CANDIDATES_API/candidates/default/java")
[[ -n "$default_java" ]] || { echo "Could not resolve SDKMAN's default java" >&2; exit 1; }
graal=$(curl -fsS "$SDKMAN_CANDIDATES_API/candidates/java/$SDKMAN_PLATFORM/versions/all" \
	| tr ',' '\n' | grep -- "^${default_java%%.*}\..*-graalce\$" | sort -V | tail -1)
[[ -n "$graal" ]] || { echo "No -graalce build for java ${default_java%%.*} on $SDKMAN_PLATFORM" >&2; exit 1; }
if [[ ! -d "$SDKMAN_DIR/candidates/java/$graal" ]]; then
	# `sdk install java <version>` asks "set as default? (Y/n)" whenever a
	# `current` exists, and an empty answer (EOF on a non-tty stdin) means yes —
	# so answer explicitly; `current` stays on Temurin.
	log "GraalVM CE $graal not found — installing alongside $default_java (not made current)"
	run_sdk install java "$graal" <<<"n"
else
	log "GraalVM CE $graal already installed"
fi

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

# async-profiler: sampling CPU/allocation/lock profiler for the JVM, next to
# the JFR every JDK here already bundles (`jcmd <pid> JFR.start`, `jfr print`).
# Not an SDKMAN candidate, so it takes pwsh's shape from update-tools.sh: a
# multi-file tarball (asprof loads ../lib/libasyncProfiler.so relative to its
# own resolved path) unpacked under /opt, entry points symlinked onto PATH.
log "async-profiler"
ASPROF_LATEST=$(github_latest_release async-profiler/async-profiler)
ASPROF_CURRENT=$(asprof --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$ASPROF_CURRENT" == "$ASPROF_LATEST" ]]; then
	echo "async-profiler already at $ASPROF_CURRENT — skipping"
else
	ASPROF_TGZ="async-profiler-${ASPROF_LATEST}-linux-$(arch_x64_arm64).tar.gz"
	ASPROF_TMP=$(mktemp -d)
	wget -q -P "$ASPROF_TMP" "https://github.com/async-profiler/async-profiler/releases/download/v${ASPROF_LATEST}/${ASPROF_TGZ}"
	sudo mkdir -p /opt/async-profiler
	sudo tar -xzf "$ASPROF_TMP/$ASPROF_TGZ" -C /opt/async-profiler --strip-components=1
	sudo ln -sf /opt/async-profiler/bin/asprof /usr/local/bin/asprof
	sudo ln -sf /opt/async-profiler/bin/jfrconv /usr/local/bin/jfrconv
	rm -rf "$ASPROF_TMP"
fi

java -version
"$SDKMAN_DIR/candidates/java/$graal/bin/native-image" --version
asprof --version
kotlin -version
gradle --version
