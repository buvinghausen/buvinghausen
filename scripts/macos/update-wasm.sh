#!/usr/bin/env bash
# Updates the cross-cutting WASM toolchain used by multiple language stacks:
# Rust's wasm32-wasip1/wasm32-unknown-unknown/wasm32-unknown-emscripten targets,
# wasm-pack, the Emscripten SDK, wasmtime, and .NET's wasm-tools workload —
# plus the wasm-opt patch over every installed Emscripten Sdk pack. Darwin twin
# of scripts/update-wasm.sh; read that header for what each piece is for and
# the verified `--enable-bulk-memory-opt` bug the patch loop fixes. Hard-depends
# on rustup and dotnet already being installed (both run earlier in MODULES).
#
# Darwin differences: ~/.zshrc for the emsdk line; wasmtime's installer wires
# ~/.zshrc itself (its detect_profile picks .zshrc for a zsh $SHELL); and
# emsdk's own tooling needs Python >= 3.10 where the Command Line Tools ship
# 3.9.6 — hit on the first run ("emsdk requires python 3.10 or above"). It
# gets Homebrew's python, named explicitly through EMSDK_PYTHON rather than
# left to PATH order. Not pyenv's: that build is replaced on every Python
# upgrade and runs later in MODULES anyway.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1

require_cmd rustup "rustup not found — run the rust module first (see TOOLCHAIN-macos.md)"
require_cmd dotnet "dotnet not found — run the dotnet module first (see TOOLCHAIN-macos.md)"

log "Rust wasm targets"
rustup target add wasm32-wasip1 wasm32-unknown-unknown wasm32-unknown-emscripten

log "wasm-pack"
cargo install wasm-pack

log "Emscripten SDK"
brew_ensure python
EMSDK_PYTHON="$(brew --prefix)/bin/python3"
export EMSDK_PYTHON
if [[ ! -d "$HOME/emsdk" ]]; then
	git clone https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
fi
(
	cd "$HOME/emsdk"
	git pull
	./emsdk install latest
	./emsdk activate latest
)
append_zshrc_once "# Emscripten SDK" <<'EOF2'

# Emscripten SDK
source "$HOME/emsdk/emsdk_env.sh" > /dev/null
EOF2
source "$HOME/emsdk/emsdk_env.sh" > /dev/null

log "wasmtime"
curl https://wasmtime.dev/install.sh -sSf | bash
export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"

log ".NET wasm-tools workload"
dotnet workload install wasm-tools

log "Patching bundled wasm-opt in every installed Emscripten Sdk pack (see scripts/update-wasm.sh)"
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
emcc --version | head -1
wasmtime --version
dotnet workload list
