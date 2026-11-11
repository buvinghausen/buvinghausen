# Phase 1: Qwen3.8-27B Q4 vs Q8, with/without DFlash, run next to production (port 9940, loopback only).
$B = $PSScriptRoot
$m = 'C:\llama.cpp\models'
$q4 = "$m\Qwen3.8-27B-UD-Q4_K_M.gguf"
$q8 = "$m\bench\Qwen3.8-27B-Q8_0.gguf"
$df = "$m\Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
function Log($m) { [IO.File]::AppendAllText("$B\progress.log", "$(Get-Date -f HH:mm:ss) $m`n") }   # LF, not Add-Content's CRLF
Log 'PHASE 1 START'

& "$B\bench.ps1" -Name 'q4-dflash'  -Model $q4 -Draft $df -Quality
& "$B\bench.ps1" -Name 'q4-nodraft' -Model $q4

# wait for the Q8 download to finish (first entry in the download log)
while (-not (Select-String -Path "$m\bench\download.log" -Pattern 'Q8_0\.gguf' -Quiet -EA SilentlyContinue)) { Start-Sleep 30 }
& "$B\bench.ps1" -Name 'q8-dflash'  -Model $q8 -Draft $df -Quality
& "$B\bench.ps1" -Name 'q8-nodraft' -Model $q8
Log 'PHASE 1 DONE'
