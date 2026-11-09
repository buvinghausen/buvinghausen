# Builds a self-contained, one-shot "SSH server, keys only, tailnet only" setup script for another Windows machine.
# Usage: make-sshd-bundle.ps1 -Target xps-15-9510 -Keys skywalker,surfacespark,pebble
param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string[]]$Keys)
$kd = 'C:\Users\buvy\ssh-keys'
$lines = foreach ($k in $Keys) {
  $l = (Get-Content "$kd\$k.pub" -ErrorAction Stop | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
  if ($l -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]{60,} \S+$') { throw "bad key file $k.pub" }
  $l
}
$keyBlock = ($lines | ForEach-Object { "  '$_'" }) -join ",`r`n"
$out = Join-Path $PSScriptRoot "setup-sshd-$Target.ps1"
@"
# One-shot OpenSSH server setup for $Target. Run ONCE in an ELEVATED PowerShell on ${Target}:
#   powershell -ExecutionPolicy Bypass -File .\setup-sshd-$Target.ps1
# - installs the in-box OpenSSH Server (serviced by Windows Update), service Automatic + running
# - only the signed-in account may log in, public keys only (no passwords)
# - allowed keys: $($Keys -join ', ')
# - default shell Windows PowerShell; firewall: port 22 only from the tailnet (100.64.0.0/10, fd7a:115c:a1e0::/48)
`$ErrorActionPreference = 'Stop'
`$keys = @(
$keyBlock
)
`$log = Join-Path `$PSScriptRoot 'setup-sshd.log'
Start-Transcript `$log -Force | Out-Null
try {
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { throw 'run this from an elevated (Administrator) PowerShell' }
  if (-not (Test-Path C:\Windows\System32\OpenSSH\sshd.exe)) {
    dism.exe /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart
    if (-not (Test-Path C:\Windows\System32\OpenSSH\sshd.exe)) { throw 'OpenSSH Server install failed' }
  }
  Set-Service sshd -StartupType Automatic
  `$cfg = 'C:\ProgramData\ssh\sshd_config'
  if (-not (Test-Path `$cfg)) { Start-Service sshd; Start-Sleep 3; Stop-Service sshd }
  Copy-Item `$cfg "`$cfg.bak-`$(Get-Date -f yyyyMMdd-HHmm)"
  `$user = `$env:USERNAME.ToLower()
  `$body = (Get-Content `$cfg) | Where-Object { `$_ -notmatch '^# >>> managed' -and `$_ -notmatch '^(AllowUsers|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|KbdInteractiveAuthentication) ' }
  `$head = @('# >>> managed settings (setup-sshd)', "AllowUsers `$user", 'PubkeyAuthentication yes', 'PasswordAuthentication no', 'KbdInteractiveAuthentication no', 'PermitEmptyPasswords no')
  Set-Content `$cfg (`$head + `$body) -Encoding ascii
  # admins use the shared admin key file (admin-only ACL); standard users use ~\.ssh\authorized_keys
  `$isAdminUser = [bool](Get-LocalGroupMember -SID S-1-5-32-544 | Where-Object { `$_.Name -match "\\`$([regex]::Escape(`$env:USERNAME))`$" })
  if (`$isAdminUser) {
    `$ak = 'C:\ProgramData\ssh\administrators_authorized_keys'
    if (-not (Test-Path `$ak)) { New-Item -ItemType File `$ak | Out-Null }
    `$have = @(Get-Content `$ak)
    foreach (`$k in `$keys) { if (`$have -notcontains `$k) { Add-Content `$ak `$k -Encoding ascii } }
    icacls `$ak /inheritance:r /grant 'Administrators:F' 'SYSTEM:F' | Out-Null
  } else {
    `$d = Join-Path `$env:USERPROFILE '.ssh'; New-Item -ItemType Directory -Force `$d | Out-Null
    `$ak = Join-Path `$d 'authorized_keys'
    `$have = @(Get-Content `$ak -ErrorAction SilentlyContinue)
    foreach (`$k in `$keys) { if (`$have -notcontains `$k) { Add-Content `$ak `$k -Encoding ascii } }
  }
  New-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
  Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue | Disable-NetFirewallRule
  Get-NetFirewallRule -DisplayName 'OpenSSH (tailnet only)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'OpenSSH (tailnet only)' -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10, 'fd7a:115c:a1e0::/48' -Action Allow -Profile Any | Out-Null
  & C:\Windows\System32\OpenSSH\sshd.exe -t; if (`$LASTEXITCODE) { throw 'sshd_config test failed' }
  Start-Service sshd
  '--- result ---'
  "user: `$user (admin: `$isAdminUser)  key file: `$ak"
  Get-Service sshd | Format-Table Name, Status, StartType
  & C:\Windows\System32\OpenSSH\sshd.exe -T 2>`$null | Select-String '^(allowusers|passwordauthentication|pubkeyauthentication) '
  & C:\Windows\System32\OpenSSH\ssh-keygen.exe -lf `$ak
  Get-NetFirewallRule | Where-Object { `$_.DisplayName -match 'ssh' } | Format-Table DisplayName, Enabled, Profile
  'DONE'
} catch { "ERROR: `$_" }
Stop-Transcript | Out-Null
"@ | Set-Content $out -Encoding ascii
"wrote $out"
