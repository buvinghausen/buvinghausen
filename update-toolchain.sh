#!/usr/bin/env bash
# Orchestrates scripts/update-*.sh — the executable version of TOOLCHAIN.md's
# "Full Update Pass". Safe to rerun any time; every module is written to be
# a no-op (or a clean overwrite) when already current. See TOOLCHAIN.md for
# what each module does and why.
#
# Usage:
#   ./update-toolchain.sh              # run every module, in order
#   ./update-toolchain.sh dotnet go     # run only the named modules
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# scripts/ is the Fedora/WSL2 pass (TOOLCHAIN.md); scripts/macos/ is the
# macOS one (TOOLCHAIN-macos.md). Same module names, same policies, each
# written and verified on its own platform.
# `llm` (Ollama + the local-llm MCP server, TOOLCHAIN-macos.md) exists only
# in the macOS pass so far; it sits after `tools` (pipx) and before `docker`.
case "$(uname -s)" in
	Darwin)
		MODULE_DIR="$SCRIPT_DIR/scripts/macos"
		MODULES=(base node go jvm dotnet rust wasm android swift ruby php python tools llm docker)
		;;
	*)
		MODULE_DIR="$SCRIPT_DIR/scripts"
		MODULES=(base node go jvm dotnet rust wasm android swift ruby php python tools docker)
		;;
esac

usage() {
	echo "Usage: $0 [module ...]"
	echo "Modules: ${MODULES[*]}"
	echo "No args = run all modules in order."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

TARGETS=("$@")
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=("${MODULES[@]}")

for m in "${TARGETS[@]}"; do
	script="$MODULE_DIR/update-${m}.sh"
	if [[ ! -f "$script" ]]; then
		echo "Unknown module '$m' (no $script)" >&2
		usage
		exit 1
	fi
	echo
	echo "########## $m ##########"
	# Re-resolve `bash` each time: on macOS the base module installs Homebrew
	# bash 5 and later modules need it, but this shell would keep the hashed
	# /bin/bash 3.2 from the first lookup otherwise.
	hash -r
	bash "$script"
done

echo
echo "All requested modules updated."
