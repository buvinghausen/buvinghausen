#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Run this ON EXACTLY ONE HOST — this generates the single SSH keypair that
# will be used for BOTH GitHub auth and commit signing, everywhere: every
# OS, every device, every devcontainer. Do not re-run this on other hosts —
# see GITHUB-SSH-SIGNING-SETUP.md for how to securely copy the resulting
# private key to your other machines instead of generating separate ones.
# ---------------------------------------------------------------------------
set -euo pipefail

EMAIL="buvinghausen@users.noreply.github.com"
KEY_PATH="$HOME/.ssh/id_ed25519_github"

echo "== Generating the ONE shared GitHub SSH key (auth + signing) =="

if [ -f "$KEY_PATH" ]; then
  echo "A key already exists at $KEY_PATH."
  echo "If this is meant to be the master copy, stop and don't overwrite it."
  exit 1
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_PATH"

echo
echo "== Public key — you'll register this TWICE on GitHub =="
echo "== (https://github.com/settings/keys -> New SSH key) =="
echo "==   1) Key type: Authentication Key"
echo "==   2) Key type: Signing Key         <- add it a second time with this type"
echo
cat "$KEY_PATH.pub"
echo
echo "== Next: securely copy $KEY_PATH (the PRIVATE key, no .pub) to your other"
echo "== hosts, then run configure-host.sh/.ps1 there. See the setup guide for"
echo "== safe ways to move it (do NOT paste it into Slack/email/plain cloud storage)."
