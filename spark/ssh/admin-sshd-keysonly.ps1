# Phase B: turn password login OFF (keys only). Run elevated after the Chromebook key works.
Start-Transcript (Join-Path $PSScriptRoot 'admin-sshd-keysonly.log') -Force | Out-Null
try {
  $cfg = 'C:\ProgramData\ssh\sshd_config'
  (Get-Content $cfg) -replace '^PasswordAuthentication yes$', 'PasswordAuthentication no' | Set-Content $cfg -Encoding ascii
  & C:\Windows\System32\OpenSSH\sshd.exe -t; if ($LASTEXITCODE) { throw 'sshd_config test failed' }
  Restart-Service sshd
  & C:\Windows\System32\OpenSSH\sshd.exe -T 2>$null | Select-String '^passwordauthentication '
  'keys in administrators_authorized_keys:'; Get-Content C:\ProgramData\ssh\administrators_authorized_keys | ForEach-Object { ($_ -split ' ')[0,2] -join ' ' }
} catch { "ERROR: $_" }
Stop-Transcript | Out-Null
Start-Sleep 3
