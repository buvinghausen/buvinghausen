# Production llama-server SUPERVISOR for the M6 Mac mini agents (run at boot as SYSTEM by the "llama-server" scheduled task).
# Compatible with Windows PowerShell 5.1 (used by the task; Store pwsh can't run as SYSTEM) and pwsh 7.
#
# Control without admin: the folder C:\llama.cpp\control is writable by the owner account only.
#   control\stop     present  -> server is kept stopped (delete the file to start it again)
#   control\restart  touched  -> server is restarted once each time the file's timestamp changes
#   logs\status.txt           -> written by the supervisor: state, pid, since, log file
# Helpers: C:\llama.cpp\prod-stop.ps1, prod-start.ps1, prod-restart.ps1, prod-status.ps1 (no admin needed).
# Server arguments are below and require admin to change (this folder is locked to Administrators/SYSTEM).
#
# Model: Qwen3.8 Flash-Next UD-IQ4_XS + MTP draft (since 2026-11-13; previously Qwen3.8-27B Q4 + DFlash, whose files
# stay in models\ as a fallback). Chosen on bench phases 3-4 (spark/README.md): faster, and 20/24 vs 16/24 quality at 32K.
# Based on NVIDIA's RTX Spark recipe for Flash-Next (qwen/qwen3.8-flash-next/rtx-spark/windows/llama-cpp/iq4-xs/vision-mtp),
# with these deliberate differences:
#   - local model paths instead of -hf/-hfrd/--mmproj-url (no network/user-profile dependency at boot); the weights are the
#     3-shard upload at unsloth commit 38bb39e, which the recipe pins
#   - --host 0.0.0.0 + --api-key-file (access limited by firewall rule to the Mac's Tailscale IP)
#   - --parallel 2 with --ctx-size 524288 => 256K context per slot (orchestrator + implementer); loads at ~86 GB GPU
#   - --alias so clients can use a short model name
#   - --n-predict 32768 generation cap per request
#   - --cache-ram 2048: the default 8192 MiB host prompt cache grew server private bytes ~8 GB (bench phase 4), and
#     Flash-Next leaves only ~12-19 GB host RAM; with 2 agent slots cross-conversation reuse is worth little
$ErrorActionPreference = 'Stop'
$root    = 'C:\llama.cpp'
$m       = Join-Path $root 'models'
$logs    = Join-Path $root 'logs'
$ctl     = Join-Path $root 'control'
$port    = 9931
$exe     = Join-Path $root 'llama-server.exe'
$keyFile = Join-Path $root 'api-key.txt'
New-Item -ItemType Directory -Force $logs, $ctl | Out-Null

$llamaArgs = @(
  '-m', "`"$m\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf`"",
  '--mmproj', "`"$m\Qwen3.8-Flash-Next-mmproj-BF16.gguf`"",
  '--alias', 'qwen3.8-flash-next',
  '--host', '0.0.0.0',
  '--port', "$port",
  '--api-key-file', "`"$keyFile`"",
  '--batch-size', '2048',
  '--ubatch-size', '512',
  '--ctx-size', '524288',
  '--parallel', '2',
  '--n-predict', '32768',          # cap per-request generation (Hermes sends no max_tokens; stops runaway reasoning)
  '--cache-ram', '2048',           # MiB of host prompt cache (default 8192); see header
  '-ngl', 'auto',
  '-fa', 'on',
  '-lzm', 'on',                    # lazy tensor loading: keeps the 87 GB of weights from spilling into host RAM
  '--spec-type', 'draft-mtp',
  '--spec-draft-n-max', '3',
  '--spec-draft-model', "`"$m\mtp-Qwen3.8-Flash-Next-Q8_0.gguf`"",
  '--temp', '1.0',
  '--top-p', '0.95',
  '--top-k', '20',
  '--min-p', '0.0',
  '--presence-penalty', '0.0',
  '--repeat-penalty', '1.0'
)

$supLog = Join-Path $logs 'supervisor.log'
function Note($msg) { "$(Get-Date -Format s) $msg" | Add-Content $supLog }
# Security: control\ is user-writable, so SYSTEM only ever *reads* there (Test-Path / timestamps) - it never
# writes or deletes in it (no junction/symlink tricks into arbitrary SYSTEM file writes/deletes).
# status.txt lives in logs\, which only Administrators/SYSTEM can write.
$statusFile = Join-Path $logs 'status.txt'
$script:lastState = ''
function Status($state, $procId, $logFile) {
  $key = "$state|$procId"
  if ($key -eq $script:lastState) { return }
  $script:lastState = $key
  "state=$state`r`npid=$procId`r`nsince=$(Get-Date -Format s)`r`nlog=$logFile" | Set-Content $statusFile
}
function RestartStamp {
  $f = Get-Item (Join-Path $ctl 'restart') -Force -ErrorAction SilentlyContinue
  if ($f -and -not $f.PSIsContainer) { return $f.LastWriteTimeUtc.Ticks } else { return 0 }
}
function Get-ServerProc {
  # Adopt whatever llama-server.exe is listening on our port (e.g. survived a supervisor restart), so we never start a second one.
  $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; if ($p -and $p.ProcessName -eq 'llama-server') { return $p } }
  return $null
}
function Stop-Server($p) {
  if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $p.WaitForExit(30000) | Out-Null }
}

