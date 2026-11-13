# Phase 3 memory watchdog: samples host free RAM and GPU memory every 5 s into logs\phase3-mem.csv.
# If host free RAM stays under 1 GB for 30 s, it kills the BENCH llama-server (port 9940 only; production is 9931) and logs it.
# Runs until logs\phase3-watch.stop exists.
$B    = $PSScriptRoot
$csv  = Join-Path $B 'logs\phase3-mem.csv'
$stop = Join-Path $B 'logs\phase3-watch.stop'
function Log($m) { [IO.File]::AppendAllText("$B\progress.log", "$(Get-Date -f HH:mm:ss) [watchdog] $m`n") }
[IO.File]::WriteAllText($csv, "time,host_free_mb,gpu_used_mib,bench_server`n")
$low = 0; $minFree = [int]::MaxValue; $maxGpu = 0
while (-not (Test-Path $stop)) {
  $free = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
  $gpu  = [int]((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1) -as [int])
  $bench = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object { $_.CommandLine -match '--port\s+9940' })
  [IO.File]::AppendAllText($csv, "$(Get-Date -f HH:mm:ss),$free,$gpu,$($bench.Count)`n")
  if ($bench.Count) {
    if ($free -lt $minFree) { $minFree = $free }
    if ($gpu -gt $maxGpu) { $maxGpu = $gpu }
  }
  if ($bench.Count -and $free -lt 1024) { $low++ } else { $low = 0 }
  if ($low -ge 6) {
    Log "ABORT: host free RAM under 1 GB for 30 s ($free MB); killing bench server pid(s) $($bench.ProcessId -join ',')"
    $bench | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $low = 0
  }
  Start-Sleep 5
}
Log "stopped; while a bench server ran: min host free $minFree MB, max GPU used $maxGpu MiB"
