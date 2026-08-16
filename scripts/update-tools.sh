#!/usr/bin/env bash
# Updates the remaining standalone tools from TOOLCHAIN.md's Full Update
# Pass: GitHub CLI, PowerShell, Mono, Chromium, posh-git-sh. Not one of the
# six language stacks you asked for individually, but skipping it would
# leave the orchestrator short of the doc's full pass — drop this module
# from update-toolchain.sh's MODULES list if you'd rather run it separately.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

log "GitHub CLI"
GH_LATEST=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
GH_CURRENT=$(gh --version 2>/dev/null | head -1 | awk '{print $3}' || true)
if [[ "$GH_CURRENT" == "$GH_LATEST" ]]; then
	echo "gh already at $GH_CURRENT — skipping"
else
	ARCH=$(arch_amd64_arm64)
	TMP=$(mktemp -d)
	wget -q -P "$TMP" "https://github.com/cli/cli/releases/download/v${GH_LATEST}/gh_${GH_LATEST}_linux_${ARCH}.tar.gz"
	tar -xzf "$TMP/gh_${GH_LATEST}_linux_${ARCH}.tar.gz" -C "$TMP"
	sudo install "$TMP/gh_${GH_LATEST}_linux_${ARCH}/bin/gh" /usr/local/bin/gh
	rm -rf "$TMP"
fi

log "PowerShell"
PS_LATEST=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
PS_CURRENT=$(pwsh --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$PS_CURRENT" == "$PS_LATEST" ]]; then
	echo "pwsh already at $PS_CURRENT — skipping"
else
	ARCH=$(arch_x64_arm64)
	TMP=$(mktemp -d)
	wget -q -P "$TMP" "https://github.com/PowerShell/PowerShell/releases/download/v${PS_LATEST}/powershell-${PS_LATEST}-linux-${ARCH}.tar.gz"
	sudo mkdir -p /opt/microsoft/powershell/7
	sudo tar -xzf "$TMP/powershell-${PS_LATEST}-linux-${ARCH}.tar.gz" -C /opt/microsoft/powershell/7
	sudo chmod +x /opt/microsoft/powershell/7/pwsh
	sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
	rm -rf "$TMP"
fi

log "Mono"
sudo dnf install -y mono-complete

log "Chromium (Playwright MCP browser)"
sudo dnf install -y chromium

log "posh-git-sh"
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh

# The download above is a replay-safe overwrite, but the ~/.bashrc wiring
# that actually activates it (source + cd() override) is a one-time bootstrap
# — add it if missing. Must land BEFORE the SDKMAN block: SDKMAN's own
# installer requires its block to stay the last thing in ~/.bashrc, so this
# is spliced in above it rather than appended at the end.
POSH_MARKER="# posh-git-sh — only active inside ~/code/**"
if ! grep -qF "$POSH_MARKER" "$HOME/.bashrc" 2>/dev/null; then
	log "Wiring posh-git-sh into ~/.bashrc"
	POSH_BLOCK=$(
		cat <<'EOF'

# posh-git-sh — only active inside ~/code/**
source ~/.posh-git-sh

_update_prompt() {
    case "$PWD" in
        $HOME/code/*)
            PROMPT_COMMAND='__posh_git_ps1 "\u@\h:\w " "\\\$ ";'
            ;;
        *)
            PROMPT_COMMAND=''
            PS1='\u@\h:\w\$ '
            ;;
    esac
}

cd() {
    builtin cd "$@" || return
    _update_prompt
}

_update_prompt
EOF
	)
	SDKMAN_LINE=$(grep -nF "MUST BE AT THE END OF THE FILE FOR SDKMAN" "$HOME/.bashrc" 2>/dev/null | head -1 | cut -d: -f1 || true)
	if [[ -n "$SDKMAN_LINE" ]]; then
		TMP_BASHRC=$(mktemp)
		head -n $((SDKMAN_LINE - 1)) "$HOME/.bashrc" >"$TMP_BASHRC"
		printf '%s\n' "$POSH_BLOCK" >>"$TMP_BASHRC"
		tail -n +"$SDKMAN_LINE" "$HOME/.bashrc" >>"$TMP_BASHRC"
		mv "$TMP_BASHRC" "$HOME/.bashrc"
	else
		printf '%s\n' "$POSH_BLOCK" >>"$HOME/.bashrc"
	fi
fi

gh --version
pwsh --version
mono --version
chromium-browser --version
