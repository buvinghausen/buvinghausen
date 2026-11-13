# Services sweep: never-used services Disabled, maybe-used services Manual (start on demand). Run elevated (pwsh 7).
# First run saves the original state of every target to services-baseline.json; admin-services-restore.ps1 puts it back.
$here = $PSScriptRoot
$baseline = Join-Path $here 'services-baseline.json'
$log = Join-Path $here 'services-sweep.log'

$disable = @(
  'Spooler', 'MapsBroker', 'PhoneSvc', 'RasMan', 'SstpSvc', 'SSDPSRV', 'FDResPub', 'fdPHost',
  'NcdAutoSetup', 'lmhosts', 'QWAVE', 'InventorySvc', 'PcaSvc', 'wuqisvc', 'WSearch'
)
$manual = @(
  'SysMain', 'WSAIFabricSvc', 'OptionsPlusUpdaterService', 'DellTechHub', 'DellClientManagementService',
  'SurfaceExperienceService-76.10212.108.3',
  'WSLService', 'vmcompute', 'hns', 'nvagent', 'CodexSandboxService.OpenAI.Codex'
)

$targets = $disable + $manual
# Existing baseline entries are kept (they hold the original state); targets added later are appended before they change.
$saved = @(if (Test-Path $baseline) { Get-Content $baseline -Raw | ConvertFrom-Json })
$new = $targets | Where-Object { $saved.Name -notcontains $_ } | ForEach-Object { Get-Service $_ -ErrorAction SilentlyContinue } |
  ForEach-Object { [pscustomobject][ordered]@{ Name = $_.Name; StartType = "$($_.StartType)"; Status = "$($_.Status)" } }
if ($new) {
  ConvertTo-Json @($saved + $new) | Set-Content -Encoding utf8NoBOM $baseline
  "baseline: added $(@($new).Count) to $baseline"
}

$results = foreach ($name in $targets) {
  $want = if ($disable -contains $name) { 'Disabled' } else { 'Manual' }
  $err = @()
  try { Set-Service $name -StartupType $want -ErrorAction Stop } catch { $err += "set: $($_.Exception.Message)" }
  try { Stop-Service $name -Force -ErrorAction Stop } catch { $err += "stop: $($_.Exception.Message)" }
  $s = Get-Service $name -ErrorAction SilentlyContinue
  [pscustomobject]@{ Name = $name; Want = $want; StartType = $s.StartType; Status = $s.Status; Error = ($err -join ' | ') }
}
$results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Tee-Object -FilePath $log
Read-Host 'Done. Press Enter to close'
