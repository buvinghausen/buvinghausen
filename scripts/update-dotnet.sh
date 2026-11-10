#!/usr/bin/env bash
# Updates the .NET 11.0 SDK and the .NET 10.0 ASP.NET Core runtime (net10.0
# test execution; 8.0/9.0 dropped at their 2026-11-10 EOL, the 11.0 preview
# channel dropped at 11.0 GA).
#
# Every install below is a cheap no-op/overwrite to rerun. What isn't cheap
# is that $DOTNET_ROOT never removes anything on its own — every channel
# leaves its previous patch sitting side by side with the new one
# indefinitely. The pruning below removes whatever isn't the newest GA
# version of a tracked channel, across every location
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
# band (confirmed: preview.1 and preview.6 are separate folders), and with
# no prerelease SDK kept, none of them is needed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
# Suppresses the first-run welcome/telemetry banner and auto HTTPS dev-cert
# generation that otherwise fires the first time `dotnet` runs under each
# newly installed feature band.
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1

# dotnet-install.sh below installs unconditionally regardless of whether
# dotnet already exists, so bootstrapping is just persisting PATH for future
# shells — dotnet-install.sh itself never touches ~/.bashrc (verified: it
# only patches PATH for its own process).
if ! command -v dotnet >/dev/null 2>&1; then
	log "dotnet not found — bootstrapping (see TOOLCHAIN.md)"
	append_bashrc_once "# .NET" <<'EOF'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF
fi

log ".NET 11.0 SDK"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0

log ".NET 10.0 ASP.NET Core runtime (net10.0 test execution; --runtime aspnetcore also brings in Microsoft.NETCore.App)"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 10.0 --runtime aspnetcore

# Tracked channels. Everything else in $DOTNET_ROOT is retired: superseded
# patches, prerelease builds, and whole channels this module no longer
# installs (8.0/9.0 runtimes, the 10.0 SDK, the 11.0 previews).
SDK_CHANNELS=(11.0)
RUNTIME_CHANNELS=(10.0 11.0)

# Newest GA version per channel. Prerelease versions are never kept, and are
# filtered out before sorting rather than after: `sort -V` ranks
# 11.0.100-rc.3.26522.148 above 11.0.100, so a plain max would keep the rc and
# delete the GA build. A channel that resolves to nothing aborts the run
# instead of letting the prune below delete every version of it.
newest_ga() { # $1 = newline-separated versions, $2.. = major.minor channels
	local versions="$1" ch v
	shift
	for ch in "$@"; do
		v=$(grep -E "^${ch//./\\.}\\.[0-9]+$" <<<"$versions" | sort -V | tail -1 || true)
		[[ -n "$v" ]] || { echo "no GA $ch version installed — refusing to prune" >&2; exit 1; }
		echo "$v"
	done
}

log "Pruning everything but the newest GA SDK/runtime per tracked channel"

prune_sdks() {
	local versions keep v
	versions=$(dotnet --list-sdks | awk '{print $1}')
	keep=$(newest_ga "$versions" "${SDK_CHANNELS[@]}")
	while IFS= read -r v; do
		[[ -z "$v" ]] && continue
		grep -qxF "$v" <<<"$keep" && continue
		echo "  sdk/$v"
		rm -rf "${DOTNET_ROOT:?}/sdk/$v"
	done <<<"$versions"
}

