# Phase 2b: finish Flash-Next quality (skip the 6 samples done before the 00:09 kill), then a two-slot capacity check.
# Launched detached (not as a Claude Code background shell) so memory-pressure reaping can't kill it. Production must be stopped.
$B  = $PSScriptRoot
$fn = 'C:\llama.cpp\models\bench\Qwen3.8-Flash-Next-UD-Q3_K_XL-00001-of-00004.gguf'
function Log($m) { "$(Get-Date -f HH:mm:ss) $m" | Add-Content "$B\progress.log" }
if (Get-NetTCPConnection -LocalPort 9931 -State Listen -EA SilentlyContinue) { Log 'PHASE 2b ABORT: production is running on 9931'; exit 1 }
Log 'PHASE 2b START (quality resume, --load-mode none)'
& "$B\bench.ps1" -Name 'flashnext-q3-quality' -Model $fn -Quality -QualityOnly -Ctx 98304 -Extra @('--load-mode', 'none') `
  -Skip 'iso_duration#1','iso_duration#2','lru_cache#1','lru_cache#2','merge_intervals#1','merge_intervals#2'

# Capacity: can Flash-Next serve 2 slots (production shape)? Try big -> small, record load result + GPU memory.
foreach ($ctx in 262144, 131072) {
  $log = "$B\logs\flashnext-cap-$ctx.log"
  $p = Start-Process C:\llama.cpp\llama-server.exe -ArgumentList @('-m', "`"$fn`"", '--host', '127.0.0.1', '--port', '9940', '--ctx-size', "$ctx", '--parallel', '2', '-ngl', '999', '--load-mode', 'none', '--batch-size', '4096', '--ubatch-size', '512') `
         -WorkingDirectory C:\llama.cpp -RedirectStandardError $log -RedirectStandardOutput "$log.out" -WindowStyle Hidden -PassThru
  $ok = $false; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalMinutes -lt 10 -and -not $p.HasExited) {
    Start-Sleep 5
    if ((Get-Content $log -Raw -EA SilentlyContinue) -match 'listening on') { $ok = $true; break }
  }
  $gpu = (nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>$null | Select-Object -First 1)
  $os = Get-CimInstance Win32_OperatingSystem
  Log ("[flashnext-cap] parallel=2 ctx=$ctx ({0}K/slot) -> {1}; GPU {2}; host RAM free {3:N1} GB" -f ($ctx / 2048), $(if ($ok) { 'LOADED' } else { "FAILED (exit $($p.ExitCode))" }), $gpu, ($os.FreePhysicalMemory / 1MB))
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
  Start-Sleep 10
  if ($ok) { break }
}
Log 'PHASE 2b DONE'
