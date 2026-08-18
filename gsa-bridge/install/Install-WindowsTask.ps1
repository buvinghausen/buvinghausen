<#
.SYNOPSIS
  Register (or remove) the logon Scheduled Task that runs the Windows half of gsa-bridge.

.DESCRIPTION
  Runs hidden at logon under the current user. No admin rights needed: the task runs as
  you, and the relay only binds loopback ports above 1024.

  The task starts regardless of GSA state - listeners are passive and resolution is lazy,
  so starting before the GSA client has authenticated is fine and expected.

.EXAMPLE
  .\Install-WindowsTask.ps1
  .\Install-WindowsTask.ps1 -Uninstall
#>
[CmdletBinding()]
param(
  [string]$TaskName = 'gsa-bridge',
  [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'gsa-bridge.ps1'
if (-not (Test-Path $scriptPath)) { throw "cannot find gsa-bridge.ps1 at $scriptPath" }

if ($Uninstall) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "removed scheduled task '$TaskName'"
  } else {
    Write-Host "no scheduled task named '$TaskName'"
  }
  return
}

$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe' }
if (-not (Test-Path $pwsh)) { throw "PowerShell 7 not found; install it or edit this script" }

$action = New-ScheduledTaskAction -Execute $pwsh `
  -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -RestartCount 3

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Principal $principal -Force `
  -Description 'Relays GSA-protected Azure endpoints into WSL2 (see gsa-bridge/spec.md)' | Out-Null

Write-Host "registered scheduled task '$TaskName' (runs hidden at logon)"
Write-Host "start it now with:  Start-ScheduledTask -TaskName $TaskName"
Write-Host "watch it live with: pwsh -File `"$scriptPath`""
