# shellcheck shell=bash
# Shared helpers for scripts/update-*.sh. Sourced, not executed.

log() { printf '\n==> %s\n' "$1"; }

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || { echo "$2" >&2; exit 1; }
}

# Matches the arch-detection convention used throughout TOOLCHAIN.md
arch_amd64_arm64() { uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'; }
arch_x64_arm64() { uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/'; }
