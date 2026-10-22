#!/usr/bin/env bash
# Updates the remaining standalone tools: GitHub CLI, actionlint (+ ShellCheck/
# pyflakes), PowerShell, Mono, the cross-language perf tooling, posh-git-sh.
# Darwin twin of scripts/update-tools.sh.
#
# Darwin differences, each explained inline: Homebrew for what Fedora takes
# from dnf or a Linux release tarball (gh, actionlint, shellcheck, mono,
# hyperfine); pyflakes through pipx; pwsh's osx-arm64 tarball under
# ~/.local/opt; Google Chrome from its cask for Playwright (Homebrew's
# chromium cask is disabled for Apple Silicon); no perf/valgrind/
# heaptrack (none exist for Apple Silicon — the macOS column is the bundled
# sample/leaks/heap/malloc_history plus samply and hyperfine); posh-git-sh on
# its zsh precmd hook, scoped to ~/Developer/**.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh
ensure_local_dirs

log "GitHub CLI / actionlint / ShellCheck / hyperfine / Mono (Homebrew)"
brew_ensure gh actionlint shellcheck hyperfine mono

# The Hyper repos' release guard (.github/scripts/release_guard.py and its
# tests) reads exports with llvm-nm / llvm-readobj and builds cross-format
# fixtures with clang and lld-link: CI's `apt-get install llvm clang lld`.
# Homebrew's llvm is keg-only (macOS provides clang), so its bin/ stays off
# PATH and the CLT's clang and libclang keep winning everywhere else; put it
# first only for the release-guard run (see TOOLCHAIN-macos.md). lld is not
# keg-only: ld.lld / lld-link / ld64.lld / wasm-ld land in Homebrew's bin,
# none of which shadows the CLT's ld.
log "LLVM / lld (Homebrew — release-guard checks)"
brew_ensure llvm lld

# actionlint shells out to shellcheck (above) and pyflakes for `run:` bodies
# and `python` steps, silently skipping those checks when either is missing.
# No pyflakes formula exists; pipx gives it its own venv on Homebrew's python
# — outside the pyenv build that update-python.sh replaces on every upgrade,
# which is the same reason Fedora takes it from dnf rather than pip.
log "pyflakes (pipx — actionlint integration)"
brew_ensure pipx
if pipx list --short 2>/dev/null | grep '^pyflakes ' >/dev/null; then
	pipx upgrade pyflakes
else
	pipx install pyflakes
fi

