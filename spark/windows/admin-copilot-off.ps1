# Hog-tie Copilot and the Windows AI features. Safe to re-run; run elevated FROM THE buvy ACCOUNT
# (the HKCU values land in whichever user elevates). Reboot afterwards: removing Recall needs one.
# Policy names/paths checked against Microsoft Learn 2026-11-10:
#   Policy CSP - WindowsAI, and the Edge policy reference (HubsSidebarEnabled, Microsoft365CopilotChatIconEnabled).
# Not scriptable here, done by hand (see README): Office "Enable Copilot" per app, Smart App Control.
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-copilot-off.log')
Start-Transcript $out -Force | Out-Null

function Set-Dword([string]$key, [string]$name, [int]$value) {
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  New-ItemProperty -Path $key -Name $name -Value $value -PropertyType DWord -Force | Out-Null
  "  $key\$name = $value"
}

try {
  # Policies first (instant); the slow DISM package work is last so it can't block them (2026-11-10: first run
  # sat in Get-AppxProvisionedPackage before writing a single policy).

  # 1. Windows AI (machine). Pro honours these; DisableSettingsAgent is Enterprise-only but harmless.
  'Windows AI policies (HKLM):'
  $ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
  Set-Dword $ai 'AllowRecallEnablement' 0     # removes the Recall component (restart required)
  Set-Dword $ai 'DisableAIDataAnalysis' 1     # no Recall snapshots
  Set-Dword $ai 'DisableClickToDo'      1
  Set-Dword $ai 'DisableSettingsAgent'  1
  $paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
  Set-Dword $paint 'DisableCocreator'      1
  Set-Dword $paint 'DisableGenerativeFill' 1
  Set-Dword $paint 'DisableImageCreator'   1

  # 1b. Notepad's Copilot features (Rewrite/Summarize/Write). Machine-wide; Notepad 11.2503.16+ ("Manage AI features
  #     in Notepad", Microsoft Learn, checked 2026-11-11).
  'Notepad AI policy (HKLM):'
  Set-Dword 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1

  # 2. Windows AI (user). TurnOffWindowsCopilot is deprecated and doesn't touch the new app; kept as a backstop.
  'Windows AI policies (HKCU):'
  Set-Dword 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
  Set-Dword 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'      'DisableClickToDo'      1
  Set-Dword 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'      'DisableAIDataAnalysis' 1

  # 3. Edge. HubsSidebarEnabled / Microsoft365CopilotChatIconEnabled are per-profile policies that do NOT
  #    apply to a profile signed in with a personal Microsoft account; blocking the Copilot extension is
  #    machine-wide and is what actually removes it there.
  'Edge policies (HKLM):'
  $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
  Set-Dword $edge 'HubsSidebarEnabled'                0
  Set-Dword $edge 'Microsoft365CopilotChatIconEnabled' 0
  Set-Dword $edge 'EdgeEntraCopilotPageContext'       0
  $block = "$edge\ExtensionInstallBlocklist"
  $copilotExt = 'ofefcgjbeghpigppfmkologfjadafddi'
  if (-not (Test-Path $block)) { New-Item -Path $block -Force | Out-Null }
  $entries = (Get-Item $block).Property | ForEach-Object { [pscustomobject]@{ N = $_; V = (Get-ItemPropertyValue $block $_) } }
  if (@($entries | Where-Object V -eq $copilotExt)) { "  $block already blocks $copilotExt" }
  else {
    $next = 1; while (@($entries | Where-Object N -eq "$next")) { $next++ }
    New-ItemProperty -Path $block -Name "$next" -Value $copilotExt -PropertyType String -Force | Out-Null
    "  $block\$next = $copilotExt"
  }

  # 3b. OneDrive: removed 2026-11-10, but OneDriveSetup.exe still ships in System32 and can come back with a
  #     feature update or a new profile. "Prevent the usage of OneDrive for file storage" (Policy CSP -
  #     System/DisableOneDriveFileSync; Pro supported) stops it syncing or appearing in Explorer/file pickers.
  'OneDrive policy (HKLM):'
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1

  # 4. Copilot app: uninstall, and deprovision so feature updates / new profiles don't bring it back.
  #    (RemoveMicrosoftCopilotApp policy is Enterprise/Education only - not this Pro box.)
  'Copilot app packages:'
  $pattern = '^Microsoft\.Copilot$|^Microsoft\.Windows\.Ai\.Copilot\.Provider$'
  $pkgs = @(Get-AppxPackage -AllUsers | Where-Object { $_.Name -match $pattern })
  if (-not $pkgs) { '  none installed' }
  foreach ($p in $pkgs) { Remove-AppxPackage -Package $p.PackageFullName -AllUsers; "  removed $($p.PackageFullName)" }
  # Get-AppxProvisionedPackage hung indefinitely here (2026-11-10, pwsh 7.6, build 28000: DismHost exited,
  # cmdlet never returned). Call dism.exe directly with a hard timeout instead.
  function Invoke-Dism([string[]]$dismArgs, [int]$timeoutSec = 180) {
    $o = Join-Path $env:TEMP "copilot-off-dism-$PID.txt"
    $p = Start-Process "$env:SystemRoot\System32\dism.exe" -ArgumentList (@('/Online', '/English') + $dismArgs) `
      -NoNewWindow -PassThru -RedirectStandardOutput $o
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
      $p.Kill(); "  dism $($dismArgs[0]) timed out after ${timeoutSec}s - skipped"; return $null }
    $text = Get-Content $o -Raw; Remove-Item $o -EA SilentlyContinue
    [pscustomobject]@{ Exit = $p.ExitCode; Text = $text }
  }
  "  listing provisioned packages via dism.exe (timeout 180s) - $(Get-Date -Format HH:mm:ss)"
  $r = Invoke-Dism @('/Get-ProvisionedAppxPackages')
  if ($r -is [string]) { $r }
  elseif ($r.Exit -ne 0) { "  dism exit $($r.Exit) - skipped" }
  else {
    $prov = @([regex]::Matches("$($r.Text)",'(?m)^PackageName\s*:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } |
      Where-Object { ($_ -split '_')[0] -match $pattern })
    if (-not $prov) { '  none provisioned' }
    foreach ($name in $prov) {
      $d = Invoke-Dism @('/Remove-ProvisionedAppxPackage', "/PackageName:$name")
      if ($d -is [string]) { $d } else { "  deprovision $name -> dism exit $($d.Exit)" }
    }
  }

  'Done. Reboot to finish removing Recall; restart Edge and check edge://policy.'
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
