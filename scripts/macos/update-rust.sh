#!/usr/bin/env bash
# Updates Rust via rustup and refreshes cargo-installed tooling. Darwin twin of
# scripts/update-rust.sh: rustup-init leaves PATH wiring to the caller on
# every platform, so ~/.zshrc gets the `. ~/.cargo/env` line here; nextest's
# prebuilt binary is the universal-apple-darwin one (`latest/mac`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

if [[ -f "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi

if ! command -v rustup >/dev/null 2>&1; then
	log "rustup not found — bootstrapping (see TOOLCHAIN-macos.md)"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
	append_zshrc_once "# Rust" <<'EOF2'

# Rust
source "$HOME/.cargo/env"
EOF2
	source "$HOME/.cargo/env"
fi
require_cmd rustup "rustup install failed — check the installer output above"

log "rustup"
rustup update

log "rustup components"
rustup component add rust-analyzer clippy rustfmt

log "bare-metal target (no_std check: cargo check --no-default-features --target thumbv7em-none-eabi)"
rustup target add thumbv7em-none-eabi

log "cargo tools"
cargo install cargo-watch cargo-edit

log "samply (profiler) / cargo-semver-checks"
cargo install --locked samply cargo-semver-checks

log "cargo-nextest (prebuilt universal-apple-darwin binary, see TOOLCHAIN-macos.md)"
curl -LsSf "https://get.nexte.st/latest/mac" | tar zxf - -C "${CARGO_HOME:-$HOME/.cargo}/bin"

rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
samply --version
cargo semver-checks --version
