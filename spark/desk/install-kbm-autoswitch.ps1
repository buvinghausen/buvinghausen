# Installs / re-registers the per-user "KbmAutoSwitch" task (no admin). Run as the signed-in user from this folder.
#   - Runs headless: conhost.exe --headless hosts powershell.exe, so there is no console window that anything can close.
#     (2026-11-09: the windowed version died twice with 0xC000013A = its console was closed; cause not identified.)
#   - Triggers: at logon, plus every 5 minutes as a watchdog. MultipleInstances=IgnoreNew means the watchdog is a no-op
#     while the script runs, and restarts it within 5 min if it ever exits. ("Restart on failure" only covers failed starts.)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'KbmAutoSwitch'
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'kbm-autoswitch.ps1') $dir -Force
$script = Join-Path $dir 'kbm-autoswitch.ps1'

$action   = New-ScheduledTaskAction -Execute 'conhost.exe' `
              -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$logon    = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$watchdog = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 `
              -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

if (Get-ScheduledTask KbmAutoSwitch -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask KbmAutoSwitch
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match '\\kbm-autoswitch\.ps1' |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}
Register-ScheduledTask KbmAutoSwitch -Action $action -Trigger $logon, $watchdog -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask KbmAutoSwitch
Start-Sleep 5
(Get-ScheduledTask KbmAutoSwitch).State
Get-Content (Join-Path $dir 'kbm-autoswitch.log') -Tail 3
