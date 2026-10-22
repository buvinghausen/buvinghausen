#!/usr/bin/env bash
# Swift on macOS is Apple's toolchain (swift.org's sits beside it only for
# Swift SDKs, see below): the Command Line Tools
# ship `swift`, `swift build`/SPM and `swift format`, and full Xcode adds the
# platform SDKs (iOS — the Hyper repos' iOS smoke test) and Instruments/xctrace.
# Both update through Apple (`softwareupdate` / the App Store), so there is no
# toolchain install or prune here — this module verifies the Apple side is
# selected and keeps SwiftLint (the Hyper repos' lint-docs-swift CI gate)
# current from Homebrew, which carries the same 0.65.x CI pins.
#
# Xcode itself is a manual App Store install (sudo one-time steps documented
# in TOOLCHAIN-macos.md). When Xcode is present but not the selected developer
# directory, this fails loudly with the exact commands rather than running
# sudo — nothing in this pass runs as root. When it's absent, the CLT Swift is
# the toolchain and that is a documented state, not a failure.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

log "Developer directory"
DEV_DIR=$(xcode-select -p 2>/dev/null || true)
[[ -n "$DEV_DIR" ]] || { echo "No developer directory selected — run \`xcode-select --install\`, or install Xcode (see TOOLCHAIN-macos.md)" >&2; exit 1; }
echo "$DEV_DIR"
if [[ -d /Applications/Xcode.app ]]; then
	if [[ "$DEV_DIR" != /Applications/Xcode.app/* ]]; then
		cat >&2 <<'MSG'
Xcode is installed but not selected. One-time, by hand (needs sudo):
  sudo xcode-select -s /Applications/Xcode.app
  sudo xcodebuild -license accept
  xcodebuild -runFirstLaunch
MSG
		exit 1
	fi
	xcodebuild -version
else
	echo "Xcode not installed — Command Line Tools Swift in use (iOS SDK / Instruments / XCTest unavailable until Xcode is added, see TOOLCHAIN-macos.md)"
	# SwiftLint loads sourcekitdInProc from the selected toolchain and, with
	# only the CLT selected, searches every Xcode path but not the CLT's
	# (crashes, exit 133 — hit on the first run). TOOLCHAIN_DIR is the
	# override it honors; the CLT carries the framework under usr/lib. The
	# guard makes the line a no-op once Xcode is selected instead.
	export TOOLCHAIN_DIR="$DEV_DIR"
fi
append_zshrc_once "# SwiftLint on the Command Line Tools" <<'EOF2'

# SwiftLint on the Command Line Tools (no-op once Xcode is the selected developer dir)
[[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]] && export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools
EOF2

log "SwiftLint (Homebrew)"
brew_ensure swiftlint

# swift.org's toolchain beside Apple's, for one job: Swift SDKs. The Hyper
# repos cross-build their Swift suite for Android with swift.org's Android SDK
# (android_build_suite.sh), and Apple's compiler refuses that SDK's modules
# ("compiled module was created by a different version of the compiler",
# hit on the first run with Xcode 27.1's Swift 6.4). swiftly installs the
# swift.org release of the same minor as Xcode's Swift into
# ~/Library/Developer/Toolchains; it is deliberately NOT on PATH (init runs
# with --no-modify-profile), so `swift` and `xcrun swift` stay Apple's
# everywhere else. A job that needs it puts its usr/bin first for that run:
#   PATH="$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin:$PATH"
# The static-Linux and wasm SDKs need no host toolchain here: the Forge runs
# them inside swift:<version> containers.
log "swiftly + swift.org toolchain (Swift SDKs only, off PATH)"
SWIFTLY="$HOME/.swiftly/bin/swiftly"
if [[ ! -x "$SWIFTLY" ]]; then
	SWIFTLY_TMP=$(mktemp -d)
	curl -fsSL -o "$SWIFTLY_TMP/swiftly.pkg" https://download.swift.org/swiftly/darwin/swiftly.pkg
	# Notarized by swift.org's Developer ID; refuse anything else.
	pkgutil --check-signature "$SWIFTLY_TMP/swiftly.pkg" | grep -F "Notarization: trusted by the Apple notary service" >/dev/null \
		|| { echo "swiftly.pkg is not notarized — not installing it" >&2; exit 1; }
	installer -pkg "$SWIFTLY_TMP/swiftly.pkg" -target CurrentUserHomeDirectory
	rm -rf "$SWIFTLY_TMP"
	"$SWIFTLY" init --no-modify-profile --skip-install --assume-yes --quiet-shell-followup
fi
"$SWIFTLY" self-update --assume-yes
APPLE_SWIFT_MINOR=$(xcrun swift --version 2>&1 | sed -n 's/.*Apple Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)
[[ -n "$APPLE_SWIFT_MINOR" ]] || { echo "Could not read Apple's Swift version from xcrun swift --version" >&2; exit 1; }
"$SWIFTLY" install "$APPLE_SWIFT_MINOR" --assume-yes
# Newest installed release of that minor kept; every other swift.org release goes.
SWIFT_KEEP=$(find "$HOME/Library/Developer/Toolchains" -maxdepth 1 -name "swift-${APPLE_SWIFT_MINOR}*-RELEASE.xctoolchain" \
	| sed 's|.*/swift-\(.*\)-RELEASE.xctoolchain|\1|' | sort -V | tail -1)
[[ -n "$SWIFT_KEEP" ]] || { echo "swiftly install $APPLE_SWIFT_MINOR left no swift-${APPLE_SWIFT_MINOR}*-RELEASE.xctoolchain" >&2; exit 1; }
while IFS= read -r v; do
	[[ -z "$v" || "$v" == "$SWIFT_KEEP" ]] && continue
	echo "  swift.org $v (kept $SWIFT_KEEP)"
	"$SWIFTLY" uninstall "$v" --assume-yes
done < <(find "$HOME/Library/Developer/Toolchains" -maxdepth 1 -name 'swift-*-RELEASE.xctoolchain' | sed 's|.*/swift-\(.*\)-RELEASE.xctoolchain|\1|')

# Swift SDKs are installed per job (android_build_suite.sh installs the one
# matching the toolchain on PATH) and only work with that exact release, so
# a superseded one is dead weight — and worse: with 6.4.0's and 6.4.1's
# Android SDKs both installed, `--swift-sdk aarch64-unknown-linux-android28`
# stopped with "matched multiple SDKs". Every swift-<version>-RELEASE_* SDK
# whose version is not the kept toolchain's is removed.
SWIFT_ORG="$HOME/Library/Developer/Toolchains/swift-${SWIFT_KEEP}-RELEASE.xctoolchain/usr/bin/swift"
while IFS= read -r sdk; do
	[[ "$sdk" =~ ^swift-([0-9.]+)-RELEASE_ ]] || continue
	[[ "${BASH_REMATCH[1]}" == "$SWIFT_KEEP" ]] && continue
	echo "  Swift SDK $sdk (toolchain is $SWIFT_KEEP)"
	"$SWIFT_ORG" sdk remove "$sdk"
done < <("$SWIFT_ORG" sdk list 2>/dev/null)

swift --version
swift format --version
swiftlint version
"$SWIFTLY" --version
"$SWIFT_ORG" --version 2>&1 | head -1
"$SWIFT_ORG" sdk list
