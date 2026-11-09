$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-setup.log')
Start-Transcript $out -Force | Out-Null
try {
  # 1. Firewall: allow TCP 9931 only from the M6 mini's Tailscale IP
  Get-NetFirewallRule -DisplayName 'llama-server (M6 mini via Tailscale)' -EA SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'llama-server (M6 mini via Tailscale)' -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort 9931 -RemoteAddress 100.110.233.121 -Profile Any | Out-Null
  'firewall rule created'
  # report any other inbound rules that mention llama-server (e.g. auto-created by Windows prompt)
  Get-NetFirewallApplicationFilter | Where-Object Program -match 'llama-server' | Get-NetFirewallRule |
    Select-Object DisplayName, Enabled, Action, Direction | Format-Table -AutoSize | Out-String

  # 2. Scheduled task: start at boot as SYSTEM, restart on failure, never time out
  $pwsh = (Get-Command pwsh).Source
  $action    = New-ScheduledTaskAction -Execute $pwsh -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\llama.cpp\serve-qwen38.ps1' -WorkingDirectory 'C:\llama.cpp'
  $trigger   = New-ScheduledTaskTrigger -AtStartup
  $trigger.Delay = 'PT30S'
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                 -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'llama-server' -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Qwen3.8-27B llama-server for M6 mini agents (C:\llama.cpp\serve-qwen38.ps1)' -Force | Out-Null
  'scheduled task registered'
  Start-ScheduledTask -TaskName 'llama-server'
  'scheduled task started'
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
