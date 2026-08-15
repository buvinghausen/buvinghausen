# ---------------------------------------------------------------------------
# Run this ON EXACTLY ONE HOST if you want Windows to be the origin instead
# of WSL. Only run generate-key-ONCE on ONE machine total — everywhere else,
# copy the resulting private key over and run configure-host instead.
# ---------------------------------------------------------------------------

$Email   = "buvinghausen@users.noreply.github.com"
$SshDir  = Join-Path $env:USERPROFILE ".ssh"
$KeyPath = Join-Path $SshDir "id_ed25519_github"

Write-Host "== Generating the ONE shared GitHub SSH key (auth + signing) =="

if (Test-Path $KeyPath) {
    Write-Host "A key already exists at $KeyPath."
    Write-Host "If this is meant to be the master copy, stop and don't overwrite it."
    exit 1
}

if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }
ssh-keygen -t ed25519 -C $Email -f $KeyPath

Write-Host ""
Write-Host "== Public key -- register this TWICE on GitHub =="
Write-Host "== (https://github.com/settings/keys -> New SSH key) =="
Write-Host "==   1) Key type: Authentication Key"
Write-Host "==   2) Key type: Signing Key         <- add it a second time with this type"
Write-Host ""
Get-Content "$KeyPath.pub"
Write-Host ""
Write-Host "== Next: securely copy $KeyPath (the PRIVATE key, no .pub) to your other"
Write-Host "== hosts, then run configure-host.ps1/.sh there."
