#!/usr/bin/env bash
# Updates the .NET LTS SDK, the older 9.0/8.0 ASP.NET Core runtimes, and the
# .NET 11 preview SDK, then prunes every superseded version per channel.
# Darwin twin of scripts/update-dotnet.sh — the header there explains the
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
	log "dotnet not found — bootstrapping (see TOOLCHAIN-macos.md)"
	append_zshrc_once "# .NET" <<'EOF2'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF2
fi

log ".NET LTS SDK"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS

log ".NET 9.0 / 8.0 ASP.NET Core runtimes (multi-target test execution; --runtime aspnetcore also brings in Microsoft.NETCore.App)"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime aspnetcore
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 8.0 --runtime aspnetcore

log ".NET 11 preview SDK"
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview

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

prune_runtime() { # $1 = framework name, $2 = grep -E pattern
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

log "dotnet tool — diagnostics tools (dotnet-trace, dotnet-counters)"
for id in dotnet-trace dotnet-counters; do
	if dotnet tool list --global | awk -v id="$id" 'NR > 2 && $1 == id {found = 1} END {exit !found}'; then
		echo "$id already installed"
	else
		dotnet tool install --global "$id"
	fi
done

log "dotnet tool — global tool updates"
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

# The mobile workloads the Hyper repos' C# legs build with: ios and maccatalyst
# (the iOS simulator app and the Mac Catalyst process in ci.yml's Apple job)
# and android (the CoreCLR and NativeAOT APKs). Installed against the newest
# SDK on the box, the 11.0 preview: this runs from scripts/macos, outside any
# repo's global.json, the same band wasm-tools lands in (update-wasm.sh). The
# android workload's build tasks want a JDK and an Android SDK at build time,
# not install time; the jvm and android modules supply them.
log "dotnet workload — ios / maccatalyst / android"
dotnet workload install ios maccatalyst android

log "dotnet workload — workload updates"
if dotnet workload list | awk '/^-+$/{t=1;next} /^Use `dotnet workload search`/{t=0} t && NF{f=1} END{exit !f}'; then
	dotnet workload update
else
	echo "No workloads installed — skipping"
fi

dotnet --list-sdks
dotnet --list-runtimes
dotnet-trace --version
dotnet-counters --version

# The ios / maccatalyst workloads build only against the Xcode they were made
# for (major.minor, RecommendedXcodeVersion in the newest Microsoft.iOS.Sdk
# pack). With any other one selected the build stops ("requires Xcode 27.0.
# The current version of Xcode is 27.1"). The fix is that Xcode installed beside the selected one and handed to the
# C# Apple builds through DEVELOPER_DIR. Installing Xcode needs an Apple ID,
# so like Xcode's own selection this fails loudly instead.
log "Xcode for the ios / maccatalyst workloads"
IOS_PACK=$(find "$DOTNET_ROOT/packs" -maxdepth 1 -name 'Microsoft.iOS.Sdk.net*' | sort -V | tail -1)
IOS_PACK=$(find "$IOS_PACK" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
WANT_XCODE=$(grep -rhoE '<RecommendedXcodeVersion[^>]*>[^<]+' "$IOS_PACK/targets" | sed 's/.*>//' | sort -u | tail -1)
[[ -n "$WANT_XCODE" ]] || { echo "No RecommendedXcodeVersion in $IOS_PACK" >&2; exit 1; }
WANT_MM=$(grep -oE '^[0-9]+\.[0-9]+' <<<"$WANT_XCODE")
MATCH=""
for app in /Applications/Xcode*.app; do
	[[ -d "$app" ]] || continue
	v=$(defaults read "$app/Contents/version.plist" CFBundleShortVersionString 2>/dev/null || true)
	echo "  $app: $v"
	[[ "$(grep -oE '^[0-9]+\.[0-9]+' <<<"$v")" == "$WANT_MM" || "$v" == "$WANT_MM" ]] && MATCH="$app"
done
if [[ -z "$MATCH" ]]; then
	cat >&2 <<MSG
The ios / maccatalyst workloads ($(basename "$(dirname "$IOS_PACK")") $(basename "$IOS_PACK")) need Xcode $WANT_MM, and no /Applications/Xcode*.app is that version.
One-time, by hand (Apple ID): download Xcode $WANT_MM from https://developer.apple.com/download/all/, then
  xip --expand Xcode_$WANT_MM.xip && mv Xcode.app /Applications/Xcode-$WANT_MM.app
  DEVELOPER_DIR=/Applications/Xcode-$WANT_MM.app/Contents/Developer xcodebuild -runFirstLaunch
and keep the selected Xcode as it is. C# Apple builds then run with
  DEVELOPER_DIR=/Applications/Xcode-$WANT_MM.app/Contents/Developer
MSG
	exit 1
fi
echo "Xcode $WANT_MM for the workloads: $MATCH (DEVELOPER_DIR=$MATCH/Contents/Developer for C# Apple builds)"
