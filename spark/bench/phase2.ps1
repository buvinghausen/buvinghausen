# Phase 2: Qwen3.8-Flash-Next UD-Q3_K_XL (no DFlash GGUF exists). Needs the whole GPU, so it waits for
# Phase 1 to finish AND for production (port 9931) to be stopped by the user. Falls back to smaller configs if load fails.
$B = $PSScriptRoot
$fn = 'C:\llama.cpp\models\bench\Qwen3.8-Flash-Next-UD-Q3_K_XL-00001-of-00004.gguf'
"$(Get-Date -f HH:mm:ss) PHASE 2 WAITING (waits for phase-1 completion + port 9931 down)" | Add-Content "$B\progress.log"
while (-not (Select-String "$B\progress.log" -Pattern '^\d\d:\d\d:\d\d PHASE 1 DONE$' -CaseSensitive -Quiet)) { Start-Sleep 60 }
while (Get-NetTCPConnection -LocalPort 9940 -State Listen -EA SilentlyContinue) { Start-Sleep 60 }
while (Get-NetTCPConnection -LocalPort 9931 -State Listen -EA SilentlyContinue) { Start-Sleep 60 }
Start-Sleep 20
"$(Get-Date -f HH:mm:ss) PHASE 2 START" | Add-Content "$B\progress.log"
$tries = @(
  @{ Ctx = 98304; Prefill = @(4096, 16384, 65536); Extra = @() },
  @{ Ctx = 32768; Prefill = @(4096, 16384);        Extra = @() },
  @{ Ctx = 32768; Prefill = @(4096, 16384);        Extra = @('--n-cpu-moe', '6') }
)
foreach ($t in $tries) {
  & "$B\bench.ps1" -Name 'flashnext-q3' -Model $fn -Quality -Ctx $t.Ctx -Prefill $t.Prefill -Extra $t.Extra
  $r = Get-Content "$B\results\flashnext-q3.json" -Raw | ConvertFrom-Json
  if ($r.prefill) { break }
  Copy-Item "$B\results\flashnext-q3.json" "$B\results\flashnext-q3-fail-ctx$($t.Ctx).json" -Force
  Copy-Item "$B\logs\flashnext-q3.log" "$B\logs\flashnext-q3-fail-ctx$($t.Ctx).log" -Force -EA SilentlyContinue
}
"$(Get-Date -f HH:mm:ss) PHASE 2 DONE" | Add-Content "$B\progress.log"
