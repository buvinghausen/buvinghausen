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
- Gotchas: `Add-WindowsCapability` fails in pwsh 7 with "Class not registered" (use 5.1 or dism). The other DISM-module cmdlets (`Get-WindowsOptionalFeature`, `Get-AppxProvisionedPackage`, …) are worse: they hit the same `0x80040154` and keep retrying for minutes before failing with the same error (see Windows Security below). sshd takes the first value it sees for each setting, so managed settings are prepended.
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
- **By hand, no policy available:**
  - **Office: removed 2026-11-10.** No Microsoft account sign-in anywhere on this box, and Microsoft 365 requires one.
    - Removed: the Microsoft 365 Click-to-Run apps, `%LOCALAPPDATA%\Microsoft\Office` (671 MB), `HKCU\Software\Microsoft\Office\16.0`, the new Outlook (`Microsoft.OutlookForWindows`, uninstalled and removed from the Windows image with `dism.exe`), the leftover OneDrive folders, and a broken `Run\Teams` entry for the native Teams app.
    - Re-scanned clean the same day: no Office/OneDrive folders, Click-to-Run registration, services, scheduled tasks or app packages. The only uninstall entry left is the Teams PWA, which lives in Brave and stays.
    - If Office is ever needed again: a retail Office 2024 key still has to be redeemed through a Microsoft account, which rules it out. **Office LTSC 2024** is activated by key with no account at any point, and it has no Copilot. It's licensed to organisations, but a CSP reseller can sell single perpetual licences to a small business. Otherwise, use Office on the Mac, or LibreOffice/ONLYOFFICE.
    - Windows activation (a digital licence tied to the hardware), winget including its `msstore` source, and Edge all work without signing in.
    - `OneDriveSetup.exe` still ships in `System32` and could bring OneDrive back after a feature update or for a new profile. `admin-copilot-off.ps1` sets `DisableFileSyncNGSC=1` ("Prevent the usage of OneDrive for file storage"), which keeps any OneDrive that comes back from syncing or appearing in Explorer and file pickers. This will also block Office's OneDrive integration once Office is back; that's intended.
  - The Copilot key: Settings → Personalization → Text input.
  - Notepad: turn off AI features in its own Settings.
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
