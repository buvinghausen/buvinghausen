# Stop the production llama-server (no admin needed). It stays stopped, even across reboots, until prod-start.ps1.
New-Item -ItemType File -Force C:\llama.cpp\control\stop | Out-Null
Write-Host 'stop requested; the supervisor acts within ~5 s. Check: C:\llama.cpp\prod-status.ps1'
