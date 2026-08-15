#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# postCreateCommand for .devcontainer/devcontainer.json.
# Fails loudly and helpfully at container startup if the host's SSH agent
# didn't get forwarded in, instead of letting someone hit a confusing
# "Permission denied (publickey)" or failed commit signature later.
#
# Save this as .devcontainer/check-ssh-agent.sh in the repo.
# ---------------------------------------------------------------------------
set -uo pipefail

echo "Checking forwarded SSH agent..."

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
    2. Rebuild/reopen the devcontainer so it re-detects your agent.

  If you're on native Windows (not WSL2), open this devcontainer from a
  WSL2 window instead -- Windows named-pipe agents can't be bind-mounted
  the way this container expects.

EOF
  exit 0   # don't hard-fail container creation, just warn loudly
fi

if ! ssh-add -l > /dev/null 2>&1; then
  echo
  echo "  !! SSH agent socket is forwarded, but no keys are loaded on the host."
  echo "     Run 'ssh-add ~/.ssh/id_ed25519_github' on your HOST, then reopen the container."
  echo
  exit 0
fi

echo "OK -- forwarded agent has $(ssh-add -l | wc -l) key(s) loaded:"
ssh-add -l
