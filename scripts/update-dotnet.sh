#!/usr/bin/env bash
# Updates the .NET LTS SDK, the older 9.0/8.0 shared runtimes (multi-target
# test execution), and the .NET 11 preview SDK (Norse discriminated unions —
# TEMPORARY, see TOOLCHAIN.md). `--quality preview` covers every monthly
# 11.0 build through GA — there is no separate "rc" quality value in
# dotnet-install.sh, so this does not need to change when 11.0 reaches RC.
#
# Every install below is a cheap no-op/overwrite to rerun. What isn't cheap
# is that $DOTNET_ROOT never removes anything on its own — every channel
# (LTS, 8.0, 9.0, 11.0 preview) leaves its previous patch/build sitting
# side by side with the new one indefinitely. The pruning below removes
# whatever isn't the current max version per channel, across every location
# .NET actually scatters a version's files into: sdk/, shared/*/, host/fxr/,
# packs/*/, templates/. Those five are always keyed by the exact, full
# version string (SDK version or runtime version, 1:1, verified by
# inspecting $DOTNET_ROOT directly) — safe to remove by exact match.
#
# sdk-manifests/, sdk-advertising/, and metadata/workloads/ are NOT included
# in that sweep except for preview/rc-qualified bands. Verified by
# inspection: GA patches within the same feature band share ONE manifest
# folder (10.0.301 and 10.0.302 both resolve to sdk-manifests/10.0.100) —
# removing it because an old patch was superseded would break the SURVIVING
# SDK, which still needs it. There's no reliable way to derive the GA
# manifest-band string from the SDK version (it's a Microsoft-assigned
# workload-set band, not a simple truncation), so GA bands are left alone
# entirely — they're small (KBs, not the hundreds of MB sdk/shared/packs
# cost). Preview/rc bands are different: each preview number is its own
# band (confirmed: preview.1 and preview.6 are separate folders), so a
# superseded preview band is always safe to remove once no surviving SDK
# still needs it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
# Suppresses the first-run welcome/telemetry banner and auto HTTPS dev-cert
# generation that otherwise fires the first time `dotnet` runs under each
# newly installed feature band — which, for the 11.0 preview channel, is
# every single month.
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1
require_cmd dotnet "dotnet not found — run the .NET install steps in TOOLCHAIN.md first"

log ".NET LTS SDK"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS

log ".NET 9.0 / 8.0 shared runtimes (multi-target test execution)"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime dotnet
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 8.0 --runtime dotnet

log ".NET 11 preview SDK"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview

# LTS's own major.minor isn't hardcoded — derived from whatever --channel
# LTS just installed, so this keeps working unmodified whenever LTS rolls
# to a new major version. At this point in the script every non-11.x SDK
# present is necessarily the LTS one (11.0 hasn't been touched yet).
NEW_LTS_SDK=$(dotnet --list-sdks | awk '{print $1}' | grep -v '^11\.' | sort -V | tail -1)
LTS_MAJOR_MINOR=$(grep -oE '^[0-9]+\.[0-9]+' <<<"$NEW_LTS_SDK")

log "Pruning stale SDKs/runtimes (keeping the current max per channel)"

prune_sdks() { # $1 = grep -E pattern matching this channel's SDKs
	local pattern="$1"
	local versions keep v
	versions=$(dotnet --list-sdks | awk '{print $1}' | grep -E "$pattern" || true)
	[[ -z "$versions" ]] && return
	keep=$(sort -V <<<"$versions" | tail -1)
	while IFS= read -r v; do
		[[ "$v" == "$keep" ]] && continue
		echo "  sdk/$v (kept $keep)"
		rm -rf "${DOTNET_ROOT:?}/sdk/$v"
	done <<<"$versions"
}

prune_runtime() { # $1 = framework name (Microsoft.NETCore.App / Microsoft.AspNetCore.App), $2 = grep -E pattern
	local framework="$1" pattern="$2"
	local versions keep v pack_dir
	versions=$(dotnet --list-runtimes | awk -v fw="$framework" '$1==fw {print $2}' | grep -E "$pattern" || true)
	[[ -z "$versions" ]] && return
	keep=$(sort -V <<<"$versions" | tail -1)
	while IFS= read -r v; do
		[[ "$v" == "$keep" ]] && continue
		echo "  shared/$framework/$v + host/fxr + packs + templates (kept $keep)"
		rm -rf "${DOTNET_ROOT:?}/shared/$framework/$v"
		rm -rf "${DOTNET_ROOT:?}/host/fxr/$v"
		for pack_dir in "$DOTNET_ROOT"/packs/*/; do
			[[ -d "${pack_dir}${v}" ]] && rm -rf "${pack_dir:?}${v}"
		done
		rm -rf "${DOTNET_ROOT:?}/templates/$v"
	done <<<"$versions"
}

prune_sdks "^${LTS_MAJOR_MINOR//./\\.}\\."
prune_sdks '^11\.0\.'
prune_runtime Microsoft.NETCore.App "^${LTS_MAJOR_MINOR//./\\.}\\."
prune_runtime Microsoft.NETCore.App '^8\.0\.'
prune_runtime Microsoft.NETCore.App '^9\.0\.'
prune_runtime Microsoft.NETCore.App '^11\.0\.'
prune_runtime Microsoft.AspNetCore.App "^${LTS_MAJOR_MINOR//./\\.}\\."
prune_runtime Microsoft.AspNetCore.App '^11\.0\.'

# Preview/rc feature bands only — see header note on why GA bands are skipped.
log "Pruning stale preview/rc manifest bands"
NEW_11_SDK=$(dotnet --list-sdks | awk '{print $1}' | grep -E '^11\.0\.' | sort -V | tail -1 || true)
SURVIVING_BAND=$(grep -oE '(preview|rc)\.[0-9]+' <<<"$NEW_11_SDK" || true)
if [[ -n "$SURVIVING_BAND" ]]; then
	for base_dir in "$DOTNET_ROOT/sdk-manifests" "$DOTNET_ROOT/sdk-advertising"; do
		[[ -d "$base_dir" ]] || continue
		for d in "$base_dir"/*; do
			[[ -d "$d" ]] || continue
			name=$(basename "$d")
			if [[ "$name" == *preview.* || "$name" == *rc.* ]] && [[ "$name" != *"$SURVIVING_BAND"* ]]; then
				echo "  $(basename "$base_dir")/$name"
				rm -rf "${d:?}"
			fi
		done
	done
	for d in "$DOTNET_ROOT"/metadata/workloads/*/*; do
		[[ -d "$d" ]] || continue
		name=$(basename "$d")
		if [[ "$name" == *preview.* || "$name" == *rc.* ]] && [[ "$name" != *"$SURVIVING_BAND"* ]]; then
			echo "  metadata/workloads/.../$name"
			rm -rf "${d:?}"
		fi
	done
fi

log "dotnet new — template updates"
dotnet new update

log "dotnet tool — global tool updates"
if [[ -n "$(dotnet tool list --global | tail -n +3)" ]]; then
	dotnet tool update --global --all
else
	echo "No global tools installed — skipping"
fi

log "dotnet workload — workload updates"
if dotnet workload list | awk '/^-+$/{t=1;next} /^Use `dotnet workload search`/{t=0} t && NF{f=1} END{exit !f}'; then
	dotnet workload update
else
	echo "No workloads installed — skipping"
fi

dotnet --list-sdks
dotnet --list-runtimes
