#!/usr/bin/env bash
# Swift on macOS is Apple's toolchain, not swiftly's: the Command Line Tools
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

swift --version
swift format --version
swiftlint version
