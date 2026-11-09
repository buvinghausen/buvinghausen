# Append public key C:\Users\buvy\ssh-keys\<name>.pub to the admin authorized_keys file. Run elevated.
param([Parameter(Mandatory)][string]$Name)
Start-Transcript (Join-Path $PSScriptRoot 'admin-sshd-addkey.log') -Force | Out-Null
try {
  $src = "C:\Users\buvy\ssh-keys\$Name.pub"
  $ak  = 'C:\ProgramData\ssh\administrators_authorized_keys'
  $lines = @(Get-Content $src | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($lines.Count -ne 1 -or $lines[0] -notmatch '^ssh-(ed25519|rsa) [A-Za-z0-9+/=]{60,} ?\S*$') { throw "unexpected content in $src (need exactly one ssh-ed25519 line)" }
  $existing = @(Get-Content $ak -ErrorAction SilentlyContinue)
  if ($existing -contains $lines[0]) { 'key already present' } else { Add-Content $ak $lines[0] -Encoding ascii; 'key added' }
  & C:\Windows\System32\OpenSSH\ssh-keygen.exe -lf $ak
  icacls $ak
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
