# Phase 4 (2026-11-12): quality re-run at production's real generation cap (32768 instead of bench's 16384),
# for both candidates, with detailed memory logging (phase4-watch.ps1) to explain phase 3's host-RAM decline.
#   1. Flash-Next UD-IQ4_XS + MTP n=3, NVIDIA recipe, 1 x 256K (same args as phase 3's flashnext-iq4-mtp)
#   2. Production's 27B UD-Q4_K_M + DFlash (same args as q4-dflash)
# Quality only (speed numbers already exist). Launch detached (Start-Process), not as a Claude Code background shell.
$ErrorActionPreference = 'Stop'
$B  = $PSScriptRoot
$FN = 'D:\models\qwen3.8-flash-next'
$LM = 'C:\llama.cpp\models'
function Log($m) { [IO.File]::AppendAllText("$B\progress.log", "$(Get-Date -f HH:mm:ss) $m`n") }
$recipe = @('--batch-size', '2048', '-ngl', 'auto', '-fa', 'on', '-lzm', 'on', '--mmproj', "$FN\mmproj-BF16.gguf",
            '--spec-type', 'draft-mtp', '--spec-draft-n-max', '3', '--spec-draft-model', "$FN\mtp-Qwen3.8-Flash-Next-Q8_0.gguf")

Add-Type -Namespace P4 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][P4.Power]::SetThreadExecutionState([uint32]2147483651)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED

try {
  Log 'PHASE 4 START (quality @ 32768 tokens: Flash-Next IQ4_XS+MTP, then 27B Q4+DFlash; detailed memory log)'
  foreach ($f in "$FN\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf", "$FN\mtp-Qwen3.8-Flash-Next-Q8_0.gguf", "$FN\mmproj-BF16.gguf",
                 "$LM\Qwen3.8-27B-UD-Q4_K_M.gguf", "$LM\Qwen3.8-27B-DFlash2-Q4_K_M.gguf") {
    if (-not (Test-Path $f)) { throw "missing $f" }
  }

  Log 'stopping production (control\stop)'
  New-Item -ItemType File -Force C:\llama.cpp\control\stop | Out-Null
  $t0 = Get-Date
  while (Get-NetTCPConnection -LocalPort 9931 -State Listen -ErrorAction SilentlyContinue) {
    if (((Get-Date) - $t0).TotalMinutes -gt 3) { throw 'production did not stop within 3 min' }
    Start-Sleep 5
  }
  Start-Sleep 10
  Log "production stopped; GPU $(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>$null | Select-Object -First 1)"

  Remove-Item "$B\logs\phase4-watch.stop" -Force -ErrorAction SilentlyContinue
  Start-Process pwsh -ArgumentList '-NoProfile', '-File', "`"$B\phase4-watch.ps1`"" -WindowStyle Hidden | Out-Null
  Start-Sleep 20   # a couple of idle baseline samples

  & "$B\bench.ps1" -Name 'flashnext-iq4-mtp-32k' -Model "$FN\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf" -Ctx 262144 `
      -Quality -QualityOnly -QualityMaxTokens 32768 -Extra $recipe
  Log 'pause 60 s between models (memory should settle; visible in phase4-mem.csv)'
  Start-Sleep 60
  & "$B\bench.ps1" -Name 'q4-dflash-32k' -Model "$LM\Qwen3.8-27B-UD-Q4_K_M.gguf" -Draft "$LM\Qwen3.8-27B-DFlash2-Q4_K_M.gguf" `
      -Ctx 98304 -Quality -QualityOnly -QualityMaxTokens 32768
} catch {
  Log "PHASE 4 ERROR: $_"
} finally {
  New-Item -ItemType File -Force "$B\logs\phase4-watch.stop" | Out-Null
  Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" | Where-Object { $_.CommandLine -match '--port\s+9940' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Log 'starting production (removing control\stop)'
  Remove-Item C:\llama.cpp\control\stop -Force -ErrorAction SilentlyContinue
  $healthy = $false; $t0 = Get-Date
  while (((Get-Date) - $t0).TotalMinutes -lt 5) {
    Start-Sleep 10
    try { if ((Invoke-RestMethod http://127.0.0.1:9931/health -TimeoutSec 5).status -eq 'ok') { $healthy = $true; break } } catch {}
  }
  Log "production health: $(if ($healthy) { 'ok' } else { 'NOT HEALTHY after 5 min - check C:\llama.cpp\logs\status.txt' })"
  [void][P4.Power]::SetThreadExecutionState([uint32]2147483648)
  Log 'PHASE 4 DONE'
}
