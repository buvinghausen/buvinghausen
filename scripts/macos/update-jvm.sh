#!/usr/bin/env bash
# Updates Java (Temurin), GraalVM CE, Kotlin, and Gradle via SDKMAN, plus
# async-profiler from its GitHub release. Darwin twin of scripts/update-jvm.sh
# — read that header for the GraalVM/`sdk upgrade`/prune reasoning; it all
# applies unchanged (the GraalVM lookup is keyed on $SDKMAN_PLATFORM, which
# sdkman-init.sh sets to darwinarm64 here).
#
# Darwin differences: SDKMAN's installer wires ~/.zshrc itself (no append
# needed); the prune loop lists directories without GNU find's -printf
# (BSD find has none); async-profiler's macOS asset is a zip, not a tarball;
# the script needs bash 4+ for `declare -A` — Homebrew's, from the base module.
#
# No `-u`/pipefail here for the same reason as the Fedora module: SDKMAN's own
# scripts are sourced into this shell and aren't strict-mode clean.
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh
require_bash4

export SDKMAN_DIR="$HOME/.sdkman"
if [[ ! -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
	log "SDKMAN not found — bootstrapping (see TOOLCHAIN-macos.md)"
	curl -s "https://get.sdkman.io" | bash
fi
source "$SDKMAN_DIR/bin/sdkman-init.sh"

if [[ ! -d "$SDKMAN_DIR/candidates/java" ]]; then
	log "Java / Kotlin / Gradle not found — installing (see TOOLCHAIN-macos.md)"
	sdk install java
	sdk install kotlin
	sdk install gradle
fi

run_sdk() {
	set +e
	sdk "$@"
	local status=$?
	set -e
	if [[ $status -gt 1 ]]; then
		echo "sdk $* failed (exit $status)" >&2
		exit "$status"
	fi
}

log "SDKMAN self-update"
run_sdk update

log "Java / Kotlin / Gradle upgrade"
run_sdk upgrade

default_java=$(curl -fsS "$SDKMAN_CANDIDATES_API/candidates/default/java")
[[ -n "$default_java" ]] || { echo "Could not resolve SDKMAN's default java" >&2; exit 1; }
graal=$(curl -fsS "$SDKMAN_CANDIDATES_API/candidates/java/$SDKMAN_PLATFORM/versions/all" \
	| tr ',' '\n' | grep -- "^${default_java%%.*}\..*-graalce\$" | sort -V | tail -1)
[[ -n "$graal" ]] || { echo "No -graalce build for java ${default_java%%.*} on $SDKMAN_PLATFORM" >&2; exit 1; }
if [[ ! -d "$SDKMAN_DIR/candidates/java/$graal" ]]; then
	log "GraalVM CE $graal not found — installing alongside $default_java (not made current)"
	run_sdk install java "$graal" <<<"n"
else
	log "GraalVM CE $graal already installed"
fi

series_key() {
	local v="$1" suffix="${1##*-}"
	[[ "$suffix" == "$v" ]] && suffix=""
	echo "${v%%.*}${suffix:+-$suffix}"
}

log "Pruning superseded patch releases (keeping the newest per major series)"
for dir in "$SDKMAN_DIR"/candidates/*/; do
	candidate=$(basename "$dir")
	current=$(basename "$(readlink "$dir/current" 2>/dev/null || true)")
	# Real installs are directories; `current` is a symlink and -d follows it,
	# so it is excluded by name instead of by type (no GNU -printf on BSD find).
	versions=$(for d in "$dir"*/; do d=$(basename "$d"); [[ "$d" == "current" ]] || echo "$d"; done | sort -V)
	[[ -z "$versions" ]] && continue
	declare -A newest=()
	while IFS= read -r v; do
		newest[$(series_key "$v")]="$v"
	done <<<"$versions"
	while IFS= read -r v; do
		keep="${newest[$(series_key "$v")]}"
		[[ "$v" == "$keep" || "$v" == "$current" ]] && continue
		echo "  $candidate/$v (kept $keep)"
		run_sdk uninstall "$candidate" "$v"
	done <<<"$versions"
	unset newest
done

# async-profiler: the macOS release is a universal zip whose single top-level
# directory unpacks to ~/.local/opt/async-profiler (asprof loads
# ../lib/libasyncProfiler.dylib relative to its own resolved path, so the tree
# stays together), entry points symlinked into ~/.local/bin.
log "async-profiler"
ensure_local_dirs
ASPROF_LATEST=$(github_latest_release async-profiler/async-profiler)
ASPROF_CURRENT=$(asprof --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$ASPROF_CURRENT" == "$ASPROF_LATEST" ]]; then
	echo "async-profiler already at $ASPROF_CURRENT — skipping"
else
	ASPROF_ZIP="async-profiler-${ASPROF_LATEST}-macos.zip"
	ASPROF_TMP=$(mktemp -d)
	curl -fsSL -o "$ASPROF_TMP/$ASPROF_ZIP" "https://github.com/async-profiler/async-profiler/releases/download/v${ASPROF_LATEST}/${ASPROF_ZIP}"
	unzip -q "$ASPROF_TMP/$ASPROF_ZIP" -d "$ASPROF_TMP/unpacked"
	rm -rf "$LOCAL_OPT/async-profiler"
	mv "$ASPROF_TMP/unpacked/async-profiler-${ASPROF_LATEST}-macos" "$LOCAL_OPT/async-profiler"
	ln -sf "$LOCAL_OPT/async-profiler/bin/asprof" "$LOCAL_BIN/asprof"
	ln -sf "$LOCAL_OPT/async-profiler/bin/jfrconv" "$LOCAL_BIN/jfrconv"
	rm -rf "$ASPROF_TMP"
fi

java -version
"$SDKMAN_DIR/candidates/java/$graal/bin/native-image" --version
asprof --version
kotlin -version
gradle --version
