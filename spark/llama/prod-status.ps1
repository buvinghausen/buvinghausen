# Show the production llama-server state (no admin needed).
Get-Content C:\llama.cpp\logs\status.txt
if (Test-Path C:\llama.cpp\control\stop) { Write-Host 'stop flag: PRESENT (run prod-start.ps1 to start)' }
Write-Host ("port 9931 listening: " + [bool](Get-NetTCPConnection -LocalPort 9931 -State Listen -ErrorAction SilentlyContinue))
