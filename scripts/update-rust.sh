#!/usr/bin/env bash
# Updates Rust via rustup and refreshes cargo-installed tooling.
# rustup replaces the active toolchain in place — no separate cleanup needed.
#
# Bootstraps rustup itself when missing (fresh machine / fresh distro) —
# rustup-init.sh doesn't touch shell rc files on its own (verified: the
# sh.rustup.rs wrapper just downloads and execs the real installer binary,
# which leaves PATH wiring to the caller), so ~/.bashrc is appended here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

if [[ -f "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi

if ! command -v rustup >/dev/null 2>&1; then
	log "rustup not found — bootstrapping (see TOOLCHAIN.md)"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	append_bashrc_once "# Rust" <<'EOF'

# Rust
source "$HOME/.cargo/env"
EOF
	source "$HOME/.cargo/env"
fi
require_cmd rustup "rustup install failed — check the installer output above"

log "rustup"
rustup update

log "rustup components"
rustup component add rust-analyzer clippy rustfmt

log "cargo tools"
cargo install cargo-watch cargo-edit

log "cargo-nextest (prebuilt binary — building from source takes 15+ min, see TOOLCHAIN.md)"
NEXTEST_PLATFORM=$(uname -m | sed 's/x86_64/linux/;s/aarch64/linux-arm/')
curl -LsSf "https://get.nexte.st/latest/${NEXTEST_PLATFORM}" | tar zxf - -C "${CARGO_HOME:-$HOME/.cargo}/bin"

rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
