$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-fix.log')
Start-Transcript $out -Force | Out-Null
try {
  # 1. Remove the auto-created allow-any rules for llama-server.exe (from Windows' first-listen prompt)
  $auto = Get-NetFirewallRule -DisplayName 'llama-server' -EA SilentlyContinue
  "removing $(@($auto).Count) auto-created rule(s): " + (($auto | ForEach-Object Name) -join ', ')
  $auto | Remove-NetFirewallRule
  'remaining llama-server rules:'
  Get-NetFirewallRule -DisplayName 'llama-server*' | ForEach-Object {
    $a = $_ | Get-NetFirewallAddressFilter; $p = $_ | Get-NetFirewallPortFilter
    "  {0} | {1} {2} | port {3} | from {4}" -f $_.DisplayName, $_.Direction, $_.Action, $p.LocalPort, $a.RemoteAddress }

  # 2. Point the task at built-in Windows PowerShell (Store pwsh is not runnable by SYSTEM)
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $action = New-ScheduledTaskAction -Execute $ps -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\llama.cpp\serve-qwen38.ps1' -WorkingDirectory 'C:\llama.cpp'
  Set-ScheduledTask -TaskName 'llama-server' -Action $action | Out-Null
  'task action updated to Windows PowerShell'
  Start-ScheduledTask -TaskName 'llama-server'
  Start-Sleep 5
  $t = Get-ScheduledTask -TaskName 'llama-server'; $i = $t | Get-ScheduledTaskInfo
  "task state: $($t.State)  user: $($t.Principal.UserId)  lastResult: 0x{0:X}" -f $i.LastTaskResult
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
