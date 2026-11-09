# Phase A: OpenSSH server on this machine. Run elevated (pwsh or Windows PowerShell). Log next to this script.
# - service Automatic + running
# - only user buvy may log in; password login TEMPORARILY on (to bootstrap the key), turned off by admin-sshd-keysonly.ps1
# - admin key file C:\ProgramData\ssh\administrators_authorized_keys (Admins/SYSTEM only)
# - default shell = Windows PowerShell
# - firewall: Windows' allow-any rule disabled; port 22 only from the tailnet (100.64.0.0/10, fd7a:115c:a1e0::/48)
Start-Transcript (Join-Path $PSScriptRoot 'admin-sshd-setup.log') -Force | Out-Null
try {
  $ErrorActionPreference = 'Stop'
  Set-Service sshd -StartupType Automatic
  if (-not (Test-Path C:\ProgramData\ssh\sshd_config)) { Start-Service sshd; Start-Sleep 3; Stop-Service sshd }   # first start generates config + host keys
  $cfg = 'C:\ProgramData\ssh\sshd_config'
  Copy-Item $cfg "$cfg.bak-$(Get-Date -f yyyyMMdd-HHmm)"
  $body = (Get-Content $cfg) | Where-Object { $_ -notmatch '^# >>> spark' -and $_ -notmatch '^(AllowUsers|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|KbdInteractiveAuthentication) ' }
  # sshd uses the FIRST value it sees, so our settings go at the top (before the stock Match block)
  $head = @(
    '# >>> spark: managed settings (admin-sshd-setup.ps1)',
    'AllowUsers buvy',
    'PubkeyAuthentication yes',
    'PasswordAuthentication yes',
    'KbdInteractiveAuthentication no',
    'PermitEmptyPasswords no')
  Set-Content $cfg ($head + $body) -Encoding ascii
  $ak = 'C:\ProgramData\ssh\administrators_authorized_keys'
  if (-not (Test-Path $ak)) { New-Item -ItemType File $ak | Out-Null }
  icacls $ak /inheritance:r /grant 'Administrators:F' 'SYSTEM:F'
  New-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
  Disable-NetFirewallRule -Name OpenSSH-Server-In-TCP
  Get-NetFirewallRule -DisplayName 'OpenSSH (tailnet only)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'OpenSSH (tailnet only)' -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10, 'fd7a:115c:a1e0::/48' -Action Allow -Profile Any | Out-Null
  & C:\Windows\System32\OpenSSH\sshd.exe -t; if ($LASTEXITCODE) { throw 'sshd_config test failed' }
  Start-Service sshd
  '--- result ---'
  Get-Service sshd | Format-Table Name, Status, StartType
  & C:\Windows\System32\OpenSSH\sshd.exe -T 2>$null | Select-String '^(allowusers|passwordauthentication|pubkeyauthentication|permitemptypasswords) '
  Get-NetFirewallRule | Where-Object { $_.DisplayName -match 'ssh' } | Format-Table DisplayName, Enabled, Profile
  icacls $ak
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
