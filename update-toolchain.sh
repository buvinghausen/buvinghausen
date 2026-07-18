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

MODULES=(node go jvm dotnet rust python tools docker)

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
	script="$SCRIPT_DIR/scripts/update-${m}.sh"
	if [[ ! -f "$script" ]]; then
		echo "Unknown module '$m' (no $script)" >&2
		usage
		exit 1
	fi
	echo
	echo "########## $m ##########"
	bash "$script"
done

echo
echo "All requested modules updated."
