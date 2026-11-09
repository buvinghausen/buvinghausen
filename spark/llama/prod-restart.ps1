# Restart the production llama-server (no admin needed). Does not clear a stop flag.
Get-Date -Format o | Set-Content C:\llama.cpp\control\restart
Write-Host 'restart requested; the supervisor acts within ~5 s. Check: C:\llama.cpp\prod-status.ps1'
