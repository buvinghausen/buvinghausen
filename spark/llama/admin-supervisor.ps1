# Install the no-admin-control supervisor for production llama-server. Run elevated. Logs next to this script.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'deploy'
Start-Transcript (Join-Path $PSScriptRoot 'admin-supervisor.log') -Force | Out-Null
try {
  Copy-Item C:\llama.cpp\serve-qwen38.ps1 "C:\llama.cpp\serve-qwen38.ps1.bak-$(Get-Date -f yyyyMMdd-HHmm)"
  Copy-Item "$src\serve-qwen38.ps1","$src\prod-stop.ps1","$src\prod-start.ps1","$src\prod-restart.ps1","$src\prod-status.ps1" C:\llama.cpp -Force
  # control folder: inherits Admins/SYSTEM full + Users read; add Modify for the owner account only
  New-Item -ItemType Directory -Force C:\llama.cpp\control | Out-Null
  icacls C:\llama.cpp\control /grant "surfacespark\buvy:(OI)(CI)M"
  # keep production stopped for now (benchmarks are running); prod-start.ps1 clears this later
  New-Item -ItemType File -Force C:\llama.cpp\control\stop | Out-Null
  # a long-running task must not be killed by the default 72 h execution limit
  $t = Get-ScheduledTask llama-server
  $t.Settings.ExecutionTimeLimit = 'PT0S'
  Set-ScheduledTask -InputObject $t | Out-Null
  Enable-ScheduledTask llama-server | Out-Null
  Start-ScheduledTask llama-server
  Start-Sleep 10
  "--- task ---"; Get-ScheduledTask llama-server | Select-Object TaskName, State | Format-List
  (Get-ScheduledTask llama-server).Settings | Select-Object ExecutionTimeLimit, RestartCount, RestartInterval | Format-List
  "--- status.txt ---"; Get-Content C:\llama.cpp\logs\status.txt
  "--- supervisor.log ---"; Get-Content C:\llama.cpp\logs\supervisor.log -Tail 5
  "--- control ACL ---"; icacls C:\llama.cpp\control
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
