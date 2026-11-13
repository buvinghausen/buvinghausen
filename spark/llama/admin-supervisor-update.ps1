# Deploy this folder's serve-qwen38.ps1 to C:\llama.cpp and restart the "llama-server" supervisor task. Run elevated.
# The supervisor adopts a llama-server still listening on 9931, so production may keep running through this;
# if ending the task takes the server down too, the new supervisor starts a fresh one (~1 min to healthy).
$ErrorActionPreference = 'Stop'
Start-Transcript (Join-Path $PSScriptRoot 'admin-supervisor-update.log') -Force | Out-Null
try {
  Copy-Item C:\llama.cpp\serve-qwen38.ps1 "C:\llama.cpp\serve-qwen38.ps1.bak-$(Get-Date -f yyyyMMdd-HHmm)"
  Copy-Item (Join-Path $PSScriptRoot 'serve-qwen38.ps1') C:\llama.cpp -Force
  Stop-ScheduledTask llama-server
  Start-Sleep 3
  Start-ScheduledTask llama-server
  Start-Sleep 15
  "--- task ---"; Get-ScheduledTask llama-server | Select-Object TaskName, State | Format-List
  "--- status.txt ---"; Get-Content C:\llama.cpp\logs\status.txt
  "--- supervisor.log ---"; Get-Content C:\llama.cpp\logs\supervisor.log -Tail 5
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