# GPU-state watchdog. /health only proves the HTTP loop is alive: after an NVIDIA driver update (2026-11-12) the
# server lost its GPU memory, /health stayed "ok" and every completion failed ("failed to allocate CUDA0 buffer").
# A real completion probe would land in an idle slot and evict an agent's cached prompt (minutes of re-prefill at
# 256K), so detection is passive. Every 60 s, once the server is 5 min old:
#   - total GPU memory used (nvidia-smi; per-process figures are N/A under WDDM) below half the healthy peak, or
#   - a CUDA allocation/error line in the server's stderr log since the last start (sticky until restart).
# Bad on 2 consecutive checks -> restart the server (counts toward the 3-crash back-off).
$nvsmi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
$gpuCheckEvery = 60
$script:gpuBase = 0; $script:gpuBad = 0; $script:logPos = 0; $script:logErr = $false; $script:lastGpuCheck = Get-Date
function Reset-GpuWatch { $script:gpuBase = 0; $script:gpuBad = 0; $script:logPos = 0; $script:logErr = $false; $script:lastGpuCheck = Get-Date }
function Get-GpuUsedMiB {
  try { $v = & $nvsmi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1; return [int]$v } catch { return -1 }
}
function Test-NewLogErrors($file) {
  # read only what llama-server appended since the last check; it holds the file open, so share ReadWrite
  if (-not $file -or -not (Test-Path $file)) { return $false }
  $fs = [System.IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
  try {
    if ($fs.Length -lt $script:logPos) { $script:logPos = 0 }
    [void]$fs.Seek($script:logPos, 'Begin')
    $text = (New-Object System.IO.StreamReader($fs)).ReadToEnd()
    $script:logPos = $fs.Length
  } finally { $fs.Dispose() }
  return ($text -match 'failed to allocate CUDA|CUDA error')
}
function Test-GpuState($p, $logFile) {
  # returns a reason string when the server should be restarted, else $null
  if (((Get-Date) - $script:lastGpuCheck).TotalSeconds -lt $gpuCheckEvery) { return $null }
  $script:lastGpuCheck = Get-Date
  try { $age = ((Get-Date) - $p.StartTime).TotalMinutes } catch { $age = 999 }
  if ($age -lt 5) { return $null }   # still loading / warming up
  if (Test-NewLogErrors $logFile) { $script:logErr = $true }
  $used = Get-GpuUsedMiB
  if ($used -gt $script:gpuBase) { $script:gpuBase = $used }
  $memLost = ($used -ge 0 -and $script:gpuBase -gt 0 -and $used -lt ($script:gpuBase / 2))
  if ($memLost -or $script:logErr) { $script:gpuBad++ } else { $script:gpuBad = 0 }
  if ($script:gpuBad -ge 2) { return "GPU state lost (gpu used $used MiB, healthy peak $($script:gpuBase) MiB, CUDA error in log: $($script:logErr))" }
  return $null
}

# Modern Standby guard. On this machine display-off = Modern Standby, whose sleep phase parks the GPU and pauses
# inference (seen 2026-11-08). While llama-server runs ON AC POWER, hold SystemRequired (blocks the low-power
# sleep phase; the screen may still turn off) + ExecutionRequired (no throttling). On battery the request is
# released so a closed lid in a bag still sleeps (Microsoft: never hold SystemRequired indefinitely on battery).
# Visible in an elevated `powercfg /requests` under SYSTEM / EXECUTION with the reason string below.
Add-Type -Namespace SparkPower -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct REASON_CONTEXT { public uint Version; public uint Flags; [MarshalAs(UnmanagedType.LPWStr)] public string SimpleReasonString; }
[StructLayout(LayoutKind.Sequential)]
public struct SYSTEM_POWER_STATUS { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr PowerCreateRequest(ref REASON_CONTEXT ctx);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool PowerSetRequest(IntPtr h, int type);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool PowerClearRequest(IntPtr h, int type);
[DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS s);
'@
$ctxReason = New-Object SparkPower.Native+REASON_CONTEXT
$ctxReason.Version = 0; $ctxReason.Flags = 1   # POWER_REQUEST_CONTEXT_VERSION, POWER_REQUEST_CONTEXT_SIMPLE_STRING
$ctxReason.SimpleReasonString = 'llama-server is serving inference (no Modern Standby while on AC)'
$script:powerReq = [SparkPower.Native]::PowerCreateRequest([ref]$ctxReason)
$script:powerHeld = $false
function On-AC { $ps = New-Object SparkPower.Native+SYSTEM_POWER_STATUS; [void][SparkPower.Native]::GetSystemPowerStatus([ref]$ps); return ($ps.ACLineStatus -eq 1) }
function Update-PowerHold($serving) {
  $want = $serving -and (On-AC)
  if ($want -eq $script:powerHeld) { return }
  if ($want) {
    $ok = [SparkPower.Native]::PowerSetRequest($script:powerReq, 1) -and [SparkPower.Native]::PowerSetRequest($script:powerReq, 3)   # SystemRequired, ExecutionRequired
    Note "power request HELD (system+execution required), ok=$ok"
  } else {
    [void][SparkPower.Native]::PowerClearRequest($script:powerReq, 1); [void][SparkPower.Native]::PowerClearRequest($script:powerReq, 3)
    Note "power request RELEASED (serving=$serving, onAC=$(On-AC))"
  }
  $script:powerHeld = $want
}

Note "supervisor start (pid $PID)"
$srv = Get-ServerProc
if ($srv) { Note "adopted running server pid $($srv.Id)"; Status "running (adopted)" $srv.Id ""; Reset-GpuWatch }
$srvLog = ''
$fails = 0
$lastRestart = RestartStamp   # only react to restart requests made after the supervisor started
while ($true) {
  # periodic housekeeping
  Get-ChildItem $logs -Filter 'server-*.log' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } | Remove-Item -Force -ErrorAction SilentlyContinue

  if (Test-Path (Join-Path $ctl 'stop')) {
    if ($srv -and -not $srv.HasExited) { Note "stop flag present -> stopping pid $($srv.Id)"; Stop-Server $srv }
    $srv = $null; $fails = 0
    Status 'stopped (control\stop present)' '' ''
    Update-PowerHold $false
    Start-Sleep 5; continue
  }

  $rs = RestartStamp
  if ($rs -ne $lastRestart) {
    $lastRestart = $rs
    if ($srv -and -not $srv.HasExited) { Note "restart flag -> stopping pid $($srv.Id)"; Stop-Server $srv }
    $srv = $null; $fails = 0
  }

  if (-not $srv -or $srv.HasExited) {
    if ($srv) { Note "server pid $($srv.Id) exited with code $($srv.ExitCode)"; $fails++ }
    $srv = $null
    if ($fails -ge 3) {
      # back off so a broken config doesn't spin; still honours stop/restart flags every 5 s
      Status "crashing - backing off (fails=$fails); see $srvLog" '' $srvLog
      for ($i = 0; $i -lt 12 -and -not (Test-Path (Join-Path $ctl 'stop')) -and (RestartStamp) -eq $lastRestart; $i++) { Start-Sleep 5 }
      if ((Test-Path (Join-Path $ctl 'stop')) -or (RestartStamp) -ne $lastRestart) { continue }   # let the top of the loop handle it
    }
    $stamp  = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $srvLog = Join-Path $logs "server-$stamp.log"       # llama-server logs to stderr
    $out    = Join-Path $logs "server-$stamp.out.log"
    # Pre-flight: fail loudly (and readably) if the API key file is missing or empty
    if (-not (Test-Path $keyFile) -or -not (Get-Content $keyFile -Raw -ErrorAction SilentlyContinue).Trim()) {
      "$(Get-Date -Format s) FATAL: $keyFile is missing or empty. Restore the key from Bitwarden ('Spark llama-server API key'); the supervisor retries every 30 s." | Set-Content (Join-Path $logs 'server-FATAL.log')
      Status "FATAL: api-key.txt missing or empty" '' (Join-Path $logs 'server-FATAL.log')
      Note 'api-key.txt missing or empty; waiting'
      Start-Sleep 30; continue
    }
    if (Get-ServerProc) { $srv = Get-ServerProc; $srvLog = ''; Note "port $port already served by pid $($srv.Id); adopting"; Status "running (adopted)" $srv.Id ""; Reset-GpuWatch; continue }
    $srv = Start-Process -FilePath $exe -ArgumentList $llamaArgs -WorkingDirectory $root `
             -RedirectStandardError $srvLog -RedirectStandardOutput $out -NoNewWindow -PassThru
    Note "started server pid $($srv.Id), log $srvLog"
    Status 'running' $srv.Id $srvLog
    Reset-GpuWatch
  } else {
    if ($fails -gt 0 -and ((Get-Date) - $srv.StartTime).TotalMinutes -gt 10) {
      $fails = 0   # stable for 10 minutes: forget earlier crashes
    }
    $why = Test-GpuState $srv $srvLog
    if ($why) {
      Note "$why -> restarting pid $($srv.Id)"
      Stop-Server $srv
      $srv = $null; $fails++
      Status "restarting: $why" '' $srvLog
      Update-PowerHold $false
      Start-Sleep 5; continue
    }
  }
  Update-PowerHold ([bool]($srv -and -not $srv.HasExited))
  Start-Sleep 5
}
