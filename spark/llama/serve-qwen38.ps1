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
# Based on NVIDIA's RTX Spark recipe (start-qwen38-nvidia.ps1), with these deliberate differences:
#   - local model paths instead of -hf/-hfrd/--mmproj-url (no network/user-profile dependency at boot)
#   - --host 0.0.0.0 + --api-key-file (access limited by firewall rule to the Mac's Tailscale IP)
#   - --parallel 2 with --ctx-size 524288 => 256K context per slot (orchestrator + implementer)
#   - --alias so clients can use a short model name
#   - --n-predict 32768 generation cap per request
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
  '-m', "`"$m\Qwen3.8-27B-UD-Q4_K_M.gguf`"",
  '--mmproj', "`"$m\mmproj-F16.gguf`"",
  '--alias', 'qwen3.8-27b',
  '--host', '0.0.0.0',
  '--port', "$port",
  '--api-key-file', "`"$keyFile`"",
  '--batch-size', '4096',
  '--ubatch-size', '512',
  '--ctx-size', '524288',
  '--parallel', '2',
  '--n-predict', '32768',          # cap per-request generation (Hermes sends no max_tokens; stops runaway reasoning)
  '-ngl', '999',
  '--spec-type', 'draft-dflash',
  '--spec-draft-n-max', '7',
  '--spec-draft-model', "`"$m\Qwen3.8-27B-DFlash2-Q4_K_M.gguf`"",
  '--spec-draft-backend-sampling',
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

Note "supervisor start (pid $PID)"
$srv = Get-ServerProc
if ($srv) { Note "adopted running server pid $($srv.Id)"; Status "running (adopted)" $srv.Id "" }
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
    if (Get-ServerProc) { $srv = Get-ServerProc; Note "port $port already served by pid $($srv.Id); adopting"; Status "running (adopted)" $srv.Id ""; continue }
    $srv = Start-Process -FilePath $exe -ArgumentList $llamaArgs -WorkingDirectory $root `
             -RedirectStandardError $srvLog -RedirectStandardOutput $out -NoNewWindow -PassThru
    Note "started server pid $($srv.Id), log $srvLog"
    Status 'running' $srv.Id $srvLog
  } elseif ($fails -gt 0 -and ((Get-Date) - $srv.StartTime).TotalMinutes -gt 10) {
    $fails = 0   # stable for 10 minutes: forget earlier crashes
  }
  Start-Sleep 5
}
