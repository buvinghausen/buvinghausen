# Run elevated in Windows PowerShell 5.1. Creates the Hermes backup SMB share and restarts llama-server.
# The hermes-backup password is entered at a hidden prompt (paste from Bitwarden); it is never written anywhere.
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-smb.log')
$user  = 'hermes-backup'
$share = 'hermes-backup$'
$path  = 'C:\Backups\hermes'
$mac   = '100.110.233.121'
$owner = 'buvy'

# --- password prompt (before transcript starts, so nothing about it is logged) ---
do {
  $p1 = Read-Host "Paste the '$user' password from Bitwarden" -AsSecureString
  $p2 = Read-Host 'Paste it again to confirm' -AsSecureString
  $s1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
  $s2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
  $match = ($s1 -ceq $s2) -and $s1.Length -ge 16
  Remove-Variable s1, s2
  if (-not $match) { Write-Host 'Passwords did not match or are shorter than 16 characters - try again.' -ForegroundColor Yellow }
} until ($match)

Start-Transcript $out -Force | Out-Null
try {
  # 1. Local account: no group membership (so no console/RDP logon), hidden from sign-in screen
  if (Get-LocalUser -Name $user -EA SilentlyContinue) {
    Set-LocalUser -Name $user -Password $p1 -PasswordNeverExpires $true; "account existed: password updated"
  } else {
    New-LocalUser -Name $user -Password $p1 -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires `
      -Description 'SMB-only: Hermes backups from M6 mini' | Out-Null; "account created"
  }
  "group memberships: " + ((Get-LocalGroup | Where-Object { (Get-LocalGroupMember $_ -EA SilentlyContinue).Name -match "\\$user$" } | ForEach-Object Name) -join ', ')
  $ul = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
  New-Item $ul -Force | Out-Null; New-ItemProperty $ul -Name $user -Value 0 -PropertyType DWord -Force | Out-Null
  "hidden from sign-in screen"

  # 2. Folder with explicit ACL (no inheritance)
  New-Item -ItemType Directory -Force $path | Out-Null
  icacls $path /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' "${owner}:(OI)(CI)F" "${user}:(OI)(CI)M" | Out-Null
  "folder ACL:"; (Get-Acl $path).Access | ForEach-Object { "  $($_.IdentityReference) $($_.FileSystemRights)" }

  # 3. SMB share, encrypted, only hermes-backup (+ Administrators)
  if (Get-SmbShare -Name $share -EA SilentlyContinue) { Remove-SmbShare -Name $share -Force }
  New-SmbShare -Name $share -Path $path -ChangeAccess "$env:COMPUTERNAME\$user" -FullAccess 'Administrators' `
    -EncryptData $true -FolderEnumerationMode AccessBased | Out-Null
  "share: " + ((Get-SmbShareAccess -Name $share | ForEach-Object { "$($_.AccountName)=$($_.AccessRight)" }) -join ', ')
  "server service: " + (Get-Service LanmanServer).Status

  # 4. Firewall: SMB only from the Mac's Tailscale IP
  Get-NetFirewallRule -DisplayName 'SMB hermes-backup (M6 mini via Tailscale)' -EA SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'SMB hermes-backup (M6 mini via Tailscale)' -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort 445 -RemoteAddress $mac -Profile Any | Out-Null
  "firewall rule created"
  "other ENABLED inbound rules on 445 (should be none):"
  Get-NetFirewallPortFilter -Protocol TCP | Where-Object LocalPort -eq '445' | Get-NetFirewallRule |
    Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.DisplayName -notmatch 'hermes-backup' } |
    ForEach-Object { "  $($_.DisplayName) [$($_.Profile)] action=$($_.Action)" }

  # 5. Restart llama-server so --n-predict takes effect
  Stop-ScheduledTask -TaskName 'llama-server'
  Get-Process llama-server -EA SilentlyContinue | Stop-Process -Force
  Start-Sleep 3
  Start-ScheduledTask -TaskName 'llama-server'
  "llama-server task restarted"
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null; Remove-Variable p1, p2 -EA SilentlyContinue }
Read-Host 'Done - press Enter to close'
