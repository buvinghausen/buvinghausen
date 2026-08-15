# ---------------------------------------------------------------------------
# GitHub SSH key setup — Windows (PowerShell)
#
# Run this in a Windows PowerShell terminal (not WSL) if you also commit
# from native Windows tools (PowerShell, Git Bash, VS Code without Remote-WSL).
#
# It will NOT overwrite an existing key at the target path.
# You will be prompted once to set a passphrase for the new key — that's
# expected and recommended.
# ---------------------------------------------------------------------------

$Email   = "buvinghausen@users.noreply.github.com"
$SshDir  = Join-Path $env:USERPROFILE ".ssh"
$KeyPath = Join-Path $SshDir "id_ed25519_github"

Write-Host "== GitHub SSH key setup (Windows) =="

if (-not (Test-Path $SshDir)) {
    New-Item -ItemType Directory -Path $SshDir | Out-Null
}

if (Test-Path $KeyPath) {
    Write-Host "A key already exists at $KeyPath — skipping generation."
    Write-Host "(Delete $KeyPath and $KeyPath.pub first if you want to regenerate.)"
} else {
    ssh-keygen -t ed25519 -C $Email -f $KeyPath
}

# Enable and start the built-in OpenSSH Authentication Agent service
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $KeyPath

# Configure SSH to use this key specifically for github.com
$ConfigFile = Join-Path $SshDir "config"
if (-not (Test-Path $ConfigFile)) {
    New-Item -ItemType File -Path $ConfigFile | Out-Null
}
$existing = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
if ($existing -notmatch "Host github\.com") {
@"

Host github.com
  HostName github.com
  User git
  IdentityFile $KeyPath
  AddKeysToAgent yes
"@ | Add-Content -Path $ConfigFile
    Write-Host "Added a github.com entry to $ConfigFile"
}

Write-Host ""
Write-Host "== Done. Your PUBLIC key (safe to share) — paste this into =="
Write-Host "== GitHub > Settings > SSH and GPG keys > New SSH key (type: Authentication Key) =="
Write-Host ""
Get-Content "$KeyPath.pub"
