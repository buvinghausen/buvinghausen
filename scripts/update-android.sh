#!/usr/bin/env bash
# Installs/updates the Android NDK plus the Rust side that consumes it: the
# Android rustup targets and cargo-ndk, so a Hyper* core's cdylib can be
# built and linked for Android here instead of only being clippy-checked
# (HyperUuid's lint-rust CI job runs `cargo clippy --target
# aarch64-linux-android`; clippy never links, so the target alone covers CI,
# and the NDK is what covers the build the CI job doesn't do). Hard-depends
# on rustup, like update-wasm.sh — runs after `rust` in update-toolchain.sh's
# MODULES order and hard-fails with a pointer rather than bootstrapping it.
#
# The NDK is a plain release zip from dl.google.com, not an `sdkmanager`
# install: sdkmanager needs the whole command-line-tools package and a JDK
# just to download one zip, and nothing here needs the rest of the Android
# SDK (no platforms, no build-tools, no emulator — the NDK is the linker and
# sysroot, which is all a cdylib build needs). Takes pwsh/async-profiler's
# shape: unpacked under /opt, with a version-free /opt/android-ndk symlink as
# the stable path ANDROID_NDK_HOME points at, and the superseded versioned
# directory removed once the symlink has moved.
#
# Google publishes NDK host builds for linux-x86_64, darwin and windows only
# (developer.android.com/ndk/downloads lists exactly one Linux package, and
# there is no linux-aarch64 one) — so on the Snapdragon box this module
# prints why and exits 0 rather than failing the full pass every time. That
# is a loud, explicit skip, not a fallback: nothing Android gets installed
# there, and the message says so.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

if [[ -f "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi
require_cmd rustup "rustup not found — run the rust module first (see TOOLCHAIN.md)"

if [[ "$(uname -m)" != "x86_64" ]]; then
	echo "SKIPPED: the Android NDK has no $(uname -m) Linux host build (linux-x86_64 only) — see TOOLCHAIN.md's Android section" >&2
	exit 0
fi

# android/ndk's GitHub releases carry every NDK release, betas/rcs flagged
# prerelease. Not lib.sh's github_latest_release: GitHub's "latest" is the
# most recently *created* non-prerelease, and point releases of an older
# line land after newer majors (r27d was published after r28c), so "latest"
# can walk backwards. Resolved from the release list instead — stable tags
# only, highest by version sort (r28c < r29 < r30).
ndk_latest_release() {
	curl -s 'https://api.github.com/repos/android/ndk/releases?per_page=30' \
		| tr -d ' \n' | sed 's/{/\n{/g' \
		| grep -v '"prerelease":true' \
		| grep -o '"tag_name":"r[0-9]*[a-z]\{0,1\}"' \
		| cut -d'"' -f4 | sort -V | tail -1
}

NDK_ROOT=/opt/android-ndk
NDK_LATEST=$(ndk_latest_release)
[[ -n "$NDK_LATEST" ]] || { echo "Could not resolve the latest Android NDK release" >&2; exit 1; }
NDK_CURRENT=$(basename "$(readlink "$NDK_ROOT" 2>/dev/null || true)" | sed 's/^android-ndk-//')

log "Android NDK"
if [[ "$NDK_CURRENT" == "$NDK_LATEST" ]]; then
	echo "NDK already at $NDK_CURRENT — skipping"
else
	NDK_ZIP="android-ndk-${NDK_LATEST}-linux.zip"
	NDK_TMP=$(mktemp -d)
	echo "Downloading $NDK_ZIP (~700 MB)"
	wget -q -P "$NDK_TMP" "https://dl.google.com/android/repository/${NDK_ZIP}"
	# The zip's single top-level directory is android-ndk-<release>, so
	# extracting straight into /opt lands it at the versioned path.
	sudo unzip -q "$NDK_TMP/$NDK_ZIP" -d /opt
	rm -rf "$NDK_TMP"
	sudo ln -sfn "/opt/android-ndk-${NDK_LATEST}" "$NDK_ROOT"
	if [[ -n "$NDK_CURRENT" && -d "/opt/android-ndk-${NDK_CURRENT}" ]]; then
		echo "Removing superseded /opt/android-ndk-${NDK_CURRENT} (kept ${NDK_LATEST})"
		sudo rm -rf "/opt/android-ndk-${NDK_CURRENT}"
	fi
fi

# cargo-ndk reads ANDROID_NDK_HOME; nothing from the NDK goes on PATH (its
# toolchain dir carries its own clang/lld/llvm-* that would shadow the
# system ones), so the NDK's tools are reached by path, as in the verify
# step below.
append_bashrc_once "# Android NDK" <<'EOF'

# Android NDK
export ANDROID_NDK_HOME=/opt/android-ndk
EOF
export ANDROID_NDK_HOME=$NDK_ROOT

# aarch64 is the ABI every Android device CI cares about (and the one
# HyperUuid's lint-rust job checks); x86_64 is the emulator's.
log "Rust Android targets"
rustup target add aarch64-linux-android x86_64-linux-android

# cargo-ndk points cargo's linker and cc-rs's CC/AR at the NDK's per-target
# clang wrappers for the API level asked for (`cargo ndk -t arm64-v8a
# --platform 21 ...`), so no per-target linker lines in .cargo/config.toml.
log "cargo-ndk"
cargo install cargo-ndk

NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
grep Pkg.Revision "$ANDROID_NDK_HOME/source.properties"
"$NDK_BIN/clang" --version | head -1
rustup target list --installed | grep android
cargo ndk --version
