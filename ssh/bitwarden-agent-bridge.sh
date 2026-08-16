#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Foreground relay: WSL unix socket -> npiperelay -> Bitwarden's Windows named
# pipe SSH agent (\\.\pipe\openssh-ssh-agent). Supervised by the
# bitwarden-agent-bridge.service systemd --user unit — do not source this or
# run it standalone in a shell.
#
# Prereqs on Windows:
#   - Bitwarden Desktop must be the standalone installer, NOT the Microsoft
#     Store/Appx build. The Store build runs sandboxed and can go
#     unresponsive on the pipe, which hangs ssh-add indefinitely.
#   - Bitwarden Desktop > Settings > SSH Agent > Enable SSH agent
#   - Windows service "OpenSSH Authentication Agent" set to Disabled
#     (Bitwarden needs to own the named pipe)
#
# npiperelay's -p (poll) flag is deliberately not used here: it polls
# indefinitely when the pipe is busy, which blocks stdin and prevents -ei
# from ever firing — another way to wedge the agent. If the agent gets
# wedged (ssh-add hangs), the fix is on the Windows side: toggle Bitwarden's
# SSH agent setting off/on, or restart Bitwarden Desktop.
# ---------------------------------------------------------------------------
set -euo pipefail

SOCK="$HOME/.ssh/agent.sock"
NPIPERELAY="$HOME/.local/bin/npiperelay.exe"
PIPE="//./pipe/openssh-ssh-agent"

rm -f "$SOCK"
exec socat UNIX-LISTEN:"$SOCK",fork EXEC:"$NPIPERELAY -ei -s $PIPE",nofork
