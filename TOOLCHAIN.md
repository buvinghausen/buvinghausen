# toolchain.md — WSL2 Polyglot Dev Environment

**Machine:** Microsoft Surface Snapdragon (aarch64)
**OS:** Windows 11 + WSL2 (Fedora, aarch64)
**Shell:** bash

All languages, compilers, and build tools live in WSL2. Windows is the display layer only. The polyglot toolchain never escapes WSL2.

> **Architecture note:** All install scripts auto-detect architecture at runtime — arm64 (Snapdragon) and amd64 (x86_64) are both supported without modification.

> **Editorial note:** the Snapdragon has been genuinely great silicon for this setup — no complaints on perf or battery running a full polyglot WSL2 toolchain.

> **Distro note:** The `dnf` dependency block is the only Fedora-specific section. For other distros substitute `apt`, `pacman`, etc. for the same package list. Everything else is distro-independent.

---

## Base Dependencies

```bash
sudo dnf update -y
sudo dnf install -y curl wget git gcc gcc-c++ make openssl-devel zlib-devel \
  bzip2 bzip2-devel readline-devel sqlite sqlite-devel xz xz-devel \
  libffi-devel tk-devel libuuid-devel patch gawk
```

---

## Node.js

Install fnm (fast node manager) and Node.js Krypton LTS (24.x):

```bash
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install --lts
fnm use lts-latest
fnm default lts-latest
```

Update npm to latest:

```bash
npm install -g npm@latest
```

**Updating Node.js:**

```bash
fnm install --lts && fnm default lts-latest
```

---

## TypeScript

Install the Go-native compiler (7.x) rather than the JavaScript-based compiler. The Go compiler delivers significantly faster type-checking on large codebases:

```bash
npm install -g typescript@latest
```

> **Note:** TypeScript 7.0 hit GA on 2026-07-08 — `latest` now resolves to the Go-native compiler directly. The old `@rc` pin used during the prerelease period is retired: npm's `rc` dist-tag is frozen on the stale `7.0.1-rc` since nobody publishes to it post-GA, so keeping that pin would silently install *behind* stable rather than ahead of it. If a future major briefly ships a next-gen compiler under `@rc`/`@next` again, re-pin deliberately and drop it the same way once it GAs.

**Updating TypeScript:**

```bash
npm install -g typescript@latest
```

---

## Go

Auto-detects architecture at install time:

```bash
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz
sudo tar -C /usr/local -xzf ${GO_VERSION}.linux-${ARCH}.tar.gz
rm ${GO_VERSION}.linux-${ARCH}.tar.gz

cat >> ~/.bashrc << 'EOF'

# Go
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

source ~/.bashrc
go version
```

Install gopls (language server) and Delve (debugger) for JetBrains/GoLand:

```bash
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest
```

**Updating Go:** Remove the old installation first, then re-run the install block above:

```bash
sudo rm -rf /usr/local/go
```

**GoLand config:**
- Settings → Go → GOROOT → `\\wsl.localhost\FedoraLinux-44\usr\local\go`
- **Delve (debugger):** GoLand bundles a `linux/amd64` `dlv` that fails on arm64 with `Exec format error`. There is no UI setting to override the path — replace the bundled binary after every GoLand update:

```powershell
# Run from PowerShell (or copy via Explorer)
Copy-Item "\\wsl.localhost\FedoraLinux-44\home\buvy\go\bin\dlv" "C:\Program Files\JetBrains\GoLand\plugins\go-plugin\lib\dlv\linux\dlv" -Force
```

---

## Java / Kotlin (SDKMAN)

Install SDKMAN:

```bash
curl -s "https://get.sdkman.io" | bash

cat >> ~/.bashrc << 'EOF'

# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
EOF

source ~/.bashrc
```

Install latest LTS Java (Temurin) and Kotlin:

```bash
sdk install java
sdk install kotlin
```

> **Note:** `sdk install java` with no version specified installs the latest LTS Temurin release automatically — no version pinning required.

**Updating Java / Kotlin:**

```bash
sdk update && sdk upgrade
```

**IntelliJ config:** Settings → Build Tools → Gradle → Gradle JVM → `~/.sdkman/candidates/java/current`

