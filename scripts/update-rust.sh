#!/usr/bin/env bash
# Updates Rust via rustup and refreshes cargo-installed tooling.
# rustup replaces the active toolchain in place — no separate cleanup needed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

if [[ -f "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi
require_cmd rustup "rustup not found — run the Rust install steps in TOOLCHAIN.md first"

log "rustup"
rustup update

log "rustup components"
rustup component add rust-analyzer clippy rustfmt

log "cargo tools"
cargo install cargo-watch cargo-edit

log "cargo-nextest (prebuilt binary — building from source takes 15+ min, see TOOLCHAIN.md)"
NEXTEST_PLATFORM=$(uname -m | sed 's/x86_64/linux-x64/;s/aarch64/linux-arm/')
curl -LsSf "https://get.nexte.st/latest/${NEXTEST_PLATFORM}" | tar zxf - -C "${CARGO_HOME:-$HOME/.cargo}/bin"

rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
