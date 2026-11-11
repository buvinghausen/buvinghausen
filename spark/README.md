# surfacespark — the RTX Spark inference box

Machine record for the Surface Laptop Ultra with an NVIDIA RTX Spark (N1X): Windows 11 26H1 build 28000 (release channel, not Insider), ARM64, GPU memory split **96 / 32** (kept on purpose). Tailscale `100.114.43.34`. Its job: a dedicated `llama-server` for the Hermes agent hub on the M6 Mac mini `pebble` (`100.110.233.121`). Planned host renames, held until a reboot is convenient: surfacespark → `spark`, pebble → `build`.

The scripts in this folder are the ones actually used on the box, collected 2026-11-09 from a Claude Code session's scratchpad. Logs are git-ignored except the benchmark's `progress.log`. Admin scripts run elevated by hand:
`pwsh -NoProfile -Command "Start-Process pwsh -Verb RunAs -Wait -ArgumentList '-File','<script>'"`.

## llama-server (production)

- **Build:** llama.cpp b12110, `win-cuda-13.4-arm64`, unpacked to `C:\llama.cpp` (same layout as NVIDIA's RTX Spark playbook).
- **Model, decided 2026-11-09:** Qwen3.8-27B **Q4_K_M + DFlash** draft (`--spec-type draft-dflash`, `--spec-draft-n-max 7`, `--spec-draft-backend-sampling`) plus mmproj, with NVIDIA's sampling settings. This is NVIDIA's own default; benchmarks below.
- **Serve shape:** alias `qwen3.8-27b`, `0.0.0.0:9931`, `--api-key-file C:\llama.cpp\api-key.txt` (key lives in Bitwarden as "Spark llama-server API key"), `--ctx-size 524288 --parallel 2` (256K per slot), `--n-predict 32768`. Don't lower n-predict: thinking runaway was the main quality failure.
- **Firewall:** TCP 9931 only from pebble's tailnet IP. `llama\admin-setup.ps1` adds the rule, `llama\admin-fix.ps1` removes Windows' auto-created allow-any rules, `llama\admin-smb.ps1` adds the Hermes backup SMB share (445, pebble only).
- **Lockdown** (`llama\admin-lockdown.ps1`): `C:\llama.cpp` was Authenticated Users:Modify, which was a SYSTEM escalation path. Now owner Administrators; Admins/SYSTEM Full; Users RX. `api-key.txt` keeps its own protected ACL.
- **Supervisor** (`llama\serve-qwen38.ps1`, installed by `llama\admin-supervisor.ps1`): a SYSTEM scheduled task loop (PowerShell 5.1-compatible, no time limit, restart on failure). It watches `C:\llama.cpp\control\` (user-writable; SYSTEM never writes or deletes there, so it's junction-safe). Status goes to `logs\status.txt`, the log to `logs\supervisor.log`. It adopts an existing listener on 9931, backs off after 3 crashes, and writes `logs\server-FATAL.log` if the key file is missing.
- **No-admin controls** (`llama\prod-*.ps1`, live copies in `C:\llama.cpp`):
  - `prod-stop` creates `control\stop`, which persists across reboots.
  - `prod-start` removes that flag.
  - `prod-restart` touches `control\restart`.
  - `prod-status` shows the status file, the flag and the 9931 listener.

**State: RUNNING since 2026-11-09 06:18.** `prod-start.ps1` worked first time, which was the first live test of the supervisor's start path: listening in 6 s, healthy in about 5 s more, 66–77 tok/s on a short code prompt with thinking off.

## Benchmarks (`bench\`, 2026-11-08 → 09)

Harness `bench\bench.ps1` (prefill, generation, and 12 Python tasks × 2 with thinking on and a 16K cap). Raw results are in `bench\results\`, the timeline in `bench\progress.log`.

| | Code / prose tok/s | Quality |
|---|---|---|
| 27B Q4 + DFlash | **43.0 / 23.1** | **21/24** |
| 27B Q4, no draft | 15.6 / 15.5 | — |
| 27B Q8 + DFlash | 32.3 / 16.9 | 17/24 |
| 27B Q8, no draft | 9.4 / 9.6 | — |
| Flash-Next UD-Q3_K_XL, no draft | 36 / 36 | 19/24 |

Prefill is about the same for all (~885 / 835 / 650 tok/s at 4K / 16K / 64K). Most quality failures were the 16K thinking cap. Flash-Next with 2 slots × 128K loads, but it uses 68 GB of GPU memory and leaves the host 0.5 GB of free RAM, so it was rejected. Q8 buys nothing: memory bandwidth bounds this box, so smaller weights plus speculative decoding win. Hosting models inside WSL2 was considered and rejected: same engine, no speed gain, and it takes RAM from the 32 GB side.

Gotchas found: b12110 has no `--no-mmap`; use `--load-mode none`. Claude Code background shells get reaped under memory pressure, so start long runs detached (`Start-Process`). When waiting for a log marker, match it case-sensitively and anchored (`'^\d\d:\d\d:\d\d PHASE 1 DONE$'`), or the waiter matches its own waiting message.

## Modern Standby (important)

On this machine, **display off = Modern Standby** (Kernel-Power events 506/507), even with sleep set to never. The GPU and llama-server pause and the fans stop. Seen 2026-11-08 23:33 when SC_MONITORPOWER was used. So never power displays off while serving.
- The desk automation uses a black screensaver instead (an OLED shows black with its pixels off).
- The screensaver doesn't run over the **lock screen**, which governs itself with its own display timeout (set to never). Locking while docked-dark therefore leaves the lock screen on the OLED.
- **Guard, installed 2026-11-09** (`llama\admin-powerguard.ps1`):
  - While llama-server runs **on AC**, the supervisor holds `PowerSetRequest` SystemRequired + ExecutionRequired.
  - The reason string is "llama-server is serving inference…". It shows in an elevated `powercfg /requests` (`llama\admin-requests.ps1`, read-only); confirmed there, owned by the supervisor's `powershell.exe`. `supervisor.log` records each hold and release.
  - On battery the request is released, so a closed lid in a bag still sleeps.
  - The same script set the lock-screen display timeout `VIDEOCONLOCK` to 60 s on AC. The value lives in the registry under the Balanced scheme; `powercfg /q` hides it.
- **Open: the screen didn't turn off at the lock screen.** Locked with production running, the OLED never went dark, and there were no Kernel-Power events. `powercfg /requests` shows no DISPLAY request. Main suspect: DDPM's network KVM feeding input to the Surface while the Mac is in use, which resets the 60 s idle timer. Next step: lock, keep using the Mac, and log `GetLastInputInfo` idle time (the scratch logger for this was `idlewatch.ps1`; re-create it when needed). Once the screen does go off, run `llama\locktest.ps1` from pebble over SSH. Pass = normal tok/s and no Kernel-Power 506.

## Desk automation (`desk\kbm-autoswitch.ps1`)

A per-user task `KbmAutoSwitch`, installed by `desk\install-kbm-autoswitch.ps1` (no admin), with three states. It runs headless (`conhost.exe --headless powershell.exe …`, so there is no console window), starts at logon, and has a 5-minute watchdog trigger (IgnoreNew, so that trigger only restarts it if it has exited):

| State | Detected by | Keyboard | OLED |
|---|---|---|---|
| desk | U5226KW display present | PowerToys Win↔Ctrl swap ON (undoes the Mac's Ctrl↔Cmd swap that DDPM forwards) | normal |
| desk-dark | display gone, its Thunderbolt hub (`VID_413C&PID_5821`) still present | swap ON | black Blank screensaver, at once |
| road | neither | swap OFF | normal |

The swap is in PowerToys Keyboard Manager's `default.json`, which hot-reloads; the script writes it without a BOM. The AC display timeout is always 0. On the U5226KW in PBP, only one input's audio plays; it's pinned to Thunderbolt (the Surface). The monitor's audio switch setting must be **Manual**; on Auto it moved the audio to the Mac after a Thunderbolt reconnect (2026-11-09).

**RDP override (2026-11-09):** when the session is remote (`GetSystemMetrics(SM_REMOTESESSION)`), the swap is forced OFF whatever the state, and it comes back on when you return to the console. The broken path was Chromebook → RDP → Spark → RDP → work: the Chromebook already sends Windows keys, the swap turned Ctrl into Win, and mstsc forwarded that on to the work machine. The log line is now `state=<s> remote=<bool>`. The Mac keeps its Ctrl↔Cmd swap; moving the receiver to the Surface was rejected because DDPM on macOS is a user-space app with no virtual HID device (`hidutil list`), so per-device modifier remaps and Karabiner wouldn't apply to forwarded input.

**Headless since 2026-11-09:** the windowed version died twice (03:08 and 17:29, right after a state change) with `0xC000013A`, meaning its hidden console was closed. "Restart on failure" only covers failed starts, so it stayed dead, and at the desk the Mac keys arrived unswapped. Cause not identified. The script now logs `start pid=` and `exit pid=`. If the log shows an exit and a restart from the watchdog, the problem still happens but recovers within 5 min.

## SSH ("diamond" topology, `ssh\`)

- In-box OpenSSH Server, keys only, `AllowUsers buvy`, default shell Windows PowerShell, port 22 from the tailnet only (100.64.0.0/10, fd7a:115c:a1e0::/48).
- Admin users' keys live in `C:\ProgramData\ssh\administrators_authorized_keys`. A password SSH session for a local admin is not elevated, so it can't write there; append keys elevated with `ssh\admin-sshd-addkey.ps1 -Name <host>`, which reads `C:\Users\buvy\ssh-keys\<host>.pub`.
- Key convention: `<hostname>.pub`, comment = hostname.
- Who reaches whom:
  - skywalker (Chromebook) is a client only and never a destination.
  - surfacespark ↔ pebble both ways.
  - xps-15-9510 is a destination only, for local x64 builds; it accepts skywalker, surfacespark and pebble.
  - The work machine: RDP only, no SSH, and tagged `tag:sink` in Tailscale, so it can't start any outbound tailnet connection.
- `ssh\make-sshd-bundle.ps1 -Target <host> -Keys a,b,c` generates a self-contained elevated setup script for another Windows machine (installs the capability via dism).
- Gotchas: `Add-WindowsCapability` fails in pwsh 7 with "Class not registered" (use 5.1 or dism). sshd takes the first value it sees for each setting, so managed settings are prepended.
- Still open: the ssh-agent on the Spark (the key has a passphrase).

## Dev environment

- D: = a 500 GB ReFS Dev Drive (VHDX at `C:\DevDrive`).
- Repos in `D:\src\<org>\<repo>`.
- `gh` is logged in, with `gh auth setup-git`.
- WSL `FedoraLinux-45`, with a clean snapshot at `D:\wsl\fedora45-clean.tar`.
- wslc 3.0.5 (WSL 3.0.5) for dev containers; VS Code `dev.containers.dockerPath` = `wslc`.
- Docker Desktop 29.9.3 per-user install, started by hand only, used for Testcontainers.
- The SkunkWerkx dev container design is in `SkunkWerkx/HyperForge` `docs/devcontainer.md`.

## Visual Studio 2026 Community (`vs\.vsconfig`)

The same file installs on arm64 and on an x64 backup machine. Both MSVC toolsets are listed, so each machine gets its native compiler plus a cross-compiler for the other architecture. Install from an elevated prompt, to the default location:

```
winget install --id Microsoft.VisualStudio.Community --override "--passive --config D:\src\buvinghausen\buvinghausen\spark\vs\.vsconfig"
```

- `--override` applies only to a first install. To change an existing install, use the Installer's **Import configuration** with this file.
- `--config` installs only what is listed, plus each item's Required dependencies. Recommended items are not added.
- Deliberately left out:
  - the ASP.NET workload (it requires VS's JavaScript/TypeScript stack, so the ASP.NET pieces are listed individually instead);
  - Node.js, Python and Git for Windows;
  - the SQL tools;
  - vcpkg, Copilot and IntelliCode;
  - the .NET 8 and 9 runtimes, and every .NET Framework targeting pack. The SDK fetches reference assemblies for `net4x` builds itself.
- No VS MAUI workload and no VS Aspire tooling. Both require VS's TypeScript stack, and MAUI also brings a second JDK (`Component.OpenJDK`) and .NET 9 mobile build tools. Instead:
  - MAUI comes from the SDK. Run `dotnet workload install maui` from an elevated prompt after VS is installed, since it writes into `C:\Program Files\dotnet`. Then build from the CLI or VS Code. Android needs a JDK and the Android SDK. Java normally comes from SDKMAN with Temurin (current LTS), but SDKMAN has no Windows arm64 build, and Adoptium publishes Temurin for Windows aarch64 only up to 21 (25 is x64 only, checked 2026-11-10). So on this machine use Temurin 21 aarch64, installed from Adoptium's MSI and not from winget: `EclipseAdoptium.Temurin.21.JDK` has no arm64 installer and would install the emulated x64 JDK. Point builds at it with `-p:JavaSdkDirectory=...`. An x64 machine can use Temurin 25 once .NET for Android supports it; .NET 10 documents JDK 21. iOS and Mac Catalyst builds run on the Mac.
  - Aspire comes from its CLI and templates (NuGet). VS runs the AppHost as an ordinary project.
- Container tools are included. They run containers through Docker Desktop or Podman, not wslc. Docker Desktop is started by hand, which matches VS's default "Start the container runtime if needed: Prompt me".
- Check after installing: `"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" export --installPath "C:\Program Files\Microsoft Visual Studio\18\Community" --config out.vsconfig`. Then confirm that nothing with TypeScript or Node in its name came in as a dependency.
