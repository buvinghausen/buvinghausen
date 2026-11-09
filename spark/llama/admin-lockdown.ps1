# Lock down C:\llama.cpp: Administrators + SYSTEM full control, Users read/execute only. Run elevated.
# api-key.txt keeps its own (protected) ACL. Output is logged next to this script.
$log = Join-Path $PSScriptRoot 'admin-lockdown.log'
Start-Transcript $log -Force | Out-Null
icacls C:\llama.cpp /setowner '*S-1-5-32-544' /T /C /Q
icacls C:\llama.cpp /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /C
"--- verify: any write access for non-admin principals? ---"
$bad = Get-ChildItem C:\llama.cpp -Recurse -Force | Get-Acl | ForEach-Object {
  foreach ($a in $_.Access) {
    if ($a.IdentityReference -notmatch 'Administrators|SYSTEM' -and $a.FileSystemRights.ToString() -match 'Write|Modify|FullControl|ChangePermissions|TakeOwnership') { "$($_.Path): $($a.IdentityReference) $($a.FileSystemRights)" }
  } }
if ($bad) { $bad } else { 'none - locked down' }
icacls C:\llama.cpp
icacls C:\llama.cpp\api-key.txt
Stop-Transcript | Out-Null
Start-Sleep 3
