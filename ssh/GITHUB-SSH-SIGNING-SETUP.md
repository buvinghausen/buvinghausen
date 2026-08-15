# GitHub SSH auth + SSH-based commit signing — one key, every device, every devcontainer

Architecture: **one SSH keypair**, used for both GitHub authentication and commit signing (no GPG at all). It lives only on your physical hosts (never inside a container image or a teammate's container). Devcontainers pick it up via SSH agent forwarding — your own devcontainers use *your* key, and if you share this devcontainer config with teammates, *their* container forwards *their* own key automatically.

GPG email used below: `buvinghausen@users.noreply.github.com`.

---

## Part 1 — Generate the key ONCE

Pick exactly one host to be the origin (WSL is a good default). Run:

```bash
chmod +x generate-key-ONCE.sh
./generate-key-ONCE.sh
```

(Windows-origin alternative: `generate-key-ONCE.ps1`.)

Do **not** re-run this on your other machines — that would create a second, different key, defeating the "one identity" goal. Every other host gets a *copy* of this same private key (Part 2).

### Register the public key on GitHub — twice

Go to https://github.com/settings/keys → **New SSH key**, and add the printed public key **twice**, with a different **Key type** each time:

1. Key type: `Authentication Key`
2. Key type: `Signing Key`

Same key text both times — GitHub tracks the two capabilities separately.

---

## Part 2 — Get the private key onto your other hosts

You need `~/.ssh/id_ed25519_github` (no `.pub`) present on every host that will use it directly (not devcontainers — see Part 4, they don't need their own copy).

**Same physical machine, WSL + Windows (your case):** don't copy it at all — just point one side at the other's file. From WSL, set `IdentityFile /mnt/c/Users/<you>/.ssh/id_ed25519_github` in `~/.ssh/config` instead of generating/copying a second file.

**Separate physical devices:** move the private key file over a channel you trust — a password manager that stores files/secrets (1Password, Bitwarden), `scp` over a connection you already trust, or a USB drive. Do not paste it into Slack, email, or a plaintext cloud-drive file. Delete any transient copy once it's in place. Set permissions after copying:
```bash
chmod 600 ~/.ssh/id_ed25519_github
```

**If you use 1Password or Bitwarden's SSH agent:** you can skip having a private key file on a host at all — the agent holds the key and answers every SSH/git signature request itself. Neither agent bridges into WSL natively (checked both projects' issue trackers: 1Password's WSL support is still an open feature request, and Bitwarden's Windows agent only exposes the `\\.\pipe\openssh-ssh-agent` named pipe, which WSL can't reach directly — the "just works everywhere" framing was the plan, not what either vendor ships).

For Bitwarden specifically, this repo has the bridge built: **`ssh/bitwarden-agent-bridge.sh`** relays that named pipe into a WSL Unix socket via `npiperelay` + `socat`, supervised by **`ssh/bitwarden-agent-bridge.service`** as a `systemd --user` unit (WSL2's systemd must be enabled — it is by default on recent WSL). A shell-rc-spawned relay was tried first and rejected: every new terminal raced to claim the socket, and a dead relay failed silently. A single supervised service avoids both.

Prereqs on Windows:
- Bitwarden Desktop must be the **standalone installer**, not the Microsoft Store/Appx build — the Store build runs sandboxed and can go unresponsive on the pipe, which hangs `ssh-add` indefinitely with no error.
- Bitwarden Desktop → Settings → SSH Agent → enable it
- Set the Windows **"OpenSSH Authentication Agent"** service to *Disabled* (Bitwarden needs to own the named pipe)

Then in WSL:
```bash
sudo dnf install -y socat   # apt/pacman/etc. on other distros
# download npiperelay.exe (amd64) from https://github.com/jstarks/npiperelay/releases,
# verify against the release checksum, and place it at ~/.local/bin/npiperelay.exe

mkdir -p ~/.local/bin ~/.config/systemd/user
cp ssh/bitwarden-agent-bridge.sh ~/.local/bin/bitwarden-agent-bridge.sh
chmod +x ~/.local/bin/bitwarden-agent-bridge.sh
cp ssh/bitwarden-agent-bridge.service ~/.config/systemd/user/bitwarden-agent-bridge.service
systemctl --user daemon-reload
systemctl --user enable --now bitwarden-agent-bridge.service
```
Then add to `~/.bashrc` (or `.zshrc`):
```bash
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
```
Open a new shell and confirm with `ssh-add -l` — it should list the key Bitwarden is holding. If `ssh-add -l` hangs, see the gotchas documented at the top of `bitwarden-agent-bridge.sh` (Store-build sandboxing, npiperelay's `-p` flag) before assuming the setup is wrong.

A host set up this way only ever has `~/.ssh/id_ed25519_github.pub` on disk — no private key file, and `configure-host.sh` doesn't apply (it requires a private key file present and exits without one). Point `~/.ssh/config`'s `IdentityFile` at the `.pub` file instead; OpenSSH matches it against whatever the agent is holding:
```
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github.pub
```

---

For hosts with the private key file on disk, once it's in place, run the configure script there:

```bash
chmod +x configure-host.sh
./configure-host.sh
```
(Windows: `configure-host.ps1`)

This sets up the agent, `~/.ssh/config`, and git:
```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519_github.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```
Note `user.signingkey` here is a **path to the public key file**, not a key ID (that's a GPG-ism, not needed for SSH signing).

---

## Part 3 — Verify

```bash
ssh -T git@github.com
git commit --allow-empty -m "test: verify signed commits"
git log --show-signature -1
```
Push it and check the commit on GitHub for the green **Verified** badge.

---

## Part 4 — Devcontainers: making forwarding automatic for anyone

Two attached files handle this:

- **`devcontainer-ssh-forwarding.json`** — merge its `mounts`, `remoteEnv`, and `postCreateCommand` fields into your real `.devcontainer/devcontainer.json`.
- **`check-ssh-agent.sh`** — save as `.devcontainer/check-ssh-agent.sh`. Runs on container start and prints clear, actionable instructions if no agent got forwarded, instead of a confusing git failure later.

The mechanism: `${localEnv:SSH_AUTH_SOCK}` is resolved on **whoever's host** opens the container, so it forwards *their* agent — not a hardcoded one. As long as a person has a normal `ssh-agent` (or 1Password/Bitwarden agent, or macOS Keychain agent) running with a key loaded, this "just works" with zero manual setup on their end. Nobody's private key ever touches the container image or filesystem — only the live agent socket is forwarded, so revoking/rotating on the host instantly applies inside every container without touching the container at all.

**This also means:** since you dropped GPG, there's only one thing to forward (the SSH agent) instead of two (SSH + gpg-agent). GPG-agent forwarding across Windows/WSL/Mac needed extra relay tooling and was fragile; SSH agent forwarding via `SSH_AUTH_SOCK` is native and works the same everywhere your Docker backend is Linux-based — which includes WSL2 (Docker Desktop's default backend on Windows), so even Windows contributors are covered as long as Docker Desktop is running in its normal WSL2 mode.

**Caveat:** this can only forward a key that already exists and is loaded on the host. There's no way to *force* someone to have set up SSH auth to GitHub in the first place — `check-ssh-agent.sh` just makes the failure obvious and actionable instead of silent.

### Optional: verifying teammates' signatures inside the container

`git log --show-signature` needs an "allowed signers" file mapping email → public key. For your own solo use, `configure-host.sh` already sets this up. For a shared team devcontainer, you can check a repo-level file (e.g. `.devcontainer/allowed_signers`) listing every trusted contributor:
```
alice@users.noreply.github.com ssh-ed25519 AAAA...
bob@users.noreply.github.com   ssh-ed25519 AAAA...
```
then add to `postCreateCommand`:
```bash
git config --global gpg.ssh.allowedSignersFile /workspaces/<repo>/.devcontainer/allowed_signers
```
This is purely cosmetic/local (`git log` output) — it has no effect on GitHub's own Verified badge, which checks against keys registered on each person's GitHub account regardless.

---

## Part 5 — Rotating / revoking the key

Because there's exactly one keypair, this is the entire process:

1. Generate a new keypair on your origin host (reuse `generate-key-ONCE.sh` after removing the old key file, or use a new filename).
2. Add the new public key to GitHub twice (Authentication + Signing), as in Part 1.
3. Delete the **old** key from https://github.com/settings/keys (both entries) — this instantly revokes it everywhere, including any devcontainer, since containers never held a copy in the first place.
4. Copy the new private key to your other hosts (Part 2) and re-run `configure-host`.
5. Devcontainers need zero changes — next time one is opened, it forwards whatever agent/key is currently loaded on that host.

Nothing to do on a per-container or per-teammate basis beyond step 4 for hosts *you* control. Teammates rotate their own keys independently, on their own schedule, with zero coordination with you — that's the benefit of everyone forwarding their own agent instead of sharing one identity across a team.
