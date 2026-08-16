#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# postCreateCommand: wires up git identity and SSH-based commit/tag signing
# (no GPG) from whichever key the forwarded SSH agent is holding. Mirrors
# ssh/GITHUB-SSH-SIGNING-SETUP.md's one-key-every-device design -- the
# container never holds a private key file, only the live forwarded agent
# socket (see devcontainer.json's SSH_AUTH_SOCK bind mount), so rotating or
# revoking the key on the host applies here with zero container changes.
#
# GIT_USER_NAME/GIT_USER_EMAIL come from devcontainer.json's remoteEnv,
# forwarded from the host. /home/vscode is a persisted volume, so this is a
# no-op on subsequent container starts once already configured -- but
# re-running it is safe and picks up a rotated key immediately.
# ---------------------------------------------------------------------------
set -uo pipefail

if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK:-/nonexistent}" ]; then
  cat <<'EOF'

  !! No SSH agent socket was forwarded into this container.

  This means:
    - git push/pull over SSH will fail
    - commit signing will fail

  Fix, on your HOST (not in this container):
    1. Make sure an ssh-agent is running and has your GitHub key loaded:
         ssh-add -l
       If that errors or shows nothing, run:
         eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_github
       (Bitwarden agent bridge: see ssh/GITHUB-SSH-SIGNING-SETUP.md Part 2.)
    2. Rebuild/reopen the devcontainer so it re-detects your agent.

  If you're on native Windows (not WSL2), open this devcontainer from a
  WSL2 window instead -- Windows named-pipe agents can't be bind-mounted
  the way this container expects.

EOF
  exit 0
fi

KEY="$(ssh-add -L 2>/dev/null | head -1)"
if [ -z "$KEY" ]; then
  echo "configure-git-ssh-signing: agent socket is forwarded, but no keys are loaded on the host -- run 'ssh-add ~/.ssh/id_ed25519_github' there, then reopen/rebuild the container."
  exit 0
fi

git config --global gpg.format ssh
git config --global user.signingkey "$KEY"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

mkdir -p ~/.ssh
chmod 700 ~/.ssh

EMAIL="$(git config --global user.email 2>/dev/null || true)"
if [ -n "$EMAIL" ]; then
  echo "$EMAIL $KEY" > ~/.ssh/allowed_signers
  git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
fi

# Non-interactive known_hosts entry so `ssh -T git@github.com` (verification step)
# doesn't hang on ssh-askpass, which this headless container doesn't have.
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
sort -u -o ~/.ssh/known_hosts ~/.ssh/known_hosts 2>/dev/null || true

echo "configure-git-ssh-signing: signing configured with $(echo "$KEY" | awk '{print $NF}')"
