# surfacespark - the RTX Spark inference box

Machine record for the Surface Laptop Ultra with an NVIDIA RTX Spark (N1X): Windows 11 26H1 build 28000 (release channel, not Insider), ARM64, GPU memory split **96 / 32** (kept on purpose). Tailscale `100.114.43.34`. Its job: a dedicated `llama-server` for the Hermes agent hub on the M6 Mac mini `pebble` (`100.110.233.121`). Planned host renames, held until a reboot is convenient: surfacespark → `spark`, pebble → `build`.

The scripts in this folder are the ones actually used on the box, collected 2026-11-09 from a Claude Code session's scratchpad. Logs are git-ignored except the benchmark's `progress.log`. Admin scripts run elevated by hand:
`pwsh -NoProfile -Command "Start-Process pwsh -Verb RunAs -Wait -ArgumentList '-File','<script>'"`.

## llama-server (production)

- **Build:** llama.cpp b12110, `win-cuda-13.4-arm64`, unpacked to `C:\llama.cpp` (same layout as NVIDIA's RTX Spark playbook).
- **Model, since 2026-11-13:** Qwen3.8 **Flash-Next UD-IQ4_XS + MTP** draft on NVIDIA's RTX Spark recipe:
  - **Weights:** the 3-shard unsloth upload at commit `38bb39e` plus its BF16 mmproj.
  - **Flags:** `-lzm on -fa on -ngl auto`, batch 2048 / ubatch 512, `--spec-type draft-mtp --spec-draft-n-max 3` with ggml-org's Q8_0 MTP draft, and `--cache-ram 2048` (see phase 4).
  - **Files:** copied into the admin-only `C:\llama.cpp\models` and SHA-256 verified by `llama\admin-flip-flashnext.ps1`; `D:\models` is user-writable, so the SYSTEM supervisor never loads from there.
  - **Why:** chosen on bench phases 3-4 (below): 53 / 38 vs 43 / 23 tok/s, and 20/24 vs 16/24 quality at the 32K cap.
  - **Fallback:** the previous model, Qwen3.8-27B Q4_K_M + DFlash (decided 2026-11-09), stays in `models\`. To revert, restore `C:\llama.cpp\serve-qwen38.ps1.bak-20261113-0206` and restart the supervisor task.
- **Serve shape:** alias `qwen3.8-flash-next` (was `qwen3.8-27b`), `0.0.0.0:9931`, `--api-key-file C:\llama.cpp\api-key.txt` (key lives in Bitwarden as "Spark llama-server API key"), `--ctx-size 524288 --parallel 2` (256K per slot), `--n-predict 32768`. Don't lower n-predict: thinking runaway was the main quality failure.
- **Firewall:** TCP 9931 only from pebble's tailnet IP. `llama\admin-setup.ps1` adds the rule, `llama\admin-fix.ps1` removes Windows' auto-created allow-any rules, `llama\admin-smb.ps1` adds the Hermes backup SMB share (445, pebble only).
- **Lockdown** (`llama\admin-lockdown.ps1`): `C:\llama.cpp` was Authenticated Users:Modify, which was a SYSTEM escalation path. Now owner Administrators; Admins/SYSTEM Full; Users RX. `api-key.txt` keeps its own protected ACL.
- **Supervisor** (`llama\serve-qwen38.ps1`, installed by `llama\admin-supervisor.ps1`): a SYSTEM scheduled task loop (PowerShell 5.1-compatible, no time limit, restart on failure). It watches `C:\llama.cpp\control\` (user-writable; SYSTEM never writes or deletes there, so it's junction-safe). Status goes to `logs\status.txt`, the log to `logs\supervisor.log`. It adopts an existing listener on 9931, backs off after 3 crashes, and writes `logs\server-FATAL.log` if the key file is missing. A GPU-state watchdog (added 2026-11-12) catches what `/health` can't. After an NVIDIA driver update the server lost its GPU memory, `/health` kept returning ok, and every completion failed. Once the server is 5 min old, the supervisor checks every 60 s for two signs: total GPU memory used falling below half its healthy peak (`nvidia-smi`; per-process figures are N/A under WDDM), and `failed to allocate CUDA`/`CUDA error` in the server log. Either one on 2 checks in a row restarts the server. It deliberately sends no test completion, because that would evict an agent's cached prompt from a slot. Deploy changes with `llama\admin-supervisor-update.ps1` (elevated).
- **No-admin controls** (`llama\prod-*.ps1`, live copies in `C:\llama.cpp`):
  - `prod-stop` creates `control\stop`, which persists across reboots.
  - `prod-start` removes that flag.
  - `prod-restart` touches `control\restart`.
  - `prod-status` shows the status file, the flag and the 9931 listener.

**State: RUNNING Flash-Next since 2026-11-13 02:07** (flip plus GPU-watchdog deploy via `admin-flip-flashnext.ps1` → `admin-supervisor-update.ps1 -RestartServer`).
- `/v1/models` serves `qwen3.8-flash-next`, with 2 slots × 262144 context.
- A real completion worked: MTP accepted 6/9 drafts.
- Memory: 86.2 GB GPU, 21.8 GB host free at load.

The 27B ran from 2026-11-09 06:18 until the flip.

## Benchmarks (`bench\`, 2026-11-08 → 09)

Harness `bench\bench.ps1` (prefill, generation, and 12 Python tasks × 2 with thinking on and a 16K cap). Raw results are in `bench\results\`, the timeline in `bench\progress.log`.

| | Code / prose tok/s | Quality |
|---|---|---|
| 27B Q4 + DFlash | **43.0 / 23.1** | **21/24** |
| 27B Q4, no draft | 15.6 / 15.5 | - |
| 27B Q8 + DFlash | 32.3 / 16.9 | 17/24 |
| 27B Q8, no draft | 9.4 / 9.6 | - |
| Flash-Next UD-Q3_K_XL, no draft | 36 / 36 | 19/24 |
| Flash-Next UD-IQ4_XS + MTP n=3 (NVIDIA recipe, 2026-11-12) | **53.2 / 37.7** | 18/24 |
| *Quality at production's 32K cap (phase 4, 2026-11-12/13):* | | |
| Flash-Next UD-IQ4_XS + MTP n=3 @ 32K | (as above) | **20/24** |
| 27B Q4 + DFlash @ 32K | (as above) | 16/24 |

**Flash-Next on NVIDIA's RTX Spark recipe** (`bench\phase3.ps1`, 2026-11-12):
- **Setup:**
  - llama.cpp b12110 instead of the recipe's b11617, and driver 621.24 instead of the recipe's 617.06.
  - Weights: unsloth UD-IQ4_XS, the 3-shard upload at commit `38bb39e`, which the recipe pins for its mmproj. Main has since been re-quantized into 4 shards. The files live in `D:\models\qwen3.8-flash-next`.
  - Flags: `-lzm on`, `-ngl auto`, `-fa on`, batch 2048, the BF16 mmproj, and the ggml-org MTP Q8_0 draft with n-max 3.
- **Speed:**
  - Prefill 932 / 883 / 775 tok/s at 4K / 16K / 64K, the fastest of all runs.
  - Draft acceptance 72-81% on code and 44-49% on prose.
- **Memory:**
  - 1 × 256K: 76.5 GB GPU and 19.8 GB host free at load. `-lzm on` keeps the 87 GB of weights from spilling into host RAM; the Q3 run without it left 0.5 GB.
  - Production shape, 2 × 256K, loads at 85.6 GB GPU with 19.1 GB host free.
- **Quality 18/24.** All 6 failures hit the 16K thinking cap: iso_duration ×2, calc, csv_line, semver and palindrome. It thinks longer than the 27B.
- **Host free RAM fell steadily while the bench server ran** in phase 3, from 19.8 GB at load to 2.27 GB after 1.75 h (`logs\phase3-mem.csv`), and recovered when the server stopped. Phase 4 found the cause; see below.

**Phase 4: quality at production's real cap + the memory cause** (`bench\phase4.ps1`, `phase4-watch.ps1`, 2026-11-12 20:48 to 11-13 02:00). Quality only, with `bench.ps1 -QualityMaxTokens 32768` (production's `--n-predict`). Both models used the same args as their earlier runs.
- **Flash-Next 20/24** (16K: 18/24). Failures: calc ×2 (hit 32K), semver#1 (hit 32K, called an undefined `compare_semver`), roman#1 (40 → "XXXX"). The extra headroom rescued iso_duration ×2 and csv_line, which take 18-32K tokens.
- **27B Q4 + DFlash 16/24** (16K: 21/24). Failures: calc ×2, iso_duration#2 and semver#2 (all at 32K), plus wrong answers in lru_cache#2, csv_line#2, roman#2 (the same "XXXX") and dijkstra#2. The 16K → 32K drop is run-to-run variance at temp 1.0 on 24 samples, not a cap effect. Treat ±3 as noise.
- Both models fail calc every time (all 4 samples ran out at 32K), and both make the same roman-numeral error.
- **Verdict:** Flash-Next wins on quality at the real cap, as well as on speed and prefill. Chosen as the next production model; the flip waits for the user's go.
- **The memory cause is llama-server's prompt cache (`--cache-ram`, default 8192 MiB), not a leak, lazy mode or file cache.** `phase4-mem.csv` logs every 10 s: free, available, standby, modified, commit, GPU, bench private/working set and vmmem.
  - **Free and available fell together.** Standby (the file cache) fell with them, so it isn't cache being counted as used.
  - **Both models' private bytes grew by about 8 GB, then plateaued:**

    | Model | Private bytes, load → plateau | Plateau reached |
    |---|---|---|
    | Flash-Next | 80.5 → 88.6 GB | ~2 h |
    | 27B | 27.3 → 34.7-35.5 GB | ~1 h |

  - **The 27B doesn't use `-lzm`**, so lazy mode is ruled out.
  - **GPU stayed flat.** Free RAM recovered when each server stopped.
  - **Lowest available:** 3.56 GB (Flash-Next, 1 × 256K). The watchdog never fired.
  - **Production implication:** Flash-Next leaves ~12-19 GB of host RAM after load, against ~21 GB for the 27B. Flash-Next's production config gets `--cache-ram 2048`. With 2 agent slots, cross-conversation cache reuse is worth little.

Prefill is about the same for all (~885 / 835 / 650 tok/s at 4K / 16K / 64K). Most quality failures were the 16K thinking cap. Flash-Next with 2 slots × 128K loads, but it uses 68 GB of GPU memory and leaves the host 0.5 GB of free RAM, so it was rejected. Q8 buys nothing: memory bandwidth bounds this box, so smaller weights plus speculative decoding win. Hosting models inside WSL2 was considered and rejected: same engine, no speed gain, and it takes RAM from the 32 GB side.

Gotchas found: b12110 has no `--no-mmap`; use `--load-mode none`. Claude Code background shells get reaped under memory pressure, so start long runs detached (`Start-Process`). When waiting for a log marker, match it case-sensitively and anchored (`'^\d\d:\d\d:\d\d PHASE 1 DONE$'`), or the waiter matches its own waiting message.

## Services sweep (`services\`, 2026-11-12)

Rule: anything that might be used is **Manual** (starts on demand, off at boot); only never-used services are **Disabled**. `services\admin-services-sweep.ps1` applies it and is safe to re-run. It records each target's original start type and status in `services-baseline.json` before changing it. `admin-services-restore.ps1` puts that state back. Output goes to `services-sweep.log`.
- **Disabled:** Spooler, MapsBroker, PhoneSvc, RasMan, SstpSvc, SSDPSRV, FDResPub, fdPHost, NcdAutoSetup, lmhosts, QWAVE, InventorySvc, PcaSvc, wuqisvc, WSearch.
- **Manual:** SysMain, WSAIFabricSvc, OptionsPlusUpdaterService, DellTechHub, DellClientManagementService, WSLService, vmcompute, hns, nvagent. `wsl --status` was confirmed to start a Manual WSLService on demand.
- **Surface services stay Automatic and running:** SurfaceService (Integration), SurfaceMachineLearningService, SurfaceExperienceService and SurfaceThermalService.
  - Surface ML was briefly set to Manual by the first sweep and was reverted the same day. A Microsoft Q&A accepted answer (not official docs) says it does adaptive performance, thermal and battery tuning, and that Experience handles firmware communication and battery-health reporting. Neither should be off on a box under sustained GPU load.
  - SurfaceService was switched Auto → Manual at 12:02 on 2026-11-12. The sweep didn't do it, and the System log (event 7040) doesn't record who did. It's back on Automatic. If it flips again, look for event 7040.
- **Couldn't change:** SurfaceExperienceService and CodexSandboxService.OpenAI.Codex. Both are MSIX-packaged services (`WIN32_PACKAGED_PROCESS`, binaries under `C:\Program Files\WindowsApps`). Their service ACL lets Authenticated Users start and stop them but gives Administrators no config right, so both stay Automatic. Surface Experience is wanted running anyway. Codex can be stopped without admin (`Stop-Service CodexSandboxService.OpenAI.Codex`) but comes back at boot. Forcing it would mean taking ownership of the service's security descriptor, and an app update re-registers the service anyway, so they were left alone.
- **Kept on purpose:** sshd, Tailscale, LanmanServer (Hermes share), Remote Desktop (TermService, SessionEnv, UmRdpService; Manual by default, for RDP over Tailscale away from home), DDPM KVM, DPMService, NVIDIA, the Surface services above, Defender, XtaCache (x64 emulation), Windows Update.

**RAM trim, same day.** Goal: as much free host RAM as possible. Keep DDPM (KVM), RDP and Tailscale.
- **Dell Core Services** 1.16.67 must stay installed. It was uninstalled through its MSI (TechHub, MyDell, the update service, their two services), and the KVM kept working only until the next reboot. After that, DDPM's session components (`DDPM.Subagent`, `DDPM.Subagent.User`, `DDPM-NKVM`, the network service) no longer started and DDPM showed 0 devices. DDPM 2.4 installs Core Services itself as a bundled component (`C:\ProgramData\Dell\DDPM.Subagent\dcs-<ver>.log`). The fix was a Repair from `C:\Program Files\Dell\Dell Display and Peripheral Manager\Installer\setup.exe -runfromtemp`, which brought back the devices and the KVM. Repair also resets `DellTechHub` and `DellClientManagementService` to Automatic. Both were set back to Manual and stopped, and the KVM survived a reboot that way (2026-11-12). After the reboot only `DDPMNetworkKVMService`, `DDPM-NKVM` and the Dell Display Manager Network Service run, and host free RAM was 21.7 GB with production loaded. Core Services has to be *installed*; it doesn't have to be *running*.
- **Dell Peripheral Core** (`DPMService` + `DPM.exe`, ~170 MB) stays installed for UltraSharp and webcam firmware updates. `DPMService` is set to Manual; start it when updating firmware. The Network KVM was confirmed working with it stopped.
- **NVIDIA App overlay** was turned off in NVIDIA App → Settings → Features, saving ~500 MB. The NVIDIA App container and driver stay.
- **Windows Search UI is fully off:** `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` `DisableSearch` = 1 (DWORD), the documented "Fully disable Search UI" policy (Policy CSP Search/DisableSearch). SearchHost and its 6 WebView2 processes (~550-600 MB) no longer run, and free host RAM was 21.2 GB after it.
  - The per-user `DisableSearchBoxSuggestions` = 1 under `HKCU\Software\Policies\Microsoft\Windows\Explorer` was tried first and saved almost nothing (602 → 534 MB), because SearchHost preloads at login anyway. It is still set and harmless.
  - Restarting Explorer is enough to apply either policy; signing out would kill detached bench runs.
- **Surface app UI** (`SurfaceApp.Desktop`, ~250 MB, Microsoft.SurfaceHub package) auto-launched at every login even with its startup task disabled. It had two launch paths. Both were traced on 2026-11-12 with process-creation auditing (event 4688 with command lines, temporarily enabled):
  1. **Startup agent:** the SurfaceBroker service's `StartupAgentLauncher` module (`Services\StartupAgentLauncherDm.exe`, `LaunchAtStartup: true` in `StartupAgentLauncher.json`) runs `%LOCALAPPDATA%\Microsoft\WindowsApps\Microsoft.SurfaceHub_8wekyb3d8bbwe\SurfaceAppStartup.exe` in each signed-in session. The Settings → App execution aliases toggle only removes the *root* `WindowsApps\SurfaceAppStartup.exe`, not this per-package copy. Fix: delete the per-package file (no admin). The launcher still runs but finds no alias and launches nothing. A Surface app update may recreate it.
  2. **Background task (the real culprit):** the app's manifest registers `general`/`timer`/`systemEvent` background tasks. At logon, svchost (BrokerInfrastructure / SystemEventsBroker / DcomLaunch) COM-activates `SurfaceApp.exe --BackgroundTaskServer -Embedding`, which spawns `SurfaceApp.Desktop.exe` (3× in one second). Fix: **Settings → Apps → Installed apps → Surface → Advanced options → Background app permissions = Never.** It's per-user and survives app updates.
  - With both in place, a reboot had 343 process creations and no SurfaceApp process. Firmware, battery and CFU keep working: they run as SurfaceBroker's own components (`BatteryDm`, `CfuDm`, `WindowsUpdatesDm`, ...), not through the app. The service itself can't be set to Manual (MSIX ACL, see above) and is wanted anyway. The app still opens normally from Start.
  - Same day, Windows Update installed "Microsoft Corporation System Hardware Update (200.0.9.0)", the Surface **system manifest** (it lists which firmware and drivers apply to this model; the previous version was 200.0.7.0 on 11/8). The reboot that finished it took ~13 min, ~10.5 min of it before the OS loaded, consistent with firmware flashing.
- **App execution aliases** were mostly turned off (Settings → Apps → Advanced app settings), including `winget` and `wt`. pwsh still resolves through its per-package alias, and `wsl` through System32.

**Remote Desktop over Tailscale only** (`rdp\admin-rdp-tailscale.ps1`, 2026-11-12). RDP is enabled. All built-in Remote Desktop firewall rules (User Mode TCP/UDP, Shadow) were open to every remote address. They are now scoped to `100.64.0.0/10` and `fd7a:115c:a1e0::/48` (the tailnet). The scope is set on disabled rules too, so toggling RDP keeps it. Connect away from home by Tailscale IP or MagicDNS name.

## Modern Standby (important)

On this machine, **display off = Modern Standby** (Kernel-Power events 506/507), even with sleep set to never. The GPU and llama-server pause and the fans stop. Seen 2026-11-08 23:33 when SC_MONITORPOWER was used. So never power displays off while serving.
- The desk automation uses a black screensaver instead (an OLED shows black with its pixels off).
- The screensaver doesn't run over the **lock screen**, which governs itself with its own display timeout (set to never). Locking while docked-dark therefore leaves the lock screen on the OLED.
- **Guard, installed 2026-11-09** (`llama\admin-powerguard.ps1`):
  - While llama-server runs **on AC**, the supervisor holds `PowerSetRequest` SystemRequired + ExecutionRequired.
  - The reason string is "llama-server is serving inference...". It shows in an elevated `powercfg /requests` (`llama\admin-requests.ps1`, read-only); confirmed there, owned by the supervisor's `powershell.exe`. `supervisor.log` records each hold and release.
  - On battery the request is released, so a closed lid in a bag still sleeps.
  - The same script set the lock-screen display timeout `VIDEOCONLOCK` to 60 s on AC. The value lives in the registry under the Balanced scheme; `powercfg /q` hides it.
- **Open: the screen didn't turn off at the lock screen.** Locked with production running, the OLED never went dark, and there were no Kernel-Power events. `powercfg /requests` shows no DISPLAY request. Main suspect: DDPM's network KVM feeding input to the Surface while the Mac is in use, which resets the 60 s idle timer. Next step: lock, keep using the Mac, and log `GetLastInputInfo` idle time (the scratch logger for this was `idlewatch.ps1`; re-create it when needed). Once the screen does go off, run `llama\locktest.ps1` from pebble over SSH. Pass = normal tok/s and no Kernel-Power 506.

## Desk automation (`desk\kbm-autoswitch.ps1`)

A per-user task `KbmAutoSwitch`, installed by `desk\install-kbm-autoswitch.ps1` (no admin), with three states. It runs headless (`conhost.exe --headless powershell.exe ...`, so there is no console window), starts at logon, and has a 5-minute watchdog trigger (IgnoreNew, so that trigger only restarts it if it has exited):

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
- Gotchas: `Add-WindowsCapability` fails in pwsh 7 with "Class not registered" (use 5.1 or dism). The other DISM-module cmdlets (`Get-WindowsOptionalFeature`, `Get-AppxProvisionedPackage`, ...) are worse: they hit the same `0x80040154` and keep retrying for minutes before failing with the same error (see Windows Security below). sshd takes the first value it sees for each setting, so managed settings are prepended.
- Still open: the ssh-agent on the Spark (the key has a passphrase).

## Dev environment

- **Local account only. No Microsoft account has ever signed in to this box, and none should.** How `buvy` was created during setup (OOBE, 26H1 build 28000):
  1. Connect to the network as normal and continue until the screen asking you to sign in with or create a Microsoft account.
  2. Press Shift+F10 to open a command prompt.
  3. Run `start ms-cxh:localonly`. It opens a local-account dialog (name, password, security questions).

  Microsoft keeps closing these routes (`oobe\bypassnro` was removed in 2025), so check this one still works before the next reinstall. Checked 2026-11-10: `Get-LocalUser buvy` shows `PrincipalSource Local`, and no identities are stored under `HKCU:\Software\Microsoft\IdentityCRL`.
- **The browser is Brave.** Its profile and PWAs, including the Teams PWA needed for work, are never part of a cleanup. Edge stays installed only because Windows needs it; its Copilot policies are in the Windows Security section.
- D: = a 500 GB ReFS Dev Drive (VHDX at `C:\DevDrive`).
- Repos in `D:\src\<org>\<repo>`.
- `gh` is logged in, with `gh auth setup-git`.
- WSL `FedoraLinux-45`, with a clean snapshot at `D:\wsl\fedora45-clean.tar`.
- wslc 3.0.5 (WSL 3.0.5) for dev containers; VS Code `dev.containers.dockerPath` = `wslc`.
- Docker Desktop 29.9.3 per-user install, started by hand only, used for Testcontainers.
- NuGet, entirely on the Dev Drive, through machine-wide environment variables. These are the only setting that covers all four of NuGet's folders, and they match how HyperForge's CI steers `NUGET_PACKAGES`:
  - `NUGET_PACKAGES=D:\packages\nuget\packages`
  - `NUGET_HTTP_CACHE_PATH=D:\packages\nuget\http-cache`
  - `NUGET_SCRATCH=D:\packages\nuget\scratch`
  - `NUGET_PLUGINS_CACHE_PATH=D:\packages\nuget\plugins-cache`

  Check with `dotnet nuget locals all --list`. Known gap: `dotnet tool` installs ignore the packages path ([dotnet/sdk#15306](https://github.com/dotnet/sdk/issues/15306)).
- Rust, native `aarch64-pc-windows-msvc`, on the Dev Drive. Machine-wide `RUSTUP_HOME=D:\packages\rustup` and `CARGO_HOME=D:\packages\cargo`, with `D:\packages\cargo\bin` on the machine PATH. The user-level copies that rustup-init created were removed. When editing the machine PATH, go through the registry with `ExpandString`; `[Environment]::SetEnvironmentVariable` would flatten the `%SystemRoot%` entries.
  - Installed with the arm64 `rustup-init.exe` from static.rust-lang.org (checked against its sha256), not winget.
  - Matches the container's `20-rust.sh`: stable, minimal profile, plus clippy, rustfmt, llvm-tools, rust-src and rust-analyzer. Targets: `x86_64-pc-windows-msvc`, `wasm32-wasip1`, `wasm32-unknown-unknown` and `thumbv7em-none-eabi`.
  - The MSRV and wasm2go toolchains and the container's dev tools stay in the container.
  - For Windows builds of repos the container also builds, set `CARGO_TARGET_DIR` outside the repo so Windows and Linux artifacts don't share `target/`.
- The SkunkWerkx dev container design is in `SkunkWerkx/HyperForge` `docs/devcontainer.md`.

## Windows Security and Copilot (`windows\`)

Both scripts are safe to re-run and are elevated like the others; each writes a `.log` beside itself.

**On this box, DISM PowerShell cmdlets hang under pwsh 7.** Examples are `Get-WindowsOptionalFeature`, `Get-AppxProvisionedPackage` and `Add-WindowsCapability`. Their DismHost fails with `0x80040154` (class not registered), and `C:\Windows\Logs\DISM\dism.log` then logs "Retrying..." over and over; there is no error and no timeout. Seen 2026-11-10. Use `dism.exe` or Windows PowerShell 5.1 instead. `admin-copilot-off.ps1` calls `dism.exe` directly, with a 180-second timeout.

- **Defender exclusions** (`windows\admin-defender-exclusions.ps1`):
  - Paths: `D:\src`, `D:\packages` and `C:\Program Files\dotnet`.
  - Processes: `dotnet.exe`, `MSBuild.exe`, `devenv.exe` and `VBCSCompiler.exe`.
  - D: is a Dev Drive, so Defender already scans it in performance mode (in the background). These exclusions go further and skip scanning entirely for trusted dev content, which stops the alerts on unsigned build output.
  - The first manual pass (2026-11-10) excluded `%USERPROFILE%\.nuget\packages`. NuGet doesn't use that folder on this box, so the script removes that exclusion.
- **Smart App Control: off, by hand.** Windows Security → App & browser control. It isn't scriptable, and it flags almost every unsigned build output (for example the net472 test `.exe`s).
- **Copilot** (`windows\admin-copilot-off.ps1`). Run it from the buvy account, because its HKCU values go to whichever user elevates. Reboot afterwards. Policy names were checked against Microsoft Learn on 2026-11-10.
  - The Copilot app is uninstalled and deprovisioned. The `RemoveMicrosoftCopilotApp` policy is Enterprise/Education only, so it doesn't apply to this Pro machine.
  - WindowsAI policies:
    - `AllowRecallEnablement=0` (removes Recall; needs the reboot)
    - `DisableAIDataAnalysis=1`
    - `DisableClickToDo=1`
    - `DisableSettingsAgent=1` (Enterprise only; harmless here)
  - Paint: `DisableCocreator`, `DisableGenerativeFill` and `DisableImageCreator`.
  - `TurnOffWindowsCopilot=1` (HKCU). Deprecated, and it doesn't affect the new app; kept as a backstop.
  - Edge: `HubsSidebarEnabled=0`, `Microsoft365CopilotChatIconEnabled=0` and `EdgeEntraCopilotPageContext=0`. These don't apply to a profile signed in with a personal Microsoft account. What does work there is `ExtensionInstallBlocklist`, which blocks the Copilot extension `ofefcgjbeghpigppfmkologfjadafddi` machine-wide. Check `edge://policy`.
- **Bing** (`windows\admin-bing-off.ps1`). Run it from the buvy account, and sign out or reboot afterwards. Policy editions were checked against Microsoft Learn on 2026-11-11.
  - Start search's Bing results: the official policy `ConnectedSearchUseWeb=0` is Enterprise/Education only. It's set anyway, along with the old `DisableWebSearch=1` and `BingSearchEnabled=0`. What actually works on Pro is `HKCU\...\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions=1`.
  - Search highlights `EnableDynamicContentInWSB=0` and `AllowCloudSearch=0`, both of which apply on Pro.
  - Widgets (the MSN/Bing feed): `DisableWidgetsBoard=1` and `DisableWidgetsOnLockScreen=1` were written. **`AllowNewsAndInterests` can't be written directly.** An elevated `New-ItemProperty` failed with "Attempted to perform an unauthorized operation", even though Administrators have Full Control of the key and the other two values in it went in fine. So Windows protects that one value. Set it through Group Policy instead: `gpedit.msc` → Computer Configuration → Administrative Templates → Windows Components → Widgets → **Allow widgets** → **Disabled**. Done 2026-11-11, and `AllowNewsAndInterests=0` is now present. The script logs it as `BLOCKED` and carries on.
  - Apps removed from the Windows image with `dism.exe` on 2026-11-11, all exit 0: `Microsoft.BingNews`, `Microsoft.BingSearch`, `Microsoft.BingWeather` and `MicrosoftWindows.Client.WebExperience` (Widgets). `Remove-AppxPackage -AllUsers` was refused ("Access is denied"), but removing BingSearch and the Widgets app for buvy alone worked, even without admin. The script now falls back to that. `Microsoft.StartExperiencesApp` and `Microsoft.WidgetsPlatformRuntime` are left alone on purpose, because the Start menu and shell depend on them.
  - Not covered: Edge's default search engine. Policy can only change it on a domain-joined or MDM-enrolled machine, and Brave is the browser anyway.
- **Telemetry** (`windows\admin-telemetry-off.ps1`). Run it from the buvy account, then reboot. Editions checked against Microsoft Learn on 2026-11-11.
  - **Pro can't turn diagnostic data off by policy.** `AllowTelemetry=0` is Enterprise/Education/Server only; Pro clamps it to 1 (Required). The script sets 0 anyway, then does the real work: the **DiagTrack** (Connected User Experiences and Telemetry) and **dmwappushservice** services are stopped and disabled, and the collector/uploader scheduled tasks are disabled (Compatibility Appraiser, MareBackup, CEIP Consolidator/UsbCeip, Autochk\Proxy, DiskDiagnosticDataCollector, Feedback\Siuf, WER QueueReporting, Flighting UsageData*, OneSettings\RefreshCache).
  - Policies Pro honours: `LimitDiagnosticLogCollection`, `LimitDumpCollection`, `DisableOneSettingsDownloads`, `DoNotShowFeedbackNotifications`, advertising ID off (`DisabledByGroupPolicy`), activity history off (`PublishUserActivities`/`UploadUserActivities`/`EnableActivityFeed`), cross-device clipboard off, inking/typing personalisation off, Find My Device off, Windows Error Reporting off, CEIP off, AppCompat inventory/AIT/Steps Recorder off, tailored experiences off (HKCU).
  - Per-user ContentDeliveryManager switches (silent app installs, Start/Settings suggestions, "finish setting up" nags) all 0. `DisableWindowsConsumerFeatures` is Enterprise only, so these are what work.
  - **Left alone on purpose:** PcaSvc, DPS/WDI, the compat-shim tasks (PcaPatchDbTask, SdbinstMergeDbTask), StartupAppTask, and Flighting `Reconcile*`/`SafeguardsReconciliation` (update safeguard holds). They're local, and breaking them breaks app compat or updates. **Defender cloud protection and sample submission** stay on: that's a security trade-off, not telemetry to rip out casually.
  - Any task or service Windows protects is logged as `BLOCKED` and the script carries on.
  - **Delivery Optimization:** `DODownloadMode=99` (Simple mode: no peer-to-peer, no DO cloud service; updates come straight from Microsoft). The DoSvc service stays, because Windows Update and the Store download through it.
  - **Edge only when clicked:** `StartupBoostEnabled=0` and `BackgroundModeEnabled=0`, and any `MicrosoftEdgeAutoLaunch*` Run entry is removed (none existed 2026-11-11). Edge Update is left alone for security patches, and WebView2 is a separate runtime that apps need.
- **NextDNS** (`windows\admin-nextdns.ps1 -ConfigId <id>`). Windows 11's built-in DNS-over-HTTPS, nothing installed. Registers NextDNS's anycast addresses (`45.90.28.0`, `45.90.30.0`, `2a07:a8c0::`, `2a07:a8c1::`) as DoH servers with the template `https://dns.nextdns.io/<id>/surfacespark`, **no plaintext fallback**, and sets them on every present physical adapter (Wi-Fi and the Realtek USB 2.5GbE, even while it is unplugged). Virtual adapters (vEthernet) are untouched. Check at `https://test.nextdns.io` (status ok, protocol DOH).
  - In the NextDNS dashboard, Privacy → Native Tracking Protection → **Microsoft (Windows)** blocks the telemetry endpoints at DNS as a second layer behind the script above. On as of 2026-11-11, along with Apple, Samsung, Xiaomi, Alexa, Huawei, Roku, Sonos and LG.
  - Brave: Settings → Privacy and security → Use secure DNS should be on **with your current service provider** (the default) so it follows Windows rather than its own resolver.
  - A new adapter (a dock, another USB NIC) gets DHCP DNS until the script is re-run.
  - **Since 2026-11-11 Tailscale carries DNS here too.** The tailnet's DNS settings have NextDNS as the global nameserver, with Override DNS servers on (set up for the Mac; see `TOOLCHAIN-macos.md`). While Tailscale runs, its catch-all NRPT rule (`.` → `100.100.100.100`) sends every query through Tailscale to NextDNS over DoH, and the Wi-Fi DoH below handles only what's left when Tailscale is off. Check with `Get-DnsClientNrptPolicy`.
  - **What's actually in place (2026-11-11): Wi-Fi only, set by hand, script not run.** Settings → Network → Wi-Fi → Hardware properties → DNS: manual, IPv4 `45.90.28.0`/`45.90.30.0` and the config's linked IPv6 pair, DoH on with manual template `https://dns.nextdns.io/<id>`. Settings stores this per adapter (`HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\{guid}\DohInterfaceSettings`, `DohFlags=2`), not in the global DoH table the script uses, so don't mix the two on one adapter. test.nextdns.io: ok / DOH. The USB 2.5GbE isn't covered yet; do it in Settings the same way when it's plugged in, and add `/surfacespark` to the template so the logs name the box instead of `unknown-doh`.
- **By hand, no policy available:**
  - Lock-screen Spotlight (Bing images). The policy `DisableWindowsSpotlightFeatures` is Enterprise only. Settings → Personalization → Lock screen → **Picture**. Done 2026-11-11; `RotatingLockScreenEnabled=0`. Do the same for the desktop background if it's ever set to Spotlight.
    - The "Get fun facts, tips, tricks..." checkbox doesn't appear on 26H1 build 28000, but its per-user values do. They were set directly, without admin: `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`, `RotatingLockScreenOverlayEnabled=0` and `SubscribedContent-338387Enabled=0`.
  - **Office: removed 2026-11-10.** No Microsoft account sign-in anywhere on this box, and Microsoft 365 requires one.
    - Removed: the Microsoft 365 Click-to-Run apps, `%LOCALAPPDATA%\Microsoft\Office` (671 MB), `HKCU\Software\Microsoft\Office\16.0`, the new Outlook (`Microsoft.OutlookForWindows`, uninstalled and removed from the Windows image with `dism.exe`), the leftover OneDrive folders, and a broken `Run\Teams` entry for the native Teams app.
    - Re-scanned clean the same day: no Office/OneDrive folders, Click-to-Run registration, services, scheduled tasks or app packages. The only uninstall entry left is the Teams PWA, which lives in Brave and stays.
    - If Office is ever needed again: a retail Office 2024 key still has to be redeemed through a Microsoft account, which rules it out. **Office LTSC 2024** is activated by key with no account at any point, and it has no Copilot. It's licensed to organisations, but a CSP reseller can sell single perpetual licences to a small business. Otherwise, use Office on the Mac, or LibreOffice/ONLYOFFICE.
    - Windows activation (a digital licence tied to the hardware), winget including its `msstore` source, and Edge all work without signing in.
    - `OneDriveSetup.exe` still ships in `System32` and could bring OneDrive back after a feature update or for a new profile. `admin-copilot-off.ps1` sets `DisableFileSyncNGSC=1` ("Prevent the usage of OneDrive for file storage"), which keeps any OneDrive that comes back from syncing or appearing in Explorer and file pickers. This will also block Office's OneDrive integration once Office is back; that's intended.
  - The Copilot key sends Win+Shift(left)+F23; Windows has no "do nothing" option (Settings only offers Search or a signed MSIX app, and the `SetCopilotHardwareKey` policy needs an app). On 2026-11-11 it still pointed at the removed Office Hub (`HKCU\Software\Microsoft\Windows\Shell\BrandedKey`). The only true off switch is PowerToys Keyboard Manager (Remap a shortcut → Copilot key → **Disabled**), but PowerToys was uninstalled 2026-11-11 and isn't worth bringing back for a key that never gets pressed. Instead: Settings → Personalization → Text input → Customize Copilot key → **Search** (local search; Bing is already cut out of it). Note `desk\kbm-autoswitch.ps1` still assumes PowerToys for the Win↔Ctrl swap; that's part of its redesign.
  - Notepad: `admin-copilot-off.ps1` sets the policy `HKLM\SOFTWARE\Policies\WindowsNotepad\DisableAIFeatures=1` (Notepad 11.2503.16+; this box has 11.2607.14), so nothing needs doing by hand.
- **Dev tools:**
  - Visual Studio: `vs\.vsconfig` already leaves out Copilot and IntelliCode.
  - VS Code user settings: `"chat.disableAIFeatures": true`. It's a user setting, not scripted.

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
- The .NET Compiler Platform SDK (`Microsoft.Component.CodeAnalysis.SDK`) is included mainly to stop the "install missing features" dialog. VS shows that dialog when a solution has a project with `<IsRoslynComponent>true</IsRoslynComponent>`, such as TaskTupleAwaiter's source generator. Builds don't need the component, but it does add the "Roslyn Component" debug target and the Syntax Visualizer. It's small and has no TypeScript or Node dependencies.
- Container tools are included. They run containers through Docker Desktop or Podman, not wslc. Docker Desktop is started by hand, which matches VS's default "Start the container runtime if needed: Prompt me".
- Check after installing: `"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" export --installPath "C:\Program Files\Microsoft Visual Studio\18\Community" --config out.vsconfig`. Then confirm that nothing with TypeScript or Node in its name came in as a dependency.
