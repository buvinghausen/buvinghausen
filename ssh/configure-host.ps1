# ---------------------------------------------------------------------------
# Run this on Windows hosts that already have the shared private key at
# $env:USERPROFILE\.ssh\id_ed25519_github (either generated here with
# generate-key-ONCE.ps1, or securely copied over). Wires up the OpenSSH
# agent service and git's SSH-based commit signing — no GPG involved.
# ---------------------------------------------------------------------------

$Email   = "buvinghausen@users.noreply.github.com"
$Name    = "Buvy"
$SshDir  = Join-Path $env:USERPROFILE ".ssh"
$KeyPath = Join-Path $SshDir "id_ed25519_github"

if (-not (Test-Path $KeyPath)) {
    Write-Host "No key found at $KeyPath — copy the private key here first (see the setup guide), then re-run."
    exit 1
}

Write-Host "== Enabling and starting the OpenSSH Authentication Agent =="
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $KeyPath

Write-Host "== SSH config for github.com =="
$ConfigFile = Join-Path $SshDir "config"
if (-not (Test-Path $ConfigFile)) { New-Item -ItemType File -Path $ConfigFile | Out-Null }
$existing = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
if ($existing -notmatch "Host github\.com") {
@"

Host github.com
  HostName github.com
  User git
  IdentityFile $KeyPath
  AddKeysToAgent yes
"@ | Add-Content -Path $ConfigFile
    Write-Host "Added github.com entry to $ConfigFile"
}

Write-Host "== git config: SSH-based signing (no GPG) =="
git config --global user.name $Name
git config --global user.email $Email
git config --global gpg.format ssh
git config --global user.signingkey "$KeyPath.pub"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

Write-Host "== Local signature verification (optional, cosmetic) =="
$AllowedSigners = Join-Path $SshDir "allowed_signers"
$PubKeyContent = Get-Content "$KeyPath.pub" -Raw
$Line = "$Email $PubKeyContent".Trim()
if (-not (Test-Path $AllowedSigners)) { New-Item -ItemType File -Path $AllowedSigners | Out-Null }
$existingSigners = Get-Content $AllowedSigners -Raw -ErrorAction SilentlyContinue
if ($existingSigners -notmatch [regex]::Escape($Email)) {
    Add-Content -Path $AllowedSigners -Value $Line
}
git config --global gpg.ssh.allowedSignersFile "$AllowedSigners"

Write-Host ""
Write-Host "== Done. Test with: =="
Write-Host "  ssh -T git@github.com"
Write-Host "  git commit --allow-empty -m test; git log --show-signature -1"
