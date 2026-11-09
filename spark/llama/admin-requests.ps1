# Run elevated. Read-only: lists active power requests (who is keeping the display / system awake) and overrides.
Start-Transcript (Join-Path $PSScriptRoot 'admin-requests.log') -Force | Out-Null
powercfg /requests
'--- overrides ---'; powercfg /requestsoverride
Stop-Transcript | Out-Null