---

## Gradle

```bash
sdk install gradle
```

> **Note:** For project work, prefer the Gradle wrapper (`./gradlew`) over the global install — it pins the Gradle version per project and is what IntelliJ uses when connecting via Gateway. The global install is for bootstrapping and one-off use outside a project context. Kotlin DSL (`build.gradle.kts`) is preferred over Groovy DSL.

**Updating Gradle:**

```bash
sdk update && sdk upgrade
```

---

## Python

Install pyenv dependencies (Fedora — substitute package manager for other distros):

```bash
sudo dnf install -y make gcc zlib-devel bzip2 bzip2-devel readline-devel \
  sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel gawk
```

Install pyenv:

```bash
curl https://pyenv.run | bash

cat >> ~/.bashrc << 'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# GIL enabled by default (yt-dlp and other GIL-dependent tools need it).
# Flip to free-threaded for testing: export PYTHON_GIL=0
EOF

source ~/.bashrc
pyenv update
```

Install latest stable Python (standard + free-threaded builds), global defaults to the standard build:

```bash
PYTHON_LATEST=$(pyenv latest 3)
pyenv install ${PYTHON_LATEST}
pyenv install ${PYTHON_LATEST}t
pyenv global ${PYTHON_LATEST}
```

Verify:

```bash
python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
```

> **Note:** The `t` suffix is the free-threaded build. Standard (GIL-enabled) is the current global default since some tools (yt-dlp) don't tolerate the GIL disabled. To test something against free-threading: `pyenv shell ${PYTHON_LATEST}t && export PYTHON_GIL=0` for that shell, or `pyenv local ${PYTHON_LATEST}t` to pin a project directory to it. Revert to free-threaded-by-default globally with `pyenv global ${PYTHON_LATEST}t` and restoring `export PYTHON_GIL=0` in `~/.bashrc`.

> **Updating Python:** `pyenv update` first to get new versions, then re-run the install block. `pyenv latest 3` always resolves the current stable release — when 3.15 ships stable it will naturally pick that up.

```bash
pyenv update
PYTHON_LATEST=$(pyenv latest 3)
pyenv install ${PYTHON_LATEST}
pyenv install ${PYTHON_LATEST}t
pyenv global ${PYTHON_LATEST}t
```

---

## Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

cat >> ~/.bashrc << 'EOF'

# Rust
source "$HOME/.cargo/env"
EOF

source ~/.bashrc

# Essential components
rustup component add rust-analyzer clippy rustfmt

# Cargo tools
cargo install cargo-watch cargo-edit
curl -LsSf https://get.nexte.st/latest/linux-arm | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

Verify:

```bash
rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
```

> **Note:** `cargo-nextest` installs from nextest's own prebuilt `aarch64-unknown-linux-gnu` binary (`get.nexte.st/latest/linux-arm`), not `cargo install` — building it from source takes 15+ minutes on Snapdragon (dozens of transitive crates, `--locked` release profile) versus seconds for the tarball. Substitute `linux-arm-musl` in the URL for a fully static binary with no glibc dependency, or `linux-x64`/`linux-x64-musl` on amd64. `cargo-watch`/`cargo-edit` don't ship prebuilt binaries this way, so those stay on `cargo install`.

**Updating Rust:**

```bash
rustup update
curl -LsSf https://get.nexte.st/latest/linux-arm | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

**RustRover/IntelliJ config:** Settings → Rust → Toolchain location → `~/.cargo/bin`

---

## .NET

Install via the official dotnet-install script (non-admin, auto-detects arm64):

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS

cat >> ~/.bashrc << 'EOF'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF

source ~/.bashrc
dotnet --version
dotnet --list-sdks
```

> **Note:** `--channel LTS` always resolves the latest LTS SDK patch release transparently — no version pinning required. arm64 is auto-detected. The package manager version is intentionally avoided to ensure `dotnet update` picks up patch releases (10.0.100 → 10.0.301+) without distro feed lag.

