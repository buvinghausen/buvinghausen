# Start the production llama-server (no admin needed).
Remove-Item C:\llama.cpp\control\stop -Force -ErrorAction SilentlyContinue
Write-Host 'start requested; model load takes ~15-90 s. Check: C:\llama.cpp\prod-status.ps1'
