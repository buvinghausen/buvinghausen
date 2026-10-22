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
#
# Beside the NDK, and macOS-only: the Android SDK the Hyper repos' Android job
# runs on. platform-tools (adb), the emulator and an API 36 google_apis_ps16k
# system image (ci.yml's emulator target, arm64-v8a here for an arm64 host)
# run the APKs and the cross-built Go/Swift suites on a device; the platform
# and build-tools the .NET android workload builds the APKs against are read
# from the workload's own defaults (AndroidSdkPlatformVersion,
# AndroidSdkBuildToolsVersion in its newest Microsoft.Android.Sdk.Darwin pack),
# so they move when `dotnet workload update` moves it. sdkmanager needs the
# command-line-tools package and a JDK, the Fedora header's reason for skipping
# it; both exist here, so the SDK is sdkmanager's to keep current. The NDK
# stays a release archive, unchanged. Hard-depends on the jvm module (the JDK
# sdkmanager runs on; the workload accepts 21 through 25) and the dotnet
# module (the workload pack), both earlier in MODULES.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
require_cmd rustup "rustup not found — run the rust module first (see TOOLCHAIN-macos.md)"
ensure_local_dirs

export JAVA_HOME="${JAVA_HOME:-$HOME/.sdkman/candidates/java/current}"
[[ -x "$JAVA_HOME/bin/java" ]] || { echo "No JDK at $JAVA_HOME — run the jvm module first (sdkmanager runs on it, see TOOLCHAIN-macos.md)" >&2; exit 1; }

# ci.yml's emulator: api-level 36, target google_apis_ps16k. Edit with it.
ANDROID_API=36
ANDROID_SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis_ps16k;arm64-v8a"
ANDROID_AVD="hyper-api${ANDROID_API}"

# The workload's default for one property, from the newest installed pack.
android_workload_default() {
	local pack
	pack=$(find "${DOTNET_ROOT:-$HOME/.dotnet}/packs/Microsoft.Android.Sdk.Darwin" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)
	[[ -n "$pack" ]] || { echo "No Microsoft.Android.Sdk.Darwin pack — run the dotnet module first (it installs the android workload)" >&2; exit 1; }
	grep -rhoE "<$1 Condition=[^>]*>[^<]+" "$pack" | sed 's/.*>//' | sort -u | tail -1
}
ANDROID_PLATFORM="platforms;$(android_workload_default AndroidSdkPlatformVersion)"
ANDROID_BUILD_TOOLS="build-tools;$(android_workload_default AndroidSdkBuildToolsVersion)"

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

# Bootstrap only: the newest command-line-tools zip for this host, named in
# Google's repository index under the cmdline-tools;latest package. Its single
# top-level cmdline-tools/ directory has to become cmdline-tools/latest, the
# one layout sdkmanager accepts. From then on `sdkmanager --update` keeps
# cmdline-tools;latest (sdkmanager itself) current with everything else.
ANDROID_HOME="$LOCAL_OPT/android-sdk"
export ANDROID_HOME
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
	log "Android command-line tools not found — bootstrapping into $ANDROID_HOME"
	CLT_ZIP=$(curl -fsSL https://dl.google.com/android/repository/repository2-3.xml | tr -d '\n' \
		| sed 's/<remotePackage/\n<remotePackage/g' | grep 'path="cmdline-tools;latest"' \
		| grep -oE "commandlinetools-mac_$(uname -m)-[0-9]+_latest\.zip" | head -1 || true)
	[[ -n "$CLT_ZIP" ]] || { echo "Could not resolve the cmdline-tools;latest zip for mac_$(uname -m) from repository2-3.xml" >&2; exit 1; }
	CLT_TMP=$(mktemp -d)
	curl -fsSL -o "$CLT_TMP/$CLT_ZIP" "https://dl.google.com/android/repository/$CLT_ZIP"
	unzip -q "$CLT_TMP/$CLT_ZIP" -d "$CLT_TMP/unpacked"
	mkdir -p "$ANDROID_HOME/cmdline-tools"
	rm -rf "$ANDROID_HOME/cmdline-tools/latest"
	mv "$CLT_TMP/unpacked/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
	rm -rf "$CLT_TMP"
fi

append_zshrc_once "# Android SDK" <<'EOF2'

# Android SDK
export ANDROID_HOME=$HOME/.local/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator
EOF2

log "Android SDK — update installed packages"
"$SDKMANAGER" --update

log "Android SDK — platform-tools, emulator, ${ANDROID_PLATFORM}, ${ANDROID_BUILD_TOOLS}, ${ANDROID_SYSTEM_IMAGE}"
"$SDKMANAGER" --install platform-tools emulator "$ANDROID_PLATFORM" "$ANDROID_BUILD_TOOLS" "$ANDROID_SYSTEM_IMAGE"

# Superseded platforms and build-tools: whatever the workload no longer names.
log "Pruning platforms / build-tools the workload has moved past (kept ${ANDROID_PLATFORM}, ${ANDROID_BUILD_TOOLS})"
for kind in platforms build-tools; do
	for d in "$ANDROID_HOME/$kind"/*/; do
		[[ -d "$d" ]] || continue
		pkg="$kind;$(basename "$d")"
		[[ "$pkg" == "$ANDROID_PLATFORM" || "$pkg" == "$ANDROID_BUILD_TOOLS" ]] && continue
		echo "  $pkg"
		"$SDKMANAGER" --uninstall "$pkg"
	done
done

# One AVD on the CI image. avdmanager asks whether to make a custom hardware
# profile; "no" takes the default device.
log "AVD $ANDROID_AVD"
if "$AVDMANAGER" list avd -c 2>/dev/null | grep -xF "$ANDROID_AVD" >/dev/null; then
	echo "$ANDROID_AVD already exists"
else
	echo no | "$AVDMANAGER" create avd -n "$ANDROID_AVD" -k "$ANDROID_SYSTEM_IMAGE"
fi

NDK_BIN=$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin)
grep Pkg.Revision "$ANDROID_NDK_HOME/source.properties"
echo "prebuilt: $NDK_BIN"
"$NDK_BIN/clang" --version | head -1
rustup target list --installed | grep android
cargo ndk --version
"$SDKMANAGER" --version
"$ANDROID_HOME/platform-tools/adb" version | sed -n 1p
"$ANDROID_HOME/emulator/emulator" -version | sed -n 1p
"$AVDMANAGER" list avd -c
