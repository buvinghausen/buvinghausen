# Flip production to Qwen3.8 Flash-Next (2026-11-13). Run elevated. Logs to admin-flip-flashnext.log next to this script.
#   1. Copy the recipe files from D:\models\qwen3.8-flash-next (user-writable) into C:\llama.cpp\models (Administrators/SYSTEM
#      only), so the SYSTEM supervisor never loads user-modifiable files; verify SHA-256 on the destination.
#   2. Deploy serve-qwen38.ps1 (Flash-Next args + GPU watchdog) and restart supervisor + server (admin-supervisor-update.ps1).
# The 27B files stay in C:\llama.cpp\models as a fallback (revert = previous serve-qwen38.ps1, backed up by step 2).
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'admin-flip-flashnext.log'
function Note($m) { $l = "$(Get-Date -f s) $m"; $l; Add-Content $log $l }
$src = 'D:\models\qwen3.8-flash-next'
$dst = 'C:\llama.cpp\models'
$files = @(
  @{ from = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf'; to = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf'; sha = '5ce89370720f8bf90890f439361282104c1aa1482d4013bb9a50923e758e71a4' }
  @{ from = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf'; to = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf'; sha = '577a38a2392b40ca2193cea502e1d92f60b8cd370675d308e0ec21885d9daaa7' }
  @{ from = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf'; to = 'Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf'; sha = 'd4634e6d84f0ebb0940be15c90d3790bf6464e3dea3a1cddc567dc0e83ad8833' }
  @{ from = 'mmproj-BF16.gguf';                                  to = 'Qwen3.8-Flash-Next-mmproj-BF16.gguf';               sha = '2e788f8c511d8093c7b43cb87b2fd7e14228340318057f8fb20c86df2efe2355' }
  @{ from = 'mtp-Qwen3.8-Flash-Next-Q8_0.gguf';                  to = 'mtp-Qwen3.8-Flash-Next-Q8_0.gguf';                  sha = 'b6a0b61c66ee705e510c1c100a754dec67cf8dfbaea14cfd14ef1abcf6ac2bb9' }
)
try {
  Note 'FLIP START'
  foreach ($f in $files) {
    $d = Join-Path $dst $f.to
    if ((Test-Path $d) -and (Get-FileHash $d -Algorithm SHA256).Hash -eq $f.sha) { Note "have $($f.to)"; continue }
    Note "copy $($f.from) -> $($f.to)"
    Copy-Item (Join-Path $src $f.from) $d -Force
    $h = (Get-FileHash $d -Algorithm SHA256).Hash
    if ($h -ne $f.sha) { Remove-Item $d -Force; throw "sha256 mismatch for $($f.to): $h" }
    Note "verified $($f.to) ($([math]::Round((Get-Item $d).Length / 1GB, 2)) GB)"
  }
  Note 'models in place; deploying supervisor with -RestartServer'
  & (Join-Path $PSScriptRoot 'admin-supervisor-update.ps1') -RestartServer
  Note 'FLIP DONE'
} catch { Note "FLIP ERROR: $_" }
Start-Sleep 3
