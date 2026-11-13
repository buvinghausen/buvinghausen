# Undo admin-services-sweep.ps1: restore each service's start type from services-baseline.json, restart those that were running. Run elevated (pwsh 7).
$baseline = Join-Path $PSScriptRoot 'services-baseline.json'
foreach ($s in (Get-Content $baseline -Raw | ConvertFrom-Json)) {
  try { Set-Service $s.Name -StartupType $s.StartType -ErrorAction Stop } catch { "$($s.Name) set: $($_.Exception.Message)" }
  if ($s.Status -eq 'Running') {
    try { Start-Service $s.Name -ErrorAction Stop } catch { "$($s.Name) start: $($_.Exception.Message)" }
  }
  Get-Service $s.Name | Select-Object Name, StartType, Status
}
Read-Host 'Done. Press Enter to close'