# PowerShell: the GitHub release tarball, same shape as Fedora, under
# ~/.local/opt instead of /opt (no sudo in this pass).
log "PowerShell"
PS_LATEST=$(github_latest_release PowerShell/PowerShell)
PS_CURRENT=$(pwsh --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$PS_CURRENT" == "$PS_LATEST" ]]; then
	echo "pwsh already at $PS_CURRENT — skipping"
else
	ARCH=$(arch_x64_arm64)
	PS_HOME="$LOCAL_OPT/microsoft/powershell/7"
	TMP=$(mktemp -d)
	curl -fsSL -o "$TMP/powershell-${PS_LATEST}-osx-${ARCH}.tar.gz" "https://github.com/PowerShell/PowerShell/releases/download/v${PS_LATEST}/powershell-${PS_LATEST}-osx-${ARCH}.tar.gz"
	rm -rf "$PS_HOME"
	mkdir -p "$PS_HOME"
	tar -xzf "$TMP/powershell-${PS_LATEST}-osx-${ARCH}.tar.gz" -C "$PS_HOME"
	chmod +x "$PS_HOME/pwsh"
	ln -sf "$PS_HOME/pwsh" "$LOCAL_BIN/pwsh"
	rm -rf "$TMP"
fi

log "posh-git-sh"
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh

# One-time ~/.zshrc wiring (the download above is a replay-safe overwrite).
# zsh has no PROMPT_COMMAND; posh-git-sh's README gives the precmd hook form.
# Spliced in above SDKMAN's block, which its installer requires to stay last.
POSH_MARKER="# posh-git-sh — only active inside ~/Developer/**"
if ! grep -qF "$POSH_MARKER" "$HOME/.zshrc" 2>/dev/null; then
	log "Wiring posh-git-sh into ~/.zshrc"
	POSH_BLOCK=$(
		cat <<'EOF2'

# posh-git-sh — only active inside ~/Developer/**
source ~/.posh-git-sh

precmd() {
    case "$PWD" in
        $HOME/Developer/*)
            __posh_git_ps1 '%n@%m:%~ ' '$ '
            ;;
        *)
            PS1='%n@%m:%~$ '
            ;;
    esac
}
EOF2
	)
	SDKMAN_LINE=$(grep -nF "MUST BE AT THE END OF THE FILE FOR SDKMAN" "$HOME/.zshrc" 2>/dev/null | head -1 | cut -d: -f1 || true)
	if [[ -n "$SDKMAN_LINE" ]]; then
		TMP_ZSHRC=$(mktemp)
		head -n $((SDKMAN_LINE - 1)) "$HOME/.zshrc" >"$TMP_ZSHRC"
		printf '%s\n' "$POSH_BLOCK" >>"$TMP_ZSHRC"
		tail -n +"$SDKMAN_LINE" "$HOME/.zshrc" >>"$TMP_ZSHRC"
		mv "$TMP_ZSHRC" "$HOME/.zshrc"
	else
		printf '%s\n' "$POSH_BLOCK" >>"$HOME/.zshrc"
	fi
fi

# Playwright MCP — the same `playwright` plugin as Fedora (claude-plugins-
# official), whose .mcp.json launches `npx @playwright/mcp@latest` with no
# arguments; the server's default browser on macOS is Google Chrome under
# /Applications. The Fedora doc's system-Chromium reasoning (one copy, the
# OS/vendor update cadence, no second ~300 MB Playwright-managed download)
# lands on the google-chrome cask here: Homebrew's chromium cask is disabled
# (`fails_gatekeeper_check`, unsigned snapshots), and Chrome is notarized.
# Chrome's own updater only runs while it is open, which on a build box it
# rarely is: it sat at 155 after 156 shipped, and wasm-pack's chromedriver
# (always the newest) then refused it ("only supports Chrome version 156").
# `brew upgrade` skips auto_updates casks unless told --greedy, so it is. The
# plugin install is replay-safe (exit 0, "already installed").
#
# Chrome has to be opened ONCE from the GUI before it will run from the
# command line. Until then every launch — headless or via Playwright, with or
# without --user-data-dir, sandboxed or not — dies with
# `FATAL:base/path_service.cc Failed to get the path for 1001` (exit 133).
# The GUI launch creates ~/Library/Application Support/Google/Chrome and its
# `First Run` sentinel, and from then on headless and Playwright launches
# work (Brave, also Chromium 155, had been opened before and never showed
# it). The sentinel is the check; the fix is manual, so this fails loudly.
log "Google Chrome (Homebrew cask — Playwright's default browser)"
brew list --cask google-chrome >/dev/null 2>&1 || brew install --cask google-chrome
brew upgrade --cask --greedy google-chrome
CHROME_FIRST_RUN="$HOME/Library/Application Support/Google/Chrome/First Run"
if [[ ! -f "$CHROME_FIRST_RUN" ]]; then
	cat >&2 <<'EOF'
Google Chrome has never been opened on this box — Playwright can't launch it
until it has (see TOOLCHAIN-macos.md, Playwright). Once, by hand:
  open -a "Google Chrome"      # get past the first-run screens, then quit it
then rerun: ./update-toolchain.sh tools
EOF
	exit 1
fi

log "Playwright MCP plugin (claude-plugins-official)"
claude plugin install playwright@claude-plugins-official

gh --version | head -1
actionlint --version | head -1
shellcheck --version | grep version:
pyflakes --version
pwsh --version
mono --version | head -1
hyperfine --version
"$(brew --prefix llvm)/bin/llvm-nm" --version | sed -n 2p
"$(brew --prefix llvm)/bin/llvm-readobj" --version | sed -n 2p
lld-link --version
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
claude plugin list | grep -A3 'playwright@' | grep -E 'playwright@|Status'
# The macOS-bundled process tools that stand in for perf/valgrind/heaptrack.
for t in sample leaks heap malloc_history vmmap; do printf '%-15s %s\n' "$t" "$(command -v "$t")"; done