**Updating .NET:**

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS
```

---

## Older .NET Runtimes (multi-target test execution)

The `--channel LTS` SDK install above only brings the latest LTS shared runtime (currently 10.0.x) into `$DOTNET_ROOT/shared`. Multi-targeted projects (e.g. `net10.0;net9.0;net8.0`) still *compile* fine for the older TFMs, but `dotnet test -f net9.0` / `net8.0` fails at launch with `NETSDK1067`/`applaunch failed` because the matching `Microsoft.NETCore.App` shared framework isn't installed — only the SDK's own runtime is. SDKs and runtimes coexist side by side, so install the older runtimes directly:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime dotnet
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 8.0 --runtime dotnet
dotnet --list-runtimes
```

> **Note:** `--runtime dotnet` installs just the `Microsoft.NETCore.App` shared runtime (no SDK, no ASP.NET Core runtime) — the smallest footprint that lets `dotnet test`/`dotnet run` execute an already-built net9.0/net8.0 app. Repeat per channel as repos add/retire TFMs; .NET 8 and 9 both end support 2026-11-10, at which point this section can drop to whatever channels are still in support.
>
> Verified against `SequentialGuid.Tests` (`tests/unit/SequentialGuid.Tests`) — before installing, `dotnet test -f net9.0`/`net8.0` reported "Zero tests ran" with the framework-not-found error; after installing 9.0.17 and 8.0.28, both ran clean (net9.0: 6295 passed; net8.0: 6293 passed).

**Updating older runtimes:** re-run the install line for each channel you have installed — same auto-resolving-over-pinned convention as the LTS SDK.

> **Bare `dotnet test` (no `-f`) always fails on a repo that multi-targets net472, even for projects that don't touch net472 themselves.** `dotnet test`'s MTP orchestrator enumerates every TFM in every project up front and aborts the whole run with `Unhandled exception: ... Ensure you have a runnable project type. A runnable project should target a runnable TFM ... The current OutputType is 'Exe'.` the instant it hits a net472 leg — net472 isn't launchable through the `dotnet` muxer on Linux, full stop. This isn't fixed by `--runtime dotnet` installs above; it's a different failure mode (orchestrator launch, not missing shared framework). **Always pass `-f <tfm>`** to scope the run to one modern TFM at a time, e.g. `dotnet test -f net10.0` — that runs every project in the repo for that one TFM cleanly. `-f net472` does **not** work either (same error, confirmed) — net472 has to go through Mono directly, see below.

---

## Mono (legacy .NET Framework test execution)

.NET Framework's CLR doesn't run natively on Linux, but multi-targeted libraries here still ship `net472`/`net462` test legs. Mono can host and execute the built test exe directly — including xUnit v3's Microsoft.Testing.Platform (MTP) test exe, which was the open question worth verifying before documenting this:

```bash
sudo dnf install -y mono-complete
mono --version
```

`dotnet test` (with or without `-f net472`) cannot launch a net472 test leg on Linux — confirmed, same `Unhandled exception: ... runnable TFM` error as the bare-`dotnet-test` case above. The only path that works is to **build** with the SDK, then **run the exe directly under Mono**, bypassing `dotnet test`'s orchestrator entirely:

```bash
dotnet build tests/unit/SequentialGuid.Tests/SequentialGuid.Tests.csproj -f net472
mono tests/unit/SequentialGuid.Tests/bin/Debug/net472/SequentialGuid.Tests.exe
```

> **Verified, not assumed:** ran the actual `SequentialGuid.Tests` net472 build (`tests/unit/SequentialGuid.Tests`) under Mono 6.14.1. The MTP runner self-identified as `64-bit Mono 6.14.1` and reported **6207 passed, 0 failed** — the same exe, same MTP host, that runs on real .NET Framework on Windows. No build-only fallback needed; this is a real execution receipt, not a guess.
>
> **One-command repo wrapper:** since neither bare `dotnet test` nor `dotnet test -f net472` can run the full matrix, multi-targeted repos get a repo-local `test.sh` at the root that loops `dotnet test -f <tfm>` over the modern TFMs, then `dotnet build -f net472` + `mono <exe>` over the net472 test projects, with `set -euo pipefail` so any failure stops the script and propagates a non-zero exit code. See `SequentialGuid/test.sh` for the reference implementation — it's repo-specific (hardcodes that repo's TFM list and net472 project paths), so copy and adjust per repo rather than trying to generalize it.
>
> **Known risk (unconfirmed, not yet hit):** Mono's BCL isn't byte-identical to real .NET Framework (globalization/ICU, some reflection edge cases). Low risk for bit/byte-manipulation-style libraries like SequentialGuid, but if a net472 test ever passes under Mono and fails on real .NET Framework (or vice versa), suspect this first before suspecting the code.

