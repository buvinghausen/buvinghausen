#!/usr/bin/env bash
# Updates the .NET 11.0 SDK and the .NET 10.0 ASP.NET Core runtime, then
# prunes everything but the newest GA version per tracked channel.
# Darwin twin of scripts/update-dotnet.sh - the header there explains the
# prune policy (what is keyed by exact version and safe to remove, why GA
# manifest bands are left alone); dotnet-install.sh resolves osx-arm64 itself
# and lays out $DOTNET_ROOT identically, so the whole body carries over. The
# one difference is ~/.zshrc as the rc file.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1

if ! command -v dotnet >/dev/null 2>&1; then
	log "dotnet not found - bootstrapping (see TOOLCHAIN-macos.md)"
	append_zshrc_once "# .NET" <<'EOF2'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF2
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
		[[ -n "$v" ]] || { echo "no GA $ch version installed - refusing to prune" >&2; exit 1; }
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

log "dotnet new - template updates"
dotnet new update

log "dotnet tool - diagnostics tools (dotnet-trace, dotnet-counters)"
for id in dotnet-trace dotnet-counters; do
	if dotnet tool list --global | awk -v id="$id" 'NR > 2 && $1 == id {found = 1} END {exit !found}'; then
		echo "$id already installed"
	else
		dotnet tool install --global "$id"
	fi
done

log "dotnet tool - global tool updates"
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
	echo "No global tools installed - skipping"
fi

# The mobile workloads the Hyper repos' C# legs build with: ios and maccatalyst
# (the iOS simulator app and the Mac Catalyst process in ci.yml's Apple job)
# and android (the CoreCLR and NativeAOT APKs). Installed against the newest
# SDK on the box, 11.0: this runs from scripts/macos, outside any
# repo's global.json, the same band wasm-tools lands in (update-wasm.sh). The
# android workload's build tasks want a JDK and an Android SDK at build time,
# not install time; the jvm and android modules supply them.
#
# Only from the SDK's own feature band. With no manifest published for that
# band, `workload install` silently falls back to an older band's manifests
# left on disk; on 11.0.100 GA day that meant the 10.0.100 band's Mono-based
# .NET 10 workloads (ios 26.0.11017, android 36.1.2), which this toolchain
# doesn't support. So each workload is installed only once NuGet carries its
# manifest for the current band, and uninstalled if it's present without one.
# Feature band = major.minor.N00 of the SDK version (11.0.203 -> 11.0.200).
SDK_BAND=$(dotnet --version | sed -E 's/^([0-9]+\.[0-9]+)\.([0-9]+)[0-9]{2}.*/\1.\200/')
log "dotnet workload - ios / maccatalyst / android (SDK band $SDK_BAND)"
for id in ios maccatalyst android; do
	if curl -fs -o /dev/null "https://api.nuget.org/v3-flatcontainer/microsoft.net.sdk.$id.manifest-$SDK_BAND/index.json"; then
		dotnet workload install "$id"
	elif dotnet workload list | awk -v id="$id" '$1 == id {found = 1} END {exit !found}'; then
		echo "$id: no $SDK_BAND manifest on NuGet yet - uninstalling the older band's workload"
		dotnet workload uninstall "$id"
	else
		echo "$id: no $SDK_BAND manifest on NuGet yet - skipping"
	fi
done

log "dotnet workload - workload updates"
if dotnet workload list | awk '/^-+$/{t=1;next} /^Use `dotnet workload search`/{t=0} t && NF{f=1} END{exit !f}'; then
	dotnet workload update
else
	echo "No workloads installed - skipping"
fi

# Workload packs carry their own versions (iOS 27.0.12212-net11-rc.2, Android
# 37.2.0-rc.2.84), not the runtime version the prune above matches on, so
# they survive it. Each installed manifest and pack has a record keyed by SDK
# band under metadata/workloads/Installed{Manifests,Packs}/v1; with the
# superseded SDKs gone, clean garbage-collects every manifest and pack no
# surviving band references. (`workload install`/`update` above already run
# the same GC for the newest band; this catches the rest.)
log "dotnet workload - clean manifests/packs left by pruned SDKs"
dotnet workload clean

# Preview/rc bands only - see header note on why GA bands are skipped. Must
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
