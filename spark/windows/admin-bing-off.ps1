# Excise Bing: web results in Start search, search highlights, Widgets (MSN feed), the Bing app.
# Safe to re-run; run elevated FROM THE buvy ACCOUNT (HKCU values land in whichever user elevates).
# Sign out (or reboot) afterwards so Start/Search pick up the policies.
# Policy names/editions checked against Microsoft Learn 2026-11-11: Policy CSP - Search, Policy CSP - NewsAndInterests.
# By hand (no Pro policy): lock-screen Spotlight - Settings > Personalization > Lock screen > Picture, and clear
# "Get fun facts, tips, tricks, and more on your lock screen".
# Avoid the DISM PowerShell cmdlets on this box: under pwsh 7 they loop on 0x80040154 (see README). dism.exe only.
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-bing-off.log')
Start-Transcript $out -Force | Out-Null

# Per-value failures are logged, not fatal: 2026-11-11 an elevated write to HKLM\...\Policies\Microsoft\Dsh was
# refused ("unauthorized operation") despite Administrators:FullControl, and that aborted the app removal below.
function Set-Dword([string]$key, [string]$name, [int]$value) {
  try {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name $name -Value $value -PropertyType DWord -Force | Out-Null
    "  $key\$name = $value"
  } catch { "  BLOCKED $key\$name = $value : $($_.Exception.Message)" }
}

function Invoke-Dism([string[]]$dismArgs, [int]$timeoutSec = 180) {
  $o = Join-Path $env:TEMP "bing-off-dism-$PID.txt"
  $p = Start-Process "$env:SystemRoot\System32\dism.exe" -ArgumentList (@('/Online', '/English') + $dismArgs) `
    -NoNewWindow -PassThru -RedirectStandardOutput $o
  if (-not $p.WaitForExit($timeoutSec * 1000)) {
    $p.Kill(); "  dism $($dismArgs[0]) timed out after ${timeoutSec}s - skipped"; return $null }
  $text = Get-Content $o -Raw; Remove-Item $o -EA SilentlyContinue
  [pscustomobject]@{ Exit = $p.ExitCode; Text = $text }
}

try {
  # 1. Windows Search (machine).
  'Search policies (HKLM):'
  $ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
  Set-Dword $ws 'EnableDynamicContentInWSB' 0   # AllowSearchHighlights=0 (Pro supported)
  Set-Dword $ws 'AllowCloudSearch'          0   # Pro supported
  Set-Dword $ws 'ConnectedSearchUseWeb'     0   # DoNotUseWebResults - Enterprise/Education per CSP; harmless backstop
  Set-Dword $ws 'DisableWebSearch'          1   # legacy; harmless backstop

  # 2. Windows Search (user). DisableSearchBoxSuggestions is the Explorer policy that, on Pro, actually stops
  #    Start search from querying Bing. BingSearchEnabled is the old per-user switch; backstop.
  'Search policies (HKCU):'
  Set-Dword 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'          'DisableSearchBoxSuggestions' 1
  Set-Dword 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'      'BingSearchEnabled'           0

  # 3. Widgets = the MSN/Bing feed. AllowNewsAndInterests is Pro supported; the other two are preview, harmless.
  'Widgets policies (HKLM):'
  $dsh = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
  Set-Dword $dsh 'AllowNewsAndInterests'      0
  Set-Dword $dsh 'DisableWidgetsBoard'        1
  Set-Dword $dsh 'DisableWidgetsOnLockScreen' 1

  # 4. Apps: uninstall for all users, then deprovision so feature updates / new profiles don't bring them back.
  #    Deliberately NOT touched: Microsoft.StartExperiencesApp and Microsoft.WidgetsPlatformRuntime (Start/shell deps).
  'Bing / Widgets app packages:'
  $pattern = '^Microsoft\.BingSearch$|^Microsoft\.BingNews$|^Microsoft\.BingWeather$|^MicrosoftWindows\.Client\.WebExperience$'
  $pkgs = @(Get-AppxPackage -AllUsers | Where-Object { $_.Name -match $pattern })
  if (-not $pkgs) { '  none installed' }
  # -AllUsers was refused ("Access is denied") for all four on 2026-11-11; removing for the current user worked
  # (even un-elevated). So: try all users, fall back to this user.
  foreach ($p in $pkgs) {
    try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; "  removed (all users) $($p.Name)" }
    catch {
      try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; "  removed (this user) $($p.Name)" }
      catch { "  could not remove $($p.Name): $($_.Exception.Message)" }
    }
  }
  "  listing provisioned packages via dism.exe (timeout 180s) - $(Get-Date -Format HH:mm:ss)"
  $r = Invoke-Dism @('/Get-ProvisionedAppxPackages')
  if ($r -is [string]) { $r }
  elseif ($r.Exit -ne 0) { "  dism exit $($r.Exit) - skipped" }
  else {
    $prov = @([regex]::Matches("$($r.Text)", '(?m)^PackageName\s*:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } |
      Where-Object { ($_ -split '_')[0] -match $pattern })
    if (-not $prov) { '  none provisioned' }
    foreach ($name in $prov) {
      $d = Invoke-Dism @('/Remove-ProvisionedAppxPackage', "/PackageName:$name")
      if ($d -is [string]) { $d } else { "  deprovision $name -> dism exit $($d.Exit)" }
    }
  }

  'Done. Sign out or reboot so Start/Search pick up the policies.'
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
