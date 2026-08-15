#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GitHub SSH key setup — WSL / Linux
#
# Run this INSIDE WSL (e.g. your Ubuntu shell) — this generates a
# dedicated SSH keypair for GitHub, starts the agent, and wires up
# ~/.ssh/config so `git` automatically uses the right key for github.com.
#
# It will NOT overwrite an existing key at the target path.
# You will be prompted once to set a passphrase for the new key — that's
# expected and recommended.
# ---------------------------------------------------------------------------
set -euo pipefail

EMAIL="buvinghausen@users.noreply.github.com"
KEY_PATH="$HOME/.ssh/id_ed25519_github"

echo "== GitHub SSH key setup (WSL/Linux) =="

if [ -f "$KEY_PATH" ]; then
  echo "A key already exists at $KEY_PATH — skipping generation."
  echo "(Delete $KEY_PATH and $KEY_PATH.pub first if you want to regenerate.)"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH"
fi

# Start (or reuse) the ssh-agent and add the key
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$KEY_PATH"

# Make the agent start automatically in future shells (bash)
if ! grep -q "ssh-agent-github-autostart" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# ssh-agent-github-autostart
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add ~/.ssh/id_ed25519_github > /dev/null 2>&1
fi
# Needed so gpg's pinentry-curses can prompt for your passphrase in this shell
export GPG_TTY=$(tty)
EOF
  echo "Added ssh-agent + GPG_TTY autostart to ~/.bashrc"
fi

# Configure SSH to use this key specifically for github.com
CONFIG_FILE="$HOME/.ssh/config"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
if ! grep -q "^Host github.com" "$CONFIG_FILE" 2>/dev/null; then
  cat >> "$CONFIG_FILE" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $KEY_PATH
  AddKeysToAgent yes
EOF
  echo "Added a github.com entry to $CONFIG_FILE"
fi

echo
echo "== Done. Your PUBLIC key (safe to share) — paste this into =="
echo "== GitHub > Settings > SSH and GPG keys > New SSH key (type: Authentication Key) =="
echo
cat "$KEY_PATH.pub"
