# Phase 3 (2026-11-12): NVIDIA's RTX Spark recipe for Qwen3.8 Flash-Next ("Launch MTP n=3"), run on our llama.cpp b12110
# instead of the recipe's pinned b11617. Unattended: download + verify, stop production, bench, capacity check, restart production.
# Launch detached (Start-Process), not as a Claude Code background shell, so memory-pressure reaping can't kill it.
#
# Recipe weights: unsloth UD-IQ4_XS in 3 shards, which exist only at the commit the recipe pins for its mmproj (38bb39e);
# main has since been re-quantized into 4 shards. MTP draft: ggml-org main (the recipe doesn't pin it).
# Deviations from the recipe, all on purpose: local paths instead of -hf/-hfrd/--mmproj-url (same files),
# bench.ps1's port 9940 and --n-predict 32768, and production's quality/speed harness instead of SPEED-Bench.
$ErrorActionPreference = 'Stop'
$B   = $PSScriptRoot
$M   = 'D:\models\qwen3.8-flash-next'
$pin = '38bb39ee97821de2c9009abb7e93950eec396e66'
function Log($m) { [IO.File]::AppendAllText("$B\progress.log", "$(Get-Date -f HH:mm:ss) $m`n") }
$files = @(
  @{ url = "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/$pin/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf"; sha = '5ce89370720f8bf90890f439361282104c1aa1482d4013bb9a50923e758e71a4' }
  @{ url = "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/$pin/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf"; sha = '577a38a2392b40ca2193cea502e1d92f60b8cd370675d308e0ec21885d9daaa7' }
  @{ url = "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/$pin/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf"; sha = 'd4634e6d84f0ebb0940be15c90d3790bf6464e3dea3a1cddc567dc0e83ad8833' }
  @{ url = "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/$pin/mmproj-BF16.gguf"; sha = '2e788f8c511d8093c7b43cb87b2fd7e14228340318057f8fb20c86df2efe2355' }
  @{ url = 'https://huggingface.co/ggml-org/Qwen3.8-Flash-Next-GGUF/resolve/main/mtp-Qwen3.8-Flash-Next-Q8_0.gguf'; sha = 'b6a0b61c66ee705e510c1c100a754dec67cf8dfbaea14cfd14ef1abcf6ac2bb9' }
)
$model  = "$M\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf"
$mmproj = "$M\mmproj-BF16.gguf"
$mtp    = "$M\mtp-Qwen3.8-Flash-Next-Q8_0.gguf"
$recipe = @('--batch-size', '2048', '-ngl', 'auto', '-fa', 'on', '-lzm', 'on', '--mmproj', $mmproj,
            '--spec-type', 'draft-mtp', '--spec-draft-n-max', '3', '--spec-draft-model', $mtp)   # appended after bench.ps1's own args; later flags win

# Keep the box out of Modern Standby while we run: production's supervisor releases its power request once production stops.
Add-Type -Namespace P3 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);'
[void][P3.Power]::SetThreadExecutionState([uint32]2147483651)   # 0x80000003 = ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED (a 0x8... literal is a negative Int32 in PowerShell)

$watch = $null
try {
  Log 'PHASE 3 START (Flash-Next UD-IQ4_XS + MTP n=3, NVIDIA recipe on b12110)'
  New-Item -ItemType Directory -Force $M, "$B\logs" | Out-Null
  foreach ($f in $files) {
    $dst = Join-Path $M (Split-Path $f.url -Leaf)
    if ((Test-Path $dst) -and (Get-FileHash $dst -Algorithm SHA256).Hash -eq $f.sha) { Log "have $(Split-Path $dst -Leaf)"; continue }
    Log "download $(Split-Path $dst -Leaf)"
    & curl.exe -L --fail --silent --show-error --retry 5 --retry-delay 10 -C - -o $dst $f.url
    if ($LASTEXITCODE) { throw "curl exit $LASTEXITCODE for $($f.url)" }
    if ((Get-FileHash $dst -Algorithm SHA256).Hash -ne $f.sha) { throw "sha256 mismatch: $dst" }
    Log "verified $(Split-Path $dst -Leaf) ($([math]::Round((Get-Item $dst).Length / 1GB, 2)) GB)"
  }

  Log 'stopping production (control\stop)'
  New-Item -ItemType File -Force C:\llama.cpp\control\stop | Out-Null
  $t0 = Get-Date
  while (Get-NetTCPConnection -LocalPort 9931 -State Listen -ErrorAction SilentlyContinue) {
    if (((Get-Date) - $t0).TotalMinutes -gt 3) { throw 'production did not stop within 3 min' }
    Start-Sleep 5
  }
  Start-Sleep 10   # let GPU memory drain
  Log "production stopped; GPU $(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>$null)"

  Remove-Item "$B\logs\phase3-watch.stop" -Force -ErrorAction SilentlyContinue
  $watch = Start-Process pwsh -ArgumentList '-NoProfile', '-File', "`"$B\phase3-watch.ps1`"" -WindowStyle Hidden -PassThru

  # Recipe shape: 1 slot x 256K.
  & "$B\bench.ps1" -Name 'flashnext-iq4-mtp' -Model $model -Ctx 262144 -Quality -Extra $recipe

  # Capacity: does it fit production's shape (2 slots x 256K), or 2 x 128K?
  foreach ($ctx in 524288, 262144) {
    $log = "$B\logs\flashnext-iq4-cap-$ctx.log"
    $a = @('-m', $model, '--host', '127.0.0.1', '--port', '9940', '--ctx-size', "$ctx", '--parallel', '2', '--ubatch-size', '512') + $recipe
    $p = Start-Process C:\llama.cpp\llama-server.exe -ArgumentList $a -WorkingDirectory C:\llama.cpp `
           -RedirectStandardError $log -RedirectStandardOutput "$log.out" -WindowStyle Hidden -PassThru
    $ok = $false; $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt 10 -and -not $p.HasExited) {
      Start-Sleep 5
      if ((Get-Content $log -Raw -ErrorAction SilentlyContinue) -match 'listening on') { $ok = $true; Start-Sleep 15; break }
    }
    $gpu = nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>$null | Select-Object -First 1
    $os  = Get-CimInstance Win32_OperatingSystem
    Log ("[flashnext-iq4-cap] parallel=2 ctx=$ctx ({0}K/slot) -> {1}; GPU {2}; host RAM free {3:N1} GB" -f ($ctx / 2048), $(if ($ok) { 'LOADED' } else { "FAILED (exit $($p.ExitCode))" }), $gpu, ($os.FreePhysicalMemory / 1MB))
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    Start-Sleep 15
    if ($ok) { break }
  }
} catch {
  Log "PHASE 3 ERROR: $_"
} finally {
  New-Item -ItemType File -Force "$B\logs\phase3-watch.stop" | Out-Null
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
  [void][P3.Power]::SetThreadExecutionState([uint32]2147483648)   # 0x80000000 = ES_CONTINUOUS: release
  Log 'PHASE 3 DONE'
}
