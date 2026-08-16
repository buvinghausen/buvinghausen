#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run this on EVERY host (WSL, Linux, macOS) that already has the shared
# private key at ~/.ssh/id_ed25519_github (either because you generated it
# here with generate-key-ONCE.sh, or because you securely copied it over
# from the host that did). It wires up the agent, SSH config, and git's
# SSH-based commit signing — no GPG involved.
# ---------------------------------------------------------------------------
set -euo pipefail

EMAIL="buvinghausen@users.noreply.github.com"
NAME="Buvy"
KEY_PATH="$HOME/.ssh/id_ed25519_github"

if [ ! -f "$KEY_PATH" ]; then
  echo "No key found at $KEY_PATH — copy the private key here first (see the setup guide), then re-run."
  exit 1
fi
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub" 2>/dev/null || true

echo "== Starting ssh-agent and loading the key =="
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$KEY_PATH"

if ! grep -q "ssh-agent-github-autostart" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# ssh-agent-github-autostart
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add ~/.ssh/id_ed25519_github > /dev/null 2>&1
fi
EOF
  echo "Added ssh-agent autostart to ~/.bashrc"
fi

echo "== SSH config for github.com =="
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
  echo "Added github.com entry to $CONFIG_FILE"
fi

echo "== git config: SSH-based signing (no GPG) =="
git config --global user.name "$NAME"
git config --global user.email "$EMAIL"
git config --global gpg.format ssh
git config --global user.signingkey "$KEY_PATH.pub"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

echo "== Local signature verification (optional, cosmetic) =="
ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
LINE="$EMAIL $(cat "$KEY_PATH.pub")"
touch "$ALLOWED_SIGNERS"
if ! grep -qF "$EMAIL" "$ALLOWED_SIGNERS" 2>/dev/null; then
  echo "$LINE" >> "$ALLOWED_SIGNERS"
fi
git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

echo
echo "== Done. Test with: =="
echo "  ssh -T git@github.com"
echo "  git commit --allow-empty -m test && git log --show-signature -1"
