#!/usr/bin/env bash
# Updates the cross-cutting WASM toolchain used by multiple language stacks:
# Rust's wasm32-wasip1/wasm32-unknown-unknown/wasm32-unknown-emscripten targets,
# wasm-pack (the wasm-bindgen test runner for wasm32-unknown-unknown), the
# Emscripten SDK (emcc — the linker wasm32-unknown-emscripten needs, since
# unlike the other two targets it doesn't use rust-lld), wasmtime (a standalone
# WASI runtime for testing wasm32-wasip1 binaries without a browser/Node in the
# loop), and .NET's wasm-tools workload (Blazor WebAssembly + native interop via
# <NativeFileReference>). Hard-depends on rustup and dotnet already being
# installed — runs after both in update-toolchain.sh's MODULES order, and
# hard-fails via require_cmd (pointing back to their own sections) rather than
# bootstrapping either itself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

require_cmd rustup "rustup not found — run the rust module first (see TOOLCHAIN.md)"
require_cmd dotnet "dotnet not found — run the dotnet module first (see TOOLCHAIN.md)"

log "Rust wasm targets"
rustup target add wasm32-wasip1 wasm32-unknown-unknown wasm32-unknown-emscripten

# wasm-pack drives the wasm-bindgen test crates (`wasm-pack test --headless
# --chrome` over rust/browser-test — what hyper-build-wasm.yml runs), fetching
# the matching wasm-bindgen test runner and chromedriver itself.
log "wasm-pack"
cargo install wasm-pack

log "Emscripten SDK"
if [[ ! -d "$HOME/emsdk" ]]; then
	git clone https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
fi
(
	cd "$HOME/emsdk"
	git pull
	./emsdk install latest
	./emsdk activate latest
)
append_bashrc_once "# Emscripten SDK" <<'EOF'

# Emscripten SDK
source "$HOME/emsdk/emsdk_env.sh" > /dev/null
EOF
source "$HOME/emsdk/emsdk_env.sh" > /dev/null

log "wasmtime"
curl https://wasmtime.dev/install.sh -sSf | bash
# The installer wires $WASMTIME_HOME/PATH into ~/.bashrc itself (idempotency
# guarded by its own grep check) — just need it live for this script's own
# verify step below, not a manual append_bashrc_once.
export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"

log ".NET wasm-tools workload"
dotnet workload install wasm-tools

# Real, verified bug (confirmed on both linux-arm64 and linux-x64, and independently in an
# unrelated project — PyO3/maturin#2549): rustc >= 1.87 emits WASM target-feature metadata
# that Binaryen's wasm-opt only learned to honor from Emscripten 3.1.74 onward. Every .NET
# SDK band's wasm-tools workload observed so far bundles an older Emscripten (3.1.56 for the
# 10.0 LTS band, 6.0.2's own wasm-opt build for the 11.0 preview band) — both die with
# `Unknown option '--enable-bulk-memory-opt'` the moment NativeFileReference forces a native
# relink. Fix: drop the newer, compatible wasm-opt from this same script's own emsdk install
# in over each installed Emscripten Sdk pack's bundled one. Re-run after any
# `dotnet workload update`, which can silently restore the broken stock binary.
log "Patching bundled wasm-opt in every installed Emscripten Sdk pack (see comment above)"
DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
for sdk_pack in "$DOTNET_ROOT/packs"/Microsoft.NET.Runtime.Emscripten.*.Sdk.*; do
	[[ -d "$sdk_pack" ]] || continue
	version_dir=$(find "$sdk_pack" -maxdepth 1 -mindepth 1 -type d | head -1)
	target="$version_dir/tools/bin/wasm-opt"
	if [[ -f "$target" ]] && ! cmp -s "$target" "$HOME/emsdk/upstream/bin/wasm-opt"; then
		echo "  $target"
		cp "$HOME/emsdk/upstream/bin/wasm-opt" "$target"
	fi
done

rustup target list --installed | grep wasm
wasm-pack --version
emcc --version
wasmtime --version
dotnet workload list