prune_runtime() { # $1 = framework name (Microsoft.NETCore.App / Microsoft.AspNetCore.App)
	local framework="$1"
	local versions keep v pack_dir
	versions=$(dotnet --list-runtimes | awk -v fw="$framework" '$1==fw {print $2}')
	keep=$(newest_ga "$versions" "${RUNTIME_CHANNELS[@]}")
	while IFS= read -r v; do
		[[ -z "$v" ]] && continue
		grep -qxF "$v" <<<"$keep" && continue
		echo "  shared/$framework/$v + host/fxr + packs + templates"
		rm -rf "${DOTNET_ROOT:?}/shared/$framework/$v"
		rm -rf "${DOTNET_ROOT:?}/host/fxr/$v"
		for pack_dir in "$DOTNET_ROOT"/packs/*/; do
			[[ -d "${pack_dir}${v}" ]] && rm -rf "${pack_dir:?}${v}"
		done
		rm -rf "${DOTNET_ROOT:?}/templates/$v"
	done <<<"$versions"
}

prune_sdks
prune_runtime Microsoft.NETCore.App
prune_runtime Microsoft.AspNetCore.App

log "dotnet new — template updates"
dotnet new update

# The update loop below only ever touches tools that are already installed,
# so the diagnostics pair this toolchain expects gets its first install here:
# dotnet-trace (EventPipe CPU/event traces — .nettrace, convertible to
# speedscope) and dotnet-counters (live runtime counters: GC, allocation rate,
# thread pool, exceptions). Formatting needs no tool — `dotnet format` is part
# of the SDK.
log "dotnet tool — diagnostics tools (dotnet-trace, dotnet-counters)"
for id in dotnet-trace dotnet-counters; do
	if dotnet tool list --global | awk -v id="$id" 'NR > 2 && $1 == id {found = 1} END {exit !found}'; then
		echo "$id already installed"
	else
		dotnet tool install --global "$id"
	fi
done

log "dotnet tool — global tool updates"
# Per-tool instead of `--all`: dotnet-ef rode the 11.0 preview channel
# alongside the preview SDK, and `--all` hard-fails the moment any installed
# tool is newer than its latest *stable* ("requested version 10.0.10 is lower
# than existing version 11.0.0-preview.x"), killing the whole run. Policy:
# a tool whose installed version is a prerelease keeps tracking prereleases;
# everything else tracks stable. Self-healing at GA — stable outranks its own
# previews, so `--prerelease` rolls the tool onto the GA version and the next
# run's version check stops matching, dropping it back to stable-only.
TOOLS=$(dotnet tool list --global | tail -n +3 | awk 'NF {print $1, $2}')
if [[ -n "$TOOLS" ]]; then
	while read -r id version; do
		if [[ "$version" == *-* ]]; then
			dotnet tool update --global "$id" --prerelease
		else
			dotnet tool update --global "$id"
		fi
	done <<<"$TOOLS"
else
	echo "No global tools installed — skipping"
fi

log "dotnet workload — workload updates"
if dotnet workload list | awk '/^-+$/{t=1;next} /^Use `dotnet workload search`/{t=0} t && NF{f=1} END{exit !f}'; then
	dotnet workload update
else
	echo "No workloads installed — skipping"
fi

# Workload packs carry their own versions (iOS 27.0.12212-net11-rc.2, Android
# 37.2.0-rc.2.84), not the runtime version the prune above matches on, so
# they survive it. Each installed manifest and pack has a record keyed by SDK
# band under metadata/workloads/Installed{Manifests,Packs}/v1; with the
# superseded SDKs gone, clean garbage-collects every manifest and pack no
# surviving band references. (`workload install`/`update` above already run
# the same GC for the newest band; this catches the rest.)
log "dotnet workload — clean manifests/packs left by pruned SDKs"
dotnet workload clean

# Preview/rc bands only — see header note on why GA bands are skipped. Must
# run AFTER the workload GC above, never before: GC uninstalls a recorded
# manifest by deleting its sdk-manifests/<band>/<id>/<version> folder, and
# throws ("Could not find a part of the path") if that folder is already
# gone, aborting the run. What's left here is what no record owns: bands an
# SDK tarball laid down itself (the rc.2 tarball carried a preview.6 band),
# sdk-advertising, and the per-band InstalledWorkloads/history folders. No
# prerelease SDK survives the prune, so every preview/rc band is stale.
log "Pruning preview/rc manifest bands"
for d in "$DOTNET_ROOT"/sdk-manifests/* "$DOTNET_ROOT"/sdk-advertising/* \
	"$DOTNET_ROOT"/metadata/workloads/* "$DOTNET_ROOT"/metadata/workloads/*/*; do
	[[ -d "$d" ]] || continue
	name=$(basename "$d")
	if [[ "$name" == *preview.* || "$name" == *rc.* ]]; then
		echo "  ${d#"$DOTNET_ROOT"/}"
		rm -rf "${d:?}"
	fi
done

dotnet --list-sdks
dotnet --list-runtimes
dotnet-trace --version
dotnet-counters --version
