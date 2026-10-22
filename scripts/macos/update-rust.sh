#!/usr/bin/env bash
# Updates Rust via rustup and refreshes cargo-installed tooling. Darwin twin of
# scripts/update-rust.sh: rustup-init leaves PATH wiring to the caller on
# every platform, so ~/.zshrc gets the `. ~/.cargo/env` line here; nextest's
# prebuilt binary is the universal-apple-darwin one (`latest/mac`).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

# Every `rust-version` the Hyper repos declare (HyperUuid 1.85, HyperCast and
# HyperTabular 1.88): the local twin of each ci.yml's MSRV job, which reads it
# from rust/Cargo.toml. Same role as update-ruby.sh's RUBY_COMPAT_SERIES; edit
# it when a Cargo.toml's rust-version moves.
RUST_MSRV_SERIES=(1.85 1.88)

# The Apple targets the Forge's macOS legs cross-build: x86_64-apple-darwin
# (osx-x64, tested under Rosetta, see update-base.sh) and the iOS device,
# simulator and Mac Catalyst static libraries behind the Swift xcframework,
# Go's staticlib and C#'s iOS / Mac Catalyst apps.
APPLE_TARGETS=(x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-ios-macabi x86_64-apple-ios-macabi)

# The rest of the Forge's static-libs set (build-static-libs.sh): Linux glibc
# and musl, and Windows MSVC, both architectures. A static library is compiled
# and never linked, so they cross-build from this box with no C toolchain;
# the archive trim needs llvm-tools' llvm-ar. The script adds both itself when
# missing; having them here keeps them current with stable and off the
# critical path of a build.
STATIC_TARGETS=(x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-unknown-linux-musl aarch64-unknown-linux-musl x86_64-pc-windows-msvc aarch64-pc-windows-msvc)

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
rustup component add rust-analyzer clippy rustfmt llvm-tools

log "bare-metal target (no_std check: cargo check --no-default-features --target thumbv7em-none-eabi)"
rustup target add thumbv7em-none-eabi

log "Apple targets (${APPLE_TARGETS[*]})"
rustup target add "${APPLE_TARGETS[@]}"

log "Static-library targets (${STATIC_TARGETS[*]})"
rustup target add "${STATIC_TARGETS[@]}"

# `rustup toolchain install 1.85` resolves the newest 1.85.x and names the
# toolchain by its series, so a point release lands in place and there is
# nothing to prune within one. Pinned toolchains outside the list go; stable
# (and any nightly) is left alone.
log "MSRV toolchains (${RUST_MSRV_SERIES[*]})"
for msrv in "${RUST_MSRV_SERIES[@]}"; do
	rustup toolchain install "$msrv" --profile minimal
done
while IFS= read -r tc; do
	series=$(grep -oE '^[0-9]+\.[0-9]+' <<<"$tc" || true)
	[[ -z "$series" || " ${RUST_MSRV_SERIES[*]} " == *" $series "* ]] && continue
	echo "  $tc (not a declared rust-version)"
	rustup toolchain uninstall "$tc"
done < <(rustup toolchain list | awk '{print $1}')

log "cargo tools"
cargo install cargo-watch cargo-edit

log "samply (profiler) / cargo-semver-checks"
cargo install --locked samply cargo-semver-checks

log "cargo-nextest (prebuilt universal-apple-darwin binary, see TOOLCHAIN-macos.md)"
curl -LsSf "https://get.nexte.st/latest/mac" | tar zxf - -C "${CARGO_HOME:-$HOME/.cargo}/bin"

rustc --version
for msrv in "${RUST_MSRV_SERIES[@]}"; do
	rustup run "$msrv" rustc --version
done
rustup target list --installed | grep -E "apple|linux-(gnu|musl)|windows-msvc"
cargo --version
rust-analyzer --version
cargo nextest --version
samply --version
cargo semver-checks --version