**Updating Mono:**

```bash
sudo dnf update -y mono-complete
```

---

## .NET 11 Preview SDK — TEMPORARY (Norse discriminated unions)

> **Temporary section — remove once no longer needed.** Tracking the .NET 11 preview channel (currently preview 6, shipped 2026-07-14) to get native discriminated union support for the Norse Architecture. **Exit condition:** drop this section once .NET 11 hits GA and the team has decided whether to adopt it as a standing channel, or once the DU work no longer needs the preview bits — whichever comes first. The main [.NET](#net) section above stays pinned to `--channel LTS` regardless; this installs side by side, it does not replace that baseline.
>
> **`--quality preview` covers RC too.** `dotnet-install.sh` only has three quality values — `daily`, `preview`, `GA` — there's no separate `rc` value. Every monthly 11.0 build (previews and, later, release candidates) ships under `preview` until GA, so the install command below doesn't need to change when 11.0 reaches RC.

Install the latest preview build of the 11.0 channel into the same `$DOTNET_ROOT` — SDKs coexist side by side automatically:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview
dotnet --list-sdks
```

> **Note:** Installing a preview SDK does not change which SDK `dotnet` resolves to by default — the CLI picks the latest installed unless pinned. Add a `global.json` in the Norse Architecture repo (not globally) to pin those projects to the 11.0 preview SDK, so every other repo on this machine keeps resolving to the LTS SDK untouched:
>
> ```json
> {
>   "sdk": {
>     "version": "11.0.100-",
>     "rollForward": "latestFeature"
>   },
>   "test": {
>     "runner": "Microsoft.Testing.Platform"
>   }
> }
> ```
>
> Replace the version with whatever `dotnet --list-sdks` reports after install. `rollForward: latestFeature` follows this toolchain's auto-resolving-over-pinned convention — each new preview build (preview 5 → preview 6 → ...) lands in the same feature band, so the pin keeps working without editing `global.json` per preview drop. The `test` block makes `dotnet test` default to Microsoft.Testing.Platform instead of the legacy VSTest runner, matching xUnit v3's native MTP support.

**Updating the preview SDK:**

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview
```

> **Old preview SDKs pile up.** Each monthly build installs as a new side-by-side SDK under `$DOTNET_ROOT` rather than replacing the last one — `scripts/update-dotnet.sh` (see [Full Update Pass](#full-update-pass)) handles this by diffing `dotnet --list-sdks` before/after the install and pruning the superseded preview's SDK/runtime/pack/host artifacts once the new one is confirmed present.

---

## GitHub CLI

Auto-detects architecture at install time:

```bash
GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz
tar -xzf gh_${GH_VERSION}_linux_${ARCH}.tar.gz
sudo install gh_${GH_VERSION}_linux_${ARCH}/bin/gh /usr/local/bin/gh
rm -rf gh_${GH_VERSION}_linux_${ARCH} gh_${GH_VERSION}_linux_${ARCH}.tar.gz

gh --version
```

Authenticate:

```bash
gh auth login
# Select: GitHub.com → HTTPS → Login with a web browser
```

**Updating gh:** Re-run the install block above — `sudo install` overwrites the existing binary in place.

---

## PowerShell

Microsoft's RHEL/CentOS repos only ship x86_64 RPMs — no aarch64 packages. Install from the GitHub releases tarball instead, which ships arm64 and amd64 binaries:

```bash
PS_VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')
wget https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/powershell-${PS_VERSION}-linux-${ARCH}.tar.gz
sudo mkdir -p /opt/microsoft/powershell/7
sudo tar -xzf powershell-${PS_VERSION}-linux-${ARCH}.tar.gz -C /opt/microsoft/powershell/7
sudo chmod +x /opt/microsoft/powershell/7/pwsh
sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
rm powershell-${PS_VERSION}-linux-${ARCH}.tar.gz
pwsh --version
```

**Updating PowerShell:** Re-run the install block — `tar -xzf` overwrites in place, the symlink is stable, no `mkdir` needed again.

---

## Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash

claude --version
claude doctor
```

Authenticate:

```bash
claude
# On first launch follow the browser prompt to sign in with your Anthropic account
```

> **Note:** The native installer auto-updates in the background on the `latest` channel — no update command required. Requires a Claude Pro subscription or higher.

---

## Playwright (Claude Code browser automation)

Browser automation is Microsoft's official `@playwright/mcp` server, wired in as a Claude Code plugin (marketplace: `claude-plugins-official`). No standalone install step for the server itself — the plugin's `.mcp.json` launches it on demand via `npx`, always resolving `@latest`:

```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest"]
  }
}
```

The browser is the distro's `chromium` package, not Playwright's own bundled Chromium download:

```bash
sudo dnf install -y chromium
```

The MCP server auto-detects the system `chromium-browser` executable (`/usr/sbin/chromium-browser`) directly — no `npx playwright install chromium` step, no second Chromium download managed separately from the OS. `~/.cache/ms-playwright` stays effectively empty (a few KB of registry metadata, no browser binaries) as a result — that's expected, not a broken install.

Verify:

```bash
npx @playwright/mcp@latest --version
chromium-browser --version
```

> **Note:** Routing through the dnf-managed `chromium` package keeps the browser under the distro's own patch/security-update cadence and avoids a redundant ~300MB Playwright-managed browser download sitting alongside the system one. This is intentional, not a fallback — the MCP server resolves straight to `chromium-browser`.

**Updating:**

```bash
sudo dnf update -y chromium
# @playwright/mcp always resolves @latest via npx — no separate update command
```

---

## Docker

Docker Desktop runs on the Windows host, not inside WSL2 — there is no install step here. The CLI and socket are injected into the distro via WSL integration, which is opt-in per-distro and off by default for non-default distros like Fedora.

Enable on the Windows side:

1. Docker Desktop → **Settings → Resources → WSL Integration**
2. Toggle the entry for **Fedora** under "Enable integration with additional distros"
3. **Apply & Restart**
4. From PowerShell: `wsl --shutdown`, then reopen the Fedora terminal

Verify:

```bash
docker version
docker context ls
```

> **Note:** The Windows host manages Docker Desktop purely to provide the GUI for one-off container/image/volume cleanup — no `dnf install`, no update command inside WSL, updates happen entirely through Docker Desktop on Windows. Project workloads themselves run from WSL via **Aspire** — that's the next wave of toolchain verification.

> **Verified:** Docker Desktop's WSL2 backend shares a network namespace with automatic localhost forwarding — a port published with `docker run -p` is reachable on `localhost` from *both* WSL2 and Windows simultaneously, no extra config. Confirmed by pulling and running `downloads.unstructured.io/unstructured-io/unstructured-api:latest` (`-p 8000:8000`) and curling `http://localhost:8000/healthcheck` from inside WSL — `200 OK`, `{"healthcheck":"HEALTHCHECK STATUS: EVERYTHING OK!"}`. The same URL works unchanged from Postman/browser on Windows.
>
> Day-to-day container lifecycle (start/stop/remove) is intended to go through the Docker Desktop GUI on Windows, not the WSL CLI — the CLI here is for occasional one-off verification, not routine use. One gotcha if you do run from the CLI: a bare `docker run` (no `-d`) ties the container to the foreground process and it dies (`Exited 137`) when that shell session ends; use `docker run -d` or just manage it from the GUI.
>
> `unstructured-api` itself is a parked capability, not active work yet — it extracts text chunks from unstructured documents (PDFs, Office docs, etc.) as a precursor step to running embeddings for RAG. This was just a "does the plumbing work" check.

**Updating images:**

```bash
./scripts/update-docker.sh
```

Lists every locally-pulled image (`docker images`), then re-pulls each `repository:tag` pair. Images pinned to an immutable version tag are effectively a no-op (already at that digest); floating tags (`:latest`, etc.) actually refresh. Local-only builds with no upstream repository fail their pull individually and are skipped without aborting the rest of the sweep.

> **Note — clean-slate policy, deliberate:** a container built from a tag that's since moved shows up in `docker ps -a` with a raw image ID instead of a name. The script force-removes any container in that state (`docker rm -f`, never `-v` — named *and* anonymous volumes are always left behind) and then prunes the now-unreferenced image. It does **not** try to reconstruct the container's `docker run` config (bind mounts, networks, replication topology) — that's easy to get subtly wrong, and anything worth keeping either lives in a named volume (survives regardless) or is owned by an orchestrator that already knows how to recreate its own containers correctly. Confirmed live on this machine: Aspire's Norse Architecture postgres primary/replica pair (`pg-primary-*`/`pg-replica-*`) bind-mounts ephemeral, session-specific init scripts from `/run/desktop/mnt/host/wsl/docker-desktop-bind-mounts/...` that only Aspire itself can regenerate correctly — the pair comes back on the next AppHost run, rebuilt against the fresh image, data intact via the `norse-pg-primary`/`norse-pg-replica` volumes. This is tuned for solo personal-machine use — if anyone else ever runs this against a shared box, they inherit the clean-slate trade-off, not just the script.

---

## Code Directory

All repositories live inside WSL2 at `~/code/` — never on `/mnt/c/`. Crossing the WSL2/Windows filesystem boundary via `/mnt/c/` degrades I/O performance noticeably for git operations, file watching, and builds.

Suggested layout:

```
~/code/
  ├── buvinghausen/    # personal repos
  └── norse/           # Norse Architecture
        └── Bifrost/
            ├── Svartalfheim/
            ├── Asgard/
            └── ...
```

Clone with submodules using the `--` separator to pass git flags through gh:

```bash
gh repo clone buvinghausen/Bifrost -- --recurse-submodules
```

---

## GitHub Desktop (Windows) via `\\wsl.localhost\`

For wide-support-surface OSS libraries (legacy .NET Framework targets — currently just `SequentialGuid` and `TaskTupleAwaiter`), GitHub Desktop on Windows opens the repo directly through the `\\wsl.localhost\<distro>\...` share rather than a separate Windows-side clone. This is purely a review/revert UI (eyeball diffs, uncheck hunks, discard lines) — not the commit path of record — so the network-share performance hit doesn't matter.

**Gotcha:** Windows git (bundled in GitHub Desktop) stats files through the 9P protocol, which can report a different executable bit than Linux-native git sees on the same inode. This shows up as a file marked "modified" in GitHub Desktop with zero line diff — a mode-only change (`100755` ↔ `100644`), most often hitting shell scripts like `test.sh`.

Fix per-repo:

```bash
git config core.fileMode false
```

This lives in `.git/config`, which is the same file regardless of which OS's git reads it, so it only needs setting once per repo.

> **Trade-off:** with filemode tracking off, git won't auto-detect a deliberate `chmod +x` on a new file. To stage a real permission change, either flip it back temporarily (`git config core.fileMode true`) or run `git update-index --chmod=+x path/to/file` directly — that works regardless of the `core.fileMode` setting.

---

## posh-git-sh

Git-aware prompt active only inside `~/code/**`. Outside that boundary the prompt reverts to the standard bash default.

```bash
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
```

Add to `~/.bashrc` (before SDKMAN block):

```bash
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
```

> **Note:** The prompt only activates when inside `~/code/**` AND inside a git repo — navigating to `~/code` itself without a repo won't trigger it. That's correct behavior.

**Updating posh-git-sh:**

```bash
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
```

---

## JetBrains WSL2 Tips

**Use local IDEs with a WSL Run Target** — not JetBrains Gateway. With a full suite (GoLand, RustRover, Rider, PyCharm, IntelliJ, WebStorm) Gateway doubles the servicing burden: every IDE patch requires a matching Gateway patch. Run Targets give the same WSL2 build/run/test integration from the local IDE without that overhead.

**WSL Run Target setup (per IDE, one-time):**

1. Settings → Build, Execution, Deployment → Run Targets → `+` → WSL
2. Select `FedoraLinux-44` from the distro list
3. JetBrains introspects the distro and maps toolchain paths automatically
4. In each run/debug configuration set **Run target** to the WSL entry

**GoLand specifics:**

- Settings → Go → GOROOT → `\\wsl.localhost\FedoraLinux-44\usr\local\go`
- With the WSL Run Target active, GoLand translates the UNC path correctly when invoking the toolchain — the broken-path bug (`stat /main.go: directory not found`) is a symptom of missing Run Target configuration, not a GOROOT misconfiguration

**General:**

- All `export` and init lines above are in `~/.bashrc` — JetBrains WSL introspection sources it automatically
- After initial setup run `wsl --shutdown` from PowerShell then reopen before connecting to ensure a clean environment load
- **If a run configuration produces broken paths** (e.g. `/main.go` instead of the full Linux path), delete it and recreate it from scratch — the path mapping bakes in at creation time and corruption isn't fixable by editing

---

## Verified Environment

```
Node.js   v24.18.0       (Krypton LTS)
npm       12.0.1
tsc       7.0.2          (Go-native compiler, GA since 2026-07-08 — no longer @rc)
go        1.26.5         linux/arm64
gopls     0.23.0
dlv       1.27.0
java      25.0.3         Temurin LTS
kotlin    2.4.10
gradle    9.6.1
python    3.14.5         GIL enabled (standard build; 3.14.5t available via pyenv local/shell for free-threaded testing)
rustc     1.97.1         aarch64-unknown-linux-gnu
cargo     1.97.1
nextest   0.9.140         prebuilt aarch64-unknown-linux-gnu binary, not cargo-installed
dotnet    10.0.302       (+ 9.0.18, 8.0.29 runtimes for multi-target test execution)
dotnet-11 11.0.100-preview.6.26359.118   TEMPORARY preview channel (Norse DU work) — see its own section
mono      6.14.1         legacy net472/net462 test execution
playwright-mcp 0.0.78    @playwright/mcp, via npx, no persistent install
chromium  150.0.7871.114 dnf-managed, not Playwright-downloaded
gh        2.96.0
pwsh      7.6.3
claude    2.1.183        native, linux-arm64, auto-updates enabled
posh-git-sh 1.5.1       ~/code/** only
```

*Verified on: 2026-07-17 · Surface Snapdragon · WSL2 Fedora aarch64 · full pass via `./update-toolchain.sh`*
*`playwright-mcp` / `chromium` added and verified separately: 2026-07-12*
*`docker` module (image refresh + dangling-image/stale-container cleanup) added to the update pass 2026-07-17 — not listed above since it tracks container images, not a pinned CLI version.*
*`python` default flipped from free-threaded (`t`, `PYTHON_GIL=0`) back to standard/GIL-enabled: 2026-07-19 — yt-dlp needs the GIL. Free-threaded build stays installed for opt-in testing.*

---

## Full Update Pass

Run this periodically to bring the entire toolchain current:

```bash
./update-toolchain.sh              # every module, in order
./update-toolchain.sh dotnet go    # or just the modules you want
```

`update-toolchain.sh` is the executable, replay-safe version of this pass — each `scripts/update-*.sh` module is a no-op or clean overwrite when already current, and the `Go`, `.NET`, and `docker` modules additionally remove whatever they're superseding (old `/usr/local/go`; every stale SDK/runtime/pack/manifest-band across all four .NET channels, not just the 11.0 preview one; dangling images and containers pinned to a superseded image) rather than leaving it to accumulate. Modules: `node` (npm + TypeScript), `go`, `jvm` (Java/Kotlin/Gradle), `dotnet` (LTS + 9.0/8.0 runtimes + 11.0 preview, full stale-version prune, `dotnet new`/`tool`/`workload` updates), `rust`, `python`, `tools` (gh, pwsh, Mono, Chromium, posh-git-sh), `docker` (image refresh, dangling-image prune, clean-slate container removal). Claude Code isn't a module — it auto-updates itself on the `latest` channel.

The command-by-command breakdown for each stack lives in that stack's own section above (e.g. [Go](#go), [.NET](#net)) — treat those as the reference for *what* each step does; `scripts/update-*.sh` is the reference for *exact, current* invocation. If they drift, the scripts win — update the docs above to match rather than editing this block, since this block just points at them.
