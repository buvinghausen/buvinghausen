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

**State at 2026-11-09: STOPPED** (the stop flag has been set since the benchmarks). Cutover is just `prod-start.ps1`, which will also be the first live test of the supervisor's start path.

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
- **Open:** have the supervisor hold a `PowerSetRequest` (Execution/SystemRequired) while llama-server runs. Then test: production running, lock the screen, let the display turn off, send a request from pebble, and check for Kernel-Power 506. That would also cover lid-closed and the 3-minute display timeout on battery.

## Desk automation (`desk\kbm-autoswitch.ps1`)

A per-user logon task `KbmAutoSwitch` (hidden PowerShell 5.1 window, restart on failure) with three states:

| State | Detected by | Keyboard | OLED |
|---|---|---|---|
| desk | U5226KW display present | PowerToys Win↔Ctrl swap ON (undoes the Mac's Ctrl↔Cmd swap that DDPM forwards) | normal |
| desk-dark | display gone, its Thunderbolt hub (`VID_413C&PID_5821`) still present | swap ON | black Blank screensaver, at once |
| road | neither | swap OFF | normal |

The swap is in PowerToys Keyboard Manager's `default.json`, which hot-reloads; the script writes it without a BOM. The AC display timeout is always 0. On the U5226KW in PBP, only one input's audio plays; it's pinned to Thunderbolt (the Surface).

## SSH ("diamond" topology, `ssh\`)

- In-box OpenSSH Server, keys only, `AllowUsers buvy`, default shell Windows PowerShell, port 22 from the tailnet only (100.64.0.0/10, fd7a:115c:a1e0::/48).
- Admin users' keys live in `C:\ProgramData\ssh\administrators_authorized_keys`. A password SSH session for a local admin is not elevated, so it can't write there; append keys elevated with `ssh\admin-sshd-addkey.ps1 -Name <host>`, which reads `C:\Users\buvy\ssh-keys\<host>.pub`.
- Key convention: `<hostname>.pub`, comment = hostname.
- Who reaches whom:
  - skywalker (Chromebook) is a client only and never a destination.
  - surfacespark ↔ pebble both ways.
  - xps-15-9510 is a destination only, for local x64 builds; it accepts skywalker, surfacespark and pebble.
  - work is the employer machine: RDP only, no SSH, and tagged `tag:sink` in Tailscale, so it can't start any outbound tailnet connection.
- `ssh\make-sshd-bundle.ps1 -Target <host> -Keys a,b,c` generates a self-contained elevated setup script for another Windows machine (installs the capability via dism).
- Gotchas: `Add-WindowsCapability` fails in pwsh 7 with "Class not registered" (use 5.1 or dism). sshd takes the first value it sees for each setting, so managed settings are prepended.
- Still open: the ssh-agent on the Spark (the key has a passphrase).

## Dev environment

- D: = a 500 GB ReFS Dev Drive (VHDX at `C:\DevDrive`).
- Repos in `D:\src\<org>\<repo>`.
- `gh` is logged in, with `gh auth setup-git`.
- WSL `FedoraLinux-45`, with a clean snapshot at `D:\wsl\fedora45-clean.tar`.
- wslc 3.0.3 (WSL 3.0.3) for dev containers; VS Code `dev.containers.dockerPath` = `wslc`.
- Docker Desktop 29.9.3 per-user install, started by hand only, used for Testcontainers.
- The SkunkWerkx dev container design is in `SkunkWerkx/HyperForge` `DEVCONTAINER.md`.
