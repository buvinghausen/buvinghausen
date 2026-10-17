#!/usr/bin/env bash
# Installs/updates the Android NDK plus the Rust side that consumes it: the
# Android rustup targets and cargo-ndk. Darwin twin of scripts/update-android.sh
# — read that header for why the NDK is a plain release archive rather than an
# sdkmanager install, and why nothing from it goes on PATH. Hard-depends on
# rustup (runs after `rust` in MODULES).
#
# Darwin differences: Google ships a macOS host build (universal), so the
# Fedora module's arm64 skip does not exist here — this is the first box in
# the pass where Android works on arm64. The archive is the darwin .zip (same
# contents as the .dmg Homebrew's cask uses, minus the disk-image mount): the
# NDK root sits inside an app bundle, AndroidNDK<build>.app/Contents/NDK, and
# is found by its source.properties rather than by an assumed path. It lives
# under ~/.local/opt with a version-free ~/.local/opt/android-ndk symlink as
# the stable path ANDROID_NDK_HOME points at; the superseded tree is removed
# once the symlink has moved. The LLVM prebuilt dir is darwin-x86_64 even on
# Apple Silicon (universal binaries) — resolved by glob, printed in verify.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
require_cmd rustup "rustup not found — run the rust module first (see TOOLCHAIN-macos.md)"
ensure_local_dirs

# Stable tags only, highest by version sort — not GitHub's "latest", which is
# the most recently *created* release and walks backwards onto LTS point
# releases (r27d was published after r28c). Same resolver as the Fedora module.
ndk_latest_release() {
	curl -s 'https://api.github.com/repos/android/ndk/releases?per_page=30' \
		| tr -d ' \n' | sed 's/{/\n{/g' \
		| grep -v '"prerelease":true' \
		| grep -o '"tag_name":"r[0-9]*[a-z]\{0,1\}"' \
		| cut -d'"' -f4 | sort -V | tail -1
}

NDK_ROOT="$LOCAL_OPT/android-ndk"
NDK_LATEST=$(ndk_latest_release)
[[ -n "$NDK_LATEST" ]] || { echo "Could not resolve the latest Android NDK release" >&2; exit 1; }
NDK_CURRENT=$(basename "$(readlink "$NDK_ROOT" 2>/dev/null || true)" | sed 's/^android-ndk-//')

log "Android NDK"
if [[ "$NDK_CURRENT" == "$NDK_LATEST" ]]; then
	echo "NDK already at $NDK_CURRENT — skipping"
else
	NDK_ZIP="android-ndk-${NDK_LATEST}-darwin.zip"
	NDK_TMP=$(mktemp -d)
	echo "Downloading $NDK_ZIP (~1 GB)"
	curl -fsSL -o "$NDK_TMP/$NDK_ZIP" "https://dl.google.com/android/repository/${NDK_ZIP}"
	unzip -q "$NDK_TMP/$NDK_ZIP" -d "$NDK_TMP/unpacked"
	rm -f "$NDK_TMP/$NDK_ZIP"
	# The NDK root is the one directory carrying source.properties. Exactly one,
	# or the archive isn't shaped the way this script understands — say so with
	# the real listing rather than guessing.
	NDK_SRC=$(find "$NDK_TMP/unpacked" -maxdepth 4 -name source.properties -exec dirname {} \;)
	if [[ $(wc -l <<<"$NDK_SRC") -ne 1 || -z "$NDK_SRC" ]]; then
		echo "Expected exactly one source.properties under the unpacked NDK zip, found:" >&2
		echo "$NDK_SRC" >&2
		find "$NDK_TMP/unpacked" -maxdepth 3 >&2
		exit 1
	fi
	rm -rf "$LOCAL_OPT/android-ndk-${NDK_LATEST}"
	mv "$NDK_SRC" "$LOCAL_OPT/android-ndk-${NDK_LATEST}"
	rm -rf "$NDK_TMP"
	ln -sfn "$LOCAL_OPT/android-ndk-${NDK_LATEST}" "$NDK_ROOT"
	if [[ -n "$NDK_CURRENT" && -d "$LOCAL_OPT/android-ndk-${NDK_CURRENT}" ]]; then
		echo "Removing superseded $LOCAL_OPT/android-ndk-${NDK_CURRENT} (kept ${NDK_LATEST})"
		rm -rf "$LOCAL_OPT/android-ndk-${NDK_CURRENT}"
	fi
fi

append_zshrc_once "# Android NDK" <<'EOF2'

# Android NDK
export ANDROID_NDK_HOME=$HOME/.local/opt/android-ndk
EOF2
export ANDROID_NDK_HOME=$NDK_ROOT

log "Rust Android targets"
rustup target add aarch64-linux-android x86_64-linux-android

log "cargo-ndk"
cargo install cargo-ndk

NDK_BIN=$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin)
grep Pkg.Revision "$ANDROID_NDK_HOME/source.properties"
echo "prebuilt: $NDK_BIN"
"$NDK_BIN/clang" --version | head -1
rustup target list --installed | grep android
cargo ndk --version
