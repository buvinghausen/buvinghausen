# Run elevated. (1) Installs the supervisor with the Modern Standby guard (power request held while serving on AC).
# (2) Lock screen turns the display off after 60 s on AC (VIDEOCONLOCK). Production stays stopped/started as it was.
$ErrorActionPreference = 'Stop'
Start-Transcript (Join-Path $PSScriptRoot 'admin-powerguard.log') -Force | Out-Null
try {
  Copy-Item C:\llama.cpp\serve-qwen38.ps1 "C:\llama.cpp\serve-qwen38.ps1.bak-$(Get-Date -f yyyyMMdd-HHmm)"
  Copy-Item (Join-Path $PSScriptRoot 'serve-qwen38.ps1') C:\llama.cpp\serve-qwen38.ps1 -Force
  Stop-ScheduledTask llama-server; Start-Sleep 3; Start-ScheduledTask llama-server; Start-Sleep 8
  powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK 60
  powercfg /setactive SCHEME_CURRENT
  '--- VIDEOCONLOCK (AC should be 0x3c) ---'; powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOCONLOCK | Select-String 'Current'
  '--- task ---'; (Get-ScheduledTask llama-server).State
  '--- supervisor.log ---'; Get-Content C:\llama.cpp\logs\supervisor.log -Tail 4
  '--- powercfg /requests ---'; powercfg /requests
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
