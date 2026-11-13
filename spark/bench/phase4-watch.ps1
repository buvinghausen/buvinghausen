# Phase 4 memory logger + watchdog. Every 10 s writes logs\phase4-mem.csv:
#   free / available RAM, standby (file cache) and modified page lists, commit charge, GPU used,
#   bench llama-server private bytes + working set, and the WSL VM (vmmem) working set.
# Purpose: tell file cache (standby; counts as available, harmless) apart from real growth (private bytes / commit).
# Safety: if AVAILABLE RAM stays under 1 GB for 30 s, kill the BENCH llama-server (port 9940 only).
# Runs until logs\phase4-watch.stop exists.
$B    = $PSScriptRoot
$csv  = Join-Path $B 'logs\phase4-mem.csv'
$stop = Join-Path $B 'logs\phase4-watch.stop'
function Log($m) { [IO.File]::AppendAllText("$B\progress.log", "$(Get-Date -f HH:mm:ss) [watchdog4] $m`n") }
$ctrs = '\Memory\Available MBytes', '\Memory\Standby Cache Normal Priority Bytes', '\Memory\Standby Cache Reserve Bytes',
        '\Memory\Standby Cache Core Bytes', '\Memory\Modified Page List Bytes', '\Memory\Committed Bytes'
[IO.File]::WriteAllText($csv, "time,free_mb,avail_mb,standby_mb,modified_mb,commit_mb,gpu_mib,bench_private_mb,bench_ws_mb,vmmem_ws_mb,bench_pid`n")
$low = 0; $minAvail = [int]::MaxValue; $minFree = [int]::MaxValue; $maxPriv = 0
while (-not (Test-Path $stop)) {
  try {
    $c = @{}; (Get-Counter $ctrs -ErrorAction SilentlyContinue).CounterSamples | ForEach-Object { $c[$_.Path.Split('\')[-1]] = $_.CookedValue }
    $free    = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
    $avail   = [int]$c['available mbytes']
    $standby = [int](($c['standby cache normal priority bytes'] + $c['standby cache reserve bytes'] + $c['standby cache core bytes']) / 1MB)
    $mod     = [int]($c['modified page list bytes'] / 1MB)
    $commit  = [int]($c['committed bytes'] / 1MB)
    $gpu     = [int]((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1) -as [int])
    $bench   = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object { $_.CommandLine -match '--port\s+9940' } | Select-Object -First 1
    $priv = 0; $ws = 0; $bpid = ''
    if ($bench) { $p = Get-Process -Id $bench.ProcessId -ErrorAction SilentlyContinue; if ($p) { $priv = [int]($p.PrivateMemorySize64 / 1MB); $ws = [int]($p.WorkingSet64 / 1MB); $bpid = $p.Id } }
    $vm = [int]((Get-Process vmmem*, vmmemWSL -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
    [IO.File]::AppendAllText($csv, "$(Get-Date -f HH:mm:ss),$free,$avail,$standby,$mod,$commit,$gpu,$priv,$ws,$vm,$bpid`n")
    if ($bench) {
      if ($avail -lt $minAvail) { $minAvail = $avail }; if ($free -lt $minFree) { $minFree = $free }; if ($priv -gt $maxPriv) { $maxPriv = $priv }
      if ($avail -lt 1024) { $low++ } else { $low = 0 }
      if ($low -ge 3) {
        Log "ABORT: available RAM under 1 GB for 30 s ($avail MB); killing bench server pid $($bench.ProcessId)"
        Stop-Process -Id $bench.ProcessId -Force -ErrorAction SilentlyContinue; $low = 0
      }
    } else { $low = 0 }
  } catch { Log "sample error: $_" }
  Start-Sleep 10
}
Log "stopped; while a bench server ran: min available $minAvail MB, min free $minFree MB, max bench private $maxPriv MB"
