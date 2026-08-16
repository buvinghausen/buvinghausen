#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# postCreateCommand: installs the bash-native posh-git-sh prompt (see
# TOOLCHAIN.md's posh-git-sh section) and sources it unconditionally in
# .bashrc. TOOLCHAIN.md scopes activation to ~/code/** on the host, where
# $HOME also holds ordinary non-repo directories (Documents, Downloads,
# etc.); in this container $HOME is just tool caches plus the one workspace,
# so that scoping has nothing to protect against and is left out here.
# /home/vscode is a persisted volume, so this is a no-op after the first run.
# ---------------------------------------------------------------------------
set -uo pipefail

if [ ! -f ~/.posh-git-sh ]; then
  curl -fsSL -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
fi

if ! grep -q '.posh-git-sh' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc << 'EOF'

# posh-git-sh
source ~/.posh-git-sh
PROMPT_COMMAND='__posh_git_ps1 "\u@\h:\w " "\\\$ ";'
EOF
fi

echo "configure-posh-git-sh: done"
